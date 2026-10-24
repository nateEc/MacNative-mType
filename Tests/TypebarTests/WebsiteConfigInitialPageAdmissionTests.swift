import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigInitialPageAdmissionTests: XCTestCase {
  private enum Failure: Error { case notPrepared, notCommitted }
  @MainActor private final class Fixture {
    let suite = "typebar.initial-page.\(UUID())"
    let defaults: UserDefaults, settings: AppSettings, account: AccountSession
    let page = PracticePageSessionStore()
    let environment: WebsiteConfigEnvironmentSource
    var window: WebsiteConfigPracticeScopeSource.Window
    var onRead: (() -> Void)?
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-initial-page-\(UUID())")
    let register: WebsiteConfigFileRegister
    lazy var source = WebsiteConfigPracticeScopeSource(environment: environment, readWindow: { [unowned self] in
      onRead?(); return window
    })
    lazy var coordinator = WebsiteConfigCommitCoordinator(router: settings.preferenceConfigurationSaves, register: register,
      environment: { [environment] in environment.read() })
    init() throws {
      defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      settings = .init(defaults: defaults, localBackgroundStore: .inMemory())
      account = .init(defaults: defaults)
      environment = .init(settings: settings, account: account, pointsPerRem: 16, documentComplete: true, development: false)
      window = .init(owner: page.owner, customRecoveryBlocked: false,
        custom: .explicit(.init(source: .editor("new owned text"), configuration: .init(mode: .custom,
          duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())),
          finiteTextSource: nil, preservesSpelling: false, recoveryBlocked: false))
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory)
      settings.preferenceConfigurationSaves.register(owner: page.owner, save: { XCTFail("No legacy save") })
      page.attach(to: settings.preferenceConfigurationSaves)
      var state = page.state
      state.session = TypingSession(configuration: .words(3), prompt: "ab cd ef")
      page.replace(state)
    }
    func close() {
      onRead = nil
      source.stop(); environment.stop(); page.detach()
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: directory)
    }
    func input(_ text: String) {
      var state = page.state; state.session.insertBatch(text); page.replace(state)
    }
    func ticket() throws -> WebsiteConfigCommitCoordinator.Prepared {
      try coordinator.prepare(#"{"mode":"custom"}"#, for: page, refreshingWith: source)
    }
    func resources() throws -> WebsiteConfigCommitCoordinator.ResourcesPrepared {
      try coordinator.prepareResources(for: ticket(), localFont: .absent, localBackground: .absent)
    }
  }

  func testFirstImportBuildsFromActualWindowAndCurrentBooksWithoutPriorPublication() async throws {
    let f = try Fixture(); defer { f.close() }
    XCTAssertNil(f.page.state.presentation); XCTAssertNil(f.page.state.practice)
    var state = f.page.state
    var book = state.session.liveWeakSpotScores
    book.record(character: "z", interval: 0.7, isCorrect: false)
    state.session = state.session.withWeakSpotScores(book).withWordDecorationState(.init(spanishClosing: "!"))
    f.page.replace(state)
    let original = f.page.state.session.automaticInputAttemptID
    let ready = try await f.coordinator.preparePractice(for: f.resources())
    XCTAssertEqual(ready.session.prompt, "new owned text")
    XCTAssertEqual(ready.session.liveWeakSpotScores, book)
    XCTAssertEqual(ready.practice?.scope.decorationState, .init(spanishClosing: "!"))
    XCTAssertEqual(try f.register.read().state, .missing)
    guard case .committed(let publication) = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else {
      return XCTFail("First import not installed")
    }
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, original)
    XCTAssertEqual(f.page.state.session.prompt, "new owned text")
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
    XCTAssertEqual(try f.register.read().state, .available(publication.draft.projection.runtime))
  }

  func testInputDuringFirstResourceReadStopsBeforeNextReaderOrWrite() async throws {
    let f = try Fixture(); defer { f.close() }
    let ticket = try f.ticket()
    do {
      _ = try await f.coordinator.prepareResources(for: ticket,
        readLocalFont: { f.input("a"); return .absent },
        readLocalBackground: { XCTFail("Late resource read"); return .absent })
      XCTFail("Initial input overwritten")
    } catch WebsiteConfigCommitCoordinatorError.stale {}
    XCTAssertEqual(f.page.state.session.typed, "a")
    XCTAssertEqual(try f.register.read().state, .missing)
  }

  func testInitialCompositionAndInputABARejectAlreadyGeneratedCandidate() async throws {
    for composition in [false, true] {
      let f = try Fixture(); defer { f.close() }
      let ready = try await f.coordinator.preparePractice(for: f.resources())
      let attempt = f.page.state.session.automaticInputAttemptID
      if composition { f.page.noteCompositionActivity(for: attempt) }
      else {
        f.input("a")
        var state = f.page.state; state.session.deleteBackward(); f.page.replace(state)
        XCTAssertEqual(f.page.state.session.typed, "")
      }
      guard case .stale = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else {
        return XCTFail("Initial activity accepted late candidate")
      }
      XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
      XCTAssertEqual(try f.register.read().state, .missing)
    }
  }

  func testWindowAttachmentAndContentABAInvalidateInitialAdmission() async throws {
    for attachment in [false, true] {
      let f = try Fixture(); defer { f.close() }
      let ready = try await f.coordinator.preparePractice(for: f.resources())
      if attachment {
        f.page.detach(); f.page.attach(to: f.settings.preferenceConfigurationSaves)
      } else { f.window.revision = UUID() }
      guard case .stale = try f.coordinator.commit(ready, to: f.page, systemIsDark: true) else {
        return XCTFail("Retired initial window committed")
      }
      XCTAssertEqual(try f.register.read().state, .missing)
    }
  }

  func testBoundInitialCandidateCannotUseForeignScopeRawProducerOrPublishWithoutPage() async throws {
    let f = try Fixture(); defer { f.close() }
    let ticket = try f.ticket()
    XCTAssertThrowsError(try f.coordinator.commit(ticket))
    let resources = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    do {
      _ = try await f.coordinator.preparePractice(for: resources, scope: .init(customText: "foreign"))
      XCTFail("Explicit scope bypassed bound window")
    } catch WebsiteConfigCommitCoordinatorError.sessionNotReady {}
    do {
      _ = try await f.coordinator.prepareSession(for: resources) { _ in
        XCTFail("Raw producer bypassed bound window")
        return TypingSession(configuration: .words(1), prompt: "foreign")
      }
      XCTFail("Raw session accepted")
    } catch WebsiteConfigCommitCoordinatorError.sessionNotReady {}
    XCTAssertEqual(try f.register.read().state, .missing)
  }

  func testInitialRestorationBindsDiskScopeAndInputToSamePage() async throws {
    let f = try Fixture(); defer { f.close() }
    guard case .committed = try f.coordinator.commit(f.coordinator.prepare(#"{"mode":"custom"}"#)) else {
      return XCTFail("Seed failed")
    }
    let disk = try f.register.read().revision
    guard case .prepared(let ticket) = try f.coordinator.prepareRestoration(for: f.page, refreshingWith: f.source) else {
      throw Failure.notPrepared
    }
    let resources = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.preparePractice(for: resources)
    XCTAssertEqual(ready.session.prompt, "new owned text")
    f.input("a")
    guard case .stale = try f.coordinator.commit(ready, to: f.page, systemIsDark: true) else {
      return XCTFail("Cold restore overwrote first input")
    }
    XCTAssertEqual(f.page.state.session.typed, "a")
    XCTAssertEqual(try f.register.read().revision, disk)
  }

  func testNoQuitRejectionRetiresOldIntentBeforeAnyContentRead() throws {
    let f = try Fixture(); defer { f.close() }
    let old = try f.coordinator.prepare("{}")
    var state = f.page.state
    state.session = TypingSession(configuration: .words(3).with(modifiers: [.noQuit]), prompt: "ab cd ef")
    state.session.insertBatch("a"); f.page.replace(state)
    f.onRead = { XCTFail("Locked initial page read content") }
    XCTAssertThrowsError(try f.ticket()) { error in
      guard case PracticePageSessionStateError.locked = error else { return XCTFail("Unexpected: \(error)") }
    }
    guard case .stale = try f.coordinator.commit(old) else { return XCTFail("Old intent survived rejected new import") }
    XCTAssertEqual(try f.register.read().state, .missing)
    XCTAssertEqual(f.page.state.session.typed, "a")
  }

  func testContentCallbackCannotReenterOrChangePageAfterCapture() throws {
    let f = try Fixture(); defer { f.close() }
    f.onRead = {
      do { _ = try f.coordinator.prepare("{}"); XCTFail("Reentrant preparation accepted") }
      catch {
        guard case WebsiteConfigCommitCoordinatorError.reentrant = error else { return XCTFail("Unexpected: \(error)") }
      }
      f.input("a")
    }
    XCTAssertThrowsError(try f.ticket()) { error in
      guard case WebsiteConfigCommitCoordinatorError.stale = error else { return XCTFail("Unexpected: \(error)") }
    }
    XCTAssertEqual(try f.register.read().state, .missing)
  }

  func testFreshRestorationAndReimportUseSameBoundPageWithoutForeignDelivery() async throws {
    let f = try Fixture(); defer { f.close() }
    guard case .committed = try f.coordinator.commit(f.coordinator.prepare(#"{"mode":"custom"}"#)) else {
      throw Failure.notCommitted
    }
    guard case .prepared(let ticket) = try f.coordinator.prepareRestoration(for: f.page, refreshingWith: f.source) else {
      throw Failure.notPrepared
    }
    let resource = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.preparePractice(for: resource)
    let disk = try f.register.read().revision
    let other = PracticePageSessionStore()
    XCTAssertThrowsError(try f.coordinator.commit(ready, to: other, systemIsDark: false))
    XCTAssertEqual(try f.register.read().revision, disk)
    guard case .committed = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else {
      throw Failure.notCommitted
    }
    let first = f.page.state.session.automaticInputAttemptID
    let next = try await f.coordinator.preparePractice(for: f.resources())
    guard case .committed = try f.coordinator.commit(next, to: f.page, systemIsDark: false) else {
      throw Failure.notCommitted
    }
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, first)
    XCTAssertEqual(f.page.state.session.prompt, "new owned text")
  }

  func testBoundMissingRestorationDoesNotReadContentOrResurrectOlderImport() throws {
    let f = try Fixture(); defer { f.close() }
    let old = try f.coordinator.prepare("{}")
    f.onRead = { XCTFail("Missing record does not need content") }
    guard case .missing = try f.coordinator.prepareRestoration(for: f.page, refreshingWith: f.source) else {
      return XCTFail("Missing native record was synthesized")
    }
    guard case .stale = try f.coordinator.commit(old) else { return XCTFail("New restore did not retire old import") }
    XCTAssertEqual(try f.register.read().state, .missing)
  }

  func testStoppedContentSourceAndLeaseABARejectBeforeWriting() async throws {
    for stopped in [false, true] {
      let f = try Fixture(); defer { f.close() }
      let ready = try await f.coordinator.preparePractice(for: f.resources())
      if stopped { f.source.stop() }
      else {
        let router = f.settings.preferenceConfigurationSaves, other = UUID()
        router.register(owner: other, save: {})
        router.activate(owner: other); router.activate(owner: f.page.owner)
      }
      guard case .stale = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else {
        return XCTFail("Retired source or lease accepted")
      }
      XCTAssertEqual(try f.register.read().state, .missing)
    }
  }
}
