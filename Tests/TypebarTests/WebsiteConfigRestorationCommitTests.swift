import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigRestorationCommitTests: XCTestCase {
  private enum Failure: Error { case expectedPrepared, expectedCommit }
  @MainActor private final class Fixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-restore-commit-\(UUID())")
    let router = PreferenceConfigurationSaveRouter(), page = PracticePageSessionStore()
    let register: WebsiteConfigFileRegister
    var epoch = UUID()
    var context = WebsiteConfigRuntimeContext()
    var onRead: (() -> Void)?
    lazy var coordinator = WebsiteConfigCommitCoordinator(router: router, register: register,
      environment: { [unowned self] in
        onRead?()
        return .init(revision: epoch, context: context, pointsPerRem: 16)
      })
    init() throws {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory)
      router.register(owner: page.owner, save: { XCTFail("Restore must not write legacy settings") })
      page.attach(to: router)
    }
    func close() { page.detach(); try? FileManager.default.removeItem(at: directory) }
    func seed() throws {
      let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"quote","quoteLength":[0,0],"time":41,"fontSize":1.75}"#,
        pointsPerRem: 16, context: .init())
      guard case .committed = try register.commit(draft, replacing: XCTUnwrap(register.read().revision)) else {
        throw Failure.expectedCommit
      }
    }
    func prepared() throws -> WebsiteConfigCommitCoordinator.Prepared {
      guard case .prepared(let ticket) = try coordinator.prepareRestoration() else { throw Failure.expectedPrepared }
      return ticket
    }
  }

  func testRestorationPreservesOriginAndDiskUntilWholePracticeCommits() async throws {
    let f = try Fixture(); defer { f.close() }
    try f.seed()
    let disk = try f.register.read()
    let ticket = try f.prepared()
    guard case .restored(let restored) = ticket.draft.origin else { return XCTFail("Restore became JSON import") }
    guard case .nativeState = restored.origin else { return XCTFail("Wrong restoration format") }
    XCTAssertNil(ticket.draft.prepared)
    XCTAssertEqual(restored.loaded, ticket.draft.projection.runtime)
    XCTAssertEqual(try f.register.read().revision, disk.revision)
    XCTAssertNil(f.coordinator.publication(for: f.page.owner))
    let resources = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    let quote = OfflineQuote(id: "owned-restore", title: "Owned", text: "ab cd", language: .english, length: .short)
    let practice = try await f.coordinator.preparePractice(for: resources, scope: .init(), loadQuotes: { _ in [quote] })
    guard case .committed(let publication) = try f.coordinator.commit(practice, to: f.page, systemIsDark: true) else {
      return XCTFail("Restore did not reach real page")
    }
    XCTAssertEqual(f.page.state.session.prompt, "ab cd")
    XCTAssertEqual(f.page.state.practice?.session.automaticInputAttemptID, publication.session?.automaticInputAttemptID)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
    XCTAssertNotEqual(try f.register.read().revision, disk.revision)
    XCTAssertEqual(try f.register.read().state, .available(publication.draft.projection.runtime))
    guard case .stale = try f.coordinator.commit(practice, to: f.page, systemIsDark: true) else {
      return XCTFail("Restore committed twice")
    }
  }

  func testMissingDoesNotCreateDefaultsAndRetiresOlderIntent() throws {
    let f = try Fixture(); defer { f.close() }
    let old = try f.coordinator.prepare("{}")
    guard case .missing = try f.coordinator.prepareRestoration() else { return XCTFail("Missing record was synthesized") }
    guard case .stale = try f.coordinator.commit(old) else { return XCTFail("Old import survived newer restore") }
    XCTAssertEqual(try f.register.read().state, .missing)
    XCTAssertNil(f.coordinator.publication(for: f.page.owner))
  }

  func testUnavailableRecordIsNotRepairedOrOverwritten() throws {
    let f = try Fixture(); defer { f.close() }
    let old = try f.coordinator.prepare("{}")
    let url = f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
    let opaque = Data("future or corrupt record".utf8)
    try opaque.write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    guard case .unavailable = try f.coordinator.prepareRestoration() else { return XCTFail("Opaque record accepted") }
    guard case .stale = try f.coordinator.commit(old) else { return XCTFail("Old request survived") }
    XCTAssertEqual(try Data(contentsOf: url), opaque)
    XCTAssertNil(f.coordinator.publication(for: f.page.owner))
  }

  func testConcurrentWriterPreventsRestorationCommit() throws {
    let f = try Fixture(); defer { f.close() }
    try f.seed()
    let ticket = try f.prepared()
    try f.seed() // Same values, different durable generation.
    let current = try f.register.read().revision
    guard case .conflict = try f.coordinator.commit(ticket) else { return XCTFail("Restore overwrote newer generation") }
    XCTAssertEqual(try f.register.read().revision, current)
    XCTAssertNil(f.coordinator.publication(for: f.page.owner))
  }

  func testEnvironmentOwnershipAndCancellationRetireRestoration() throws {
    let f = try Fixture(); defer { f.close() }
    try f.seed()
    let disk = try f.register.read().revision
    let environmentTicket = try f.prepared()
    f.epoch = UUID()
    guard case .stale = try f.coordinator.commit(environmentTicket) else { return XCTFail("Old environment accepted") }
    let ownerTicket = try f.prepared()
    let other = UUID()
    f.router.register(owner: other, save: {})
    f.router.activate(owner: other); f.router.activate(owner: f.page.owner)
    guard case .stale = try f.coordinator.commit(ownerTicket) else { return XCTFail("Owner ABA accepted") }
    let cancelled = try f.prepared()
    XCTAssertTrue(f.coordinator.cancel(cancelled))
    guard case .stale = try f.coordinator.commit(cancelled) else { return XCTFail("Cancelled restore accepted") }
    XCTAssertEqual(try f.register.read().revision, disk)
  }

  func testEnvironmentCallbackCannotStealRestoreOwnership() throws {
    let f = try Fixture(); defer { f.close() }
    try f.seed()
    let other = UUID()
    f.router.register(owner: other, save: {})
    f.onRead = { f.router.activate(owner: other) }
    XCTAssertThrowsError(try f.coordinator.prepareRestoration()) { error in
      guard case WebsiteConfigCommitCoordinatorError.stale = error else { return XCTFail("Unexpected error: \(error)") }
    }
    XCTAssertNil(f.coordinator.publication(for: f.page.owner))
  }

  func testRestorationReprojectsAccountDependentFieldsBeforeAnyWrite() throws {
    let f = try Fixture(); defer { f.close() }
    let original = try WebsiteConfigNativeProfile.prepareDraft(#"{"paceCaret":"pb","randomTheme":"custom"}"#,
      pointsPerRem: 16, context: .init(authenticated: true, documentComplete: true, customThemeCount: 1))
    guard case .committed = try f.register.commit(original, replacing: XCTUnwrap(f.register.read().revision)) else {
      return XCTFail("Seed failed")
    }
    f.context.documentComplete = true // Current window is signed out.
    let disk = try f.register.read()
    let ticket = try f.prepared()
    guard case .restored(let restored) = ticket.draft.origin else { return XCTFail("Missing restore origin") }
    XCTAssertEqual(restored.loaded["paceCaret"], .string("pb"))
    XCTAssertEqual(restored.loaded["randomTheme"], .string("custom"))
    XCTAssertEqual(Set(restored.projection.rejectedKeys), ["paceCaret", "randomTheme"])
    // The earlier custom-speed setter has already selected custom. Rejection
    // of the later PB setter retains that value, not the initial default off.
    XCTAssertEqual(ticket.draft.behavior.paceGuideMode, .custom)
    XCTAssertEqual(ticket.draft.behavior.paceGuideCustomWpm, 100)
    XCTAssertEqual(restored.projection.runtime["randomTheme"], .string("off"))
    XCTAssertEqual(try f.register.read().revision, disk.revision)
    guard case .committed(let publication) = try f.coordinator.commit(ticket) else { return XCTFail("Correction not committed") }
    XCTAssertEqual(try f.register.read().state, .available(publication.draft.projection.runtime))
  }

  func testFailedPracticePreparationLeavesPersistedRecordAndPageUntouched() async throws {
    let f = try Fixture(); defer { f.close() }
    try f.seed()
    let disk = try f.register.read().revision
    let attempt = f.page.state.session.automaticInputAttemptID
    let ticket = try f.prepared()
    let resources = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    do {
      _ = try await f.coordinator.preparePractice(for: resources, scope: .init(), loadQuotes: { _ in throw Failure.expectedPrepared })
      XCTFail("Failed loader accepted")
    } catch Failure.expectedPrepared {}
    XCTAssertTrue(f.coordinator.cancel(resources))
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertNil(f.page.state.presentation)
  }

  func testNoQuitPageRejectsRestorationBeforeDurableCommit() async throws {
    let f = try Fixture(); defer { f.close() }
    try f.seed()
    var state = f.page.state
    state.session = TypingSession(configuration: .words(2).with(modifiers: [.noQuit]), prompt: "ab cd")
    state.session.insertBatch("a")
    f.page.replace(state)
    let disk = try f.register.read().revision
    let resources = try f.coordinator.prepareResources(for: f.prepared(), localFont: .absent, localBackground: .absent)
    let quote = OfflineQuote(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)
    let ready = try await f.coordinator.preparePractice(for: resources, scope: .init(), loadQuotes: { _ in [quote] })
    XCTAssertThrowsError(try f.coordinator.commit(ready, to: f.page, systemIsDark: false)) { error in
      guard case PracticePageSessionStateError.locked = error else { return XCTFail("Unexpected error: \(error)") }
    }
    XCTAssertEqual(f.page.state.session.typed, "a")
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, state.session.automaticInputAttemptID)
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertNil(f.coordinator.publication(for: f.page.owner))
  }
}
