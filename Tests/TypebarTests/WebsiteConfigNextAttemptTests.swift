import Darwin
import TypebarSystem
import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigNextAttemptTests: XCTestCase {
  private enum Failure: Error { case notCommitted }
  @MainActor private final class Fixture {
    let page = PracticePageSessionStore(), router = PreferenceConfigurationSaveRouter()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-next-attempt-\(UUID())")
    let register: WebsiteConfigFileRegister
    var epoch = UUID()
    var environmentAction: (() -> Void)?
    lazy var coordinator = WebsiteConfigCommitCoordinator(router: router, register: register,
      environment: { [unowned self] in
        environmentAction?()
        return .init(revision: epoch, context: .init(), pointsPerRem: 16)
      })
    var quotes: [OfflineQuote] {
      [("101", QuoteLength.short), ("102", .short), ("103", .medium)].map {
        .init(id: $0.0, title: "Owned continuation sample", text: "ab", language: .english, length: $0.1)
      }
    }
    init() throws {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory)
      router.register(owner: page.owner, save: { XCTFail("No legacy settings write") })
      page.attach(to: router)
    }
    func close() { page.detach(); try? FileManager.default.removeItem(at: directory) }
    func publish(_ json: String = #"{"mode":"quote","quoteLength":[0,0,1]}"#) async throws {
      let resources = try coordinator.prepareResources(for: coordinator.prepare(json), localFont: .absent, localBackground: .absent)
      let ready = try await coordinator.preparePractice(for: resources, scope: .init(customText: "ab cd"),
        loadQuotes: { _ in self.quotes }, random: .init(quoteIndex: { _ in 0 }))
      guard case .committed = try coordinator.commit(ready, to: page, systemIsDark: true) else { throw Failure.notCommitted }
    }
    func input(_ text: String) {
      var value = page.state
      value.session.insertBatch(text)
      page.replace(value)
    }
  }

  func testNextInstallsOnceWithoutWritingConfigOrReplayingQuoteLength() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let presentation = try XCTUnwrap(f.page.state.presentation)
    let disk = try f.register.read().revision
    let bytes = try Data(contentsOf: f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename))
    let oldID = f.page.state.session.automaticInputAttemptID
    var budget: Int?
    let next = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes },
      random: .init(quoteIndex: { budget = $0; return 0 }))
    XCTAssertEqual(budget, 4, "Ordinary next must advance, not reset the five-slot weighted queue")
    guard case .advanced(let old) = try f.coordinator.advance(next, to: f.page) else { return XCTFail("Next was not installed") }
    XCTAssertEqual(old.session.automaticInputAttemptID, oldID)
    XCTAssertNil(old.incomplete)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, oldID)
    XCTAssertFalse(f.page.state.session.hasStarted)
    XCTAssertTrue(f.page.state.presentation === presentation)
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(try Data(contentsOf: f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)), bytes)
    guard case .stale = try f.coordinator.advance(next, to: f.page) else { return XCTFail("Next was installed twice") }
    var secondBudget: Int?
    _ = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes },
      random: .init(quoteIndex: { secondBudget = $0; return 0 }))
    XCTAssertEqual(secondBudget, 3)
  }

  func testInputDuringPreparationRetiresCandidateAndDoesNotConsumeQueue() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    do {
      _ = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.input("a"); return f.quotes })
      XCTFail("A late candidate replaced new input")
    } catch WebsiteConfigCommitCoordinatorError.stale {}
    XCTAssertEqual(f.page.state.session.typed, "a")
    var budget: Int?
    _ = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes },
      random: .init(quoteIndex: { budget = $0; return 0 }))
    XCTAssertEqual(budget, 4)
  }

  func testNoQuitAndNewEnvironmentRejectBeforeGeneration() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"funbox":["no_quit"]}"#)
    f.input("a")
    do {
      _ = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in XCTFail("No Quit reached generation"); return f.quotes })
      XCTFail("Active No Quit restarted")
    } catch PracticePageSessionStateError.locked {}
    f.epoch = UUID()
    do {
      _ = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in XCTFail("Stale environment reached generation"); return f.quotes })
      XCTFail("Old resources crossed environments")
    } catch WebsiteConfigCommitCoordinatorError.stale {}
  }

  func testPriorActiveAttemptIsReturnedOnlyAfterSuccessfulReplacement() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"custom"}"#)
    f.input("a")
    let next = try await f.coordinator.prepareNext(for: f.page)
    guard case .advanced(let old) = try f.coordinator.advance(next, to: f.page) else { return XCTFail("Next failed") }
    XCTAssertEqual(old.session.typed, "a")
    XCTAssertTrue(old.session.hasStarted)
    XCTAssertFalse(old.session.isFinished)
    XCTAssertEqual(old.incomplete?.accuracy, 100)
    XCTAssertGreaterThanOrEqual(try XCTUnwrap(old.incomplete?.engagedDuration), 0)
    XCTAssertEqual(f.page.state.session.typed, "")
    XCTAssertFalse(f.page.acceptsInput(for: old.session.automaticInputAttemptID))
  }

  func testDiskConflictAndForeignPageKeepTheOldAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let oldID = f.page.state.session.automaticInputAttemptID
    let next = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes })
    let foreign = PracticePageSessionStore(); foreign.attach(to: f.router)
    XCTAssertThrowsError(try f.coordinator.advance(next, to: foreign))
    let disk = try XCTUnwrap(f.register.read().revision)
    let external = try WebsiteConfigNativeProfile.prepareDraft(#"{"words":17}"#, pointsPerRem: 16, context: .init())
    guard case .committed = try f.register.commit(external, replacing: disk) else { return XCTFail("Fixture write failed") }
    guard case .conflict = try f.coordinator.advance(next, to: f.page) else { return XCTFail("External settings were ignored") }
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, oldID)
  }

  func testAttachmentABAAndCancellationDoNotReplaceTheAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let oldID = f.page.state.session.automaticInputAttemptID
    let next = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes })
    f.page.detach(); f.page.attach(to: f.router)
    guard case .stale = try f.coordinator.advance(next, to: f.page) else { return XCTFail("Attachment ABA revived a candidate") }
    let cancelled = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes })
    XCTAssertTrue(f.coordinator.cancel(cancelled))
    XCTAssertFalse(f.coordinator.cancel(cancelled))
    guard case .stale = try f.coordinator.advance(cancelled, to: f.page) else { return XCTFail("Cancelled attempt was installed") }
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, oldID)
  }

  func testFailedNewGenerationRetiresOlderReadyCandidateWithoutConsumingQueue() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let first = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes })
    do {
      _ = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in throw Failure.notCommitted })
      XCTFail("Failed source was admitted")
    } catch Failure.notCommitted {}
    guard case .stale = try f.coordinator.advance(first, to: f.page) else { return XCTFail("An older seed survived a newer request") }
    var budget: Int?
    _ = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes },
      random: .init(quoteIndex: { budget = $0; return 0 }))
    XCTAssertEqual(budget, 4)
  }

  func testBusyReadReleasesPageReservationAndAllowsExactCandidateRetry() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let oldID = f.page.state.session.automaticInputAttemptID
    let next = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes })
    let descriptor = Darwin.open(f.directory.appendingPathComponent(WebsiteConfigFileRegister.lockFilename).path,
      O_RDWR | O_CLOEXEC | O_NOFOLLOW)
    XCTAssertGreaterThanOrEqual(descriptor, 0); defer { Darwin.close(descriptor) }
    XCTAssertEqual(typebar_file_lock(descriptor, LOCK_EX | LOCK_NB), 0)
    defer { _ = typebar_file_lock(descriptor, LOCK_UN) }
    guard case .busy = try f.coordinator.advance(next, to: f.page) else { return XCTFail("Expected bounded busy result") }
    XCTAssertTrue(f.page.acceptsInput(for: oldID), "Busy must release the page reservation")
    XCTAssertEqual(typebar_file_lock(descriptor, LOCK_UN), 0)
    guard case .advanced = try f.coordinator.advance(next, to: f.page) else { return XCTFail("Exact candidate retry failed") }
  }

  func testInjectedOldClockCannotChangeDiskAfterTheFinalRead() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"custom"}"#)
    let seed = try XCTUnwrap(f.page.state.practice?.session)
    let disk = try XCTUnwrap(f.register.read().revision)
    let external = try WebsiteConfigNativeProfile.prepareDraft(#"{"words":17}"#, pointsPerRem: 16, context: .init())
    var armed = false
    var clockTime: TimeInterval = 0
    var state = f.page.state
    state.session = seed.withElapsedClock(.init {
      if armed {
        armed = false
        do {
          guard case .committed = try f.register.commit(external, replacing: disk) else { XCTFail("Fixture clock write failed"); return clockTime }
        } catch { XCTFail("Fixture clock error: \(error)") }
      }
      return clockTime
    })
    f.page.replace(state)
    f.input("a")
    clockTime = 1
    let oldID = f.page.state.session.automaticInputAttemptID
    let next = try await f.coordinator.prepareNext(for: f.page)
    armed = true
    guard case .conflict = try f.coordinator.advance(next, to: f.page) else {
      return XCTFail("Clock callback changed the record after validation, but the attempt was replaced")
    }
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, oldID)
    XCTAssertEqual(f.page.state.session.typed, "a")
  }

  func testCancellationFromEnvironmentCallbackStopsBeforeInstallation() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let oldID = f.page.state.session.automaticInputAttemptID
    let disk = try f.register.read().revision
    let next = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes })
    var work: Task<Void, Error>?
    f.environmentAction = { work?.cancel() }
    defer { f.environmentAction = nil }
    work = Task { @MainActor in _ = try f.coordinator.advance(next, to: f.page) }
    do {
      try await XCTUnwrap(work).value
      XCTFail("Cancellation from a checked callback was ignored")
    } catch is CancellationError {}
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, oldID)
    XCTAssertEqual(try f.register.read().revision, disk)
  }
}
