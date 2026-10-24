import Darwin
import TypebarSystem
import XCTest
import Observation
@testable import Typebar

@MainActor final class WebsitePracticeRestartControllerTests: XCTestCase {
  private enum Failure: Error { case generation, publication }
  @MainActor private final class Fixture {
    let page = PracticePageSessionStore(), router = PreferenceConfigurationSaveRouter()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-restart-controller-\(UUID())")
    let register: WebsiteConfigFileRegister
    lazy var coordinator: WebsiteConfigCommitCoordinator = {
      let epoch = UUID()
      return .init(router: router, register: register,
        environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    }()
    var quotes: [OfflineQuote] { [.init(id: "owned", title: "Owned departure sample", text: "ab cd", language: .english, length: .short)] }
    init() throws {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory)
      router.register(owner: page.owner, save: { XCTFail("No legacy configuration write") })
      page.attach(to: router)
    }
    func close() { page.detach(); try? FileManager.default.removeItem(at: directory) }
    func publish(_ json: String = #"{"mode":"custom"}"#) async throws {
      let resources = try coordinator.prepareResources(for: coordinator.prepare(json), localFont: .absent, localBackground: .absent)
      let ready = try await coordinator.preparePractice(for: resources, scope: .init(customText: "ab cd"), loadQuotes: { _ in self.quotes })
      guard case .committed = try coordinator.commit(ready, to: page, systemIsDark: true) else { throw Failure.publication }
    }
    func input(_ text: String) { var state = page.state; state.session.insert(text); page.replace(state) }
    func bind(loadQuotes: (@MainActor (TypingLanguage) async throws -> [OfflineQuote])? = nil) throws -> WebsitePracticeRestartController {
      try page.bindRestartController(using: coordinator, loadQuotes: loadQuotes ?? { _ in self.quotes })
    }
  }
  private func wait(_ ready: () -> Bool) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !ready() && ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertTrue(ready(), "Restart operation did not settle")
  }

  func testProductionCandidateRepeatKeepsConfigurationResourcesAndSourceExhaustionPolicy() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"words","words":0,"repeatedPace":true}"#)
    let old = f.page.state, presentation = try XCTUnwrap(old.presentation)
    let disk = try f.register.read().revision
    let controller = try f.bind()
    let advanced = try await controller.requestAndWait(requestID: UUID(), repeatingRequested: true)
    XCTAssertTrue(advanced)
    XCTAssertTrue(f.page.state.presentation === presentation)
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(f.page.state.session.prompt, old.session.prompt)
    XCTAssertEqual(f.page.state.practice?.repetition, .sameWordset(repeatedPace: true))
    var session = f.page.state.session
    session.insertBatch(session.prompt)
    XCTAssertEqual(session.outcome, .failed)
    XCTAssertEqual(session.failureReason, .wordGeneration)
    var failed = f.page.state; failed.session = session; f.page.replace(failed)
    let recovered = try await controller.requestAndWait(requestID: UUID())
    XCTAssertTrue(recovered, "Ordinary restart after the failure must allow fresh generation")
    XCTAssertEqual(f.page.state.session.outcome, .active)
    XCTAssertFalse(f.page.state.session.hasStarted)
    XCTAssertEqual(f.page.state.practice?.repetition, WebsitePracticeRepetition.none)
    XCTAssertTrue(f.page.state.presentation === presentation)
    XCTAssertEqual(try f.register.read().revision, disk)
  }

  func testProductionRepeatKeepsPrefetchedCandidateFutureThenFailsInsteadOfDrawingPastIt() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"words","words":0}"#)
    var state = f.page.state
    let openingCount = try XCTUnwrap(state.session.generatedWordReplayHistory?.count)
    let first = try XCTUnwrap(state.session.prompt.components(separatedBy: " ").first)
    state.session.insertBatch(first + " ")
    f.page.replace(state)
    let captured = f.page.state.session
    XCTAssertGreaterThan(try XCTUnwrap(captured.generatedWordReplayHistory?.count), openingCount)
    let disk = try f.register.read().revision
    let controller = try f.bind()
    let advanced = try await controller.requestAndWait(requestID: UUID(), repeatingRequested: true)
    XCTAssertTrue(advanced)
    var repeated = f.page.state.session
    repeated.insertBatch(repeated.prompt)
    XCTAssertEqual(repeated.outcome, .failed)
    XCTAssertEqual(repeated.failureReason, .wordGeneration)
    XCTAssertEqual(repeated.prompt, captured.prompt)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(try f.register.read().revision, disk)
  }

  func testCandidateRepeatCancellationAfterDepartureCanRetryWithoutDuplicateAccounting() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"words","words":4}"#); f.input("a")
    let old = f.page.state.session, disk = try f.register.read().revision
    let controller = try f.bind()
    await Task { @MainActor in
      withObservationTracking { _ = f.page.state } onChange: { withUnsafeCurrentTask { $0?.cancel() } }
      do {
        _ = try await controller.requestAndWait(requestID: UUID(), repeatingRequested: true)
        XCTFail("Cancelled repeat installed")
      } catch is CancellationError {} catch { XCTFail("Unexpected: \(error)") }
    }.value
    XCTAssertFalse(controller.isPreparing)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, old.automaticInputAttemptID)
    XCTAssertEqual(f.page.state.session.outcome, .abandoned)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertFalse(f.page.acceptsInput(for: old.automaticInputAttemptID))
    let retried = try await controller.requestAndWait(requestID: UUID(), repeatingRequested: true)
    XCTAssertTrue(retried)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, old.automaticInputAttemptID)
    XCTAssertEqual(f.page.state.session.prompt, old.prompt)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertNil(f.page.state.restartDepartureAttemptID)
    XCTAssertEqual(try f.register.read().revision, disk)
  }

  func testAwaitedRequestSharesBusyStateAndOldCancellationCannotCancelTheNextRequest() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off"}"#)
    var reply: CheckedContinuation<[OfflineQuote], Never>?
    defer { reply?.resume(returning: f.quotes) }
    let controller = try f.bind(loadQuotes: { _ in await withCheckedContinuation { reply = $0 } })
    let old = UUID(), next = UUID()
    let first = Task { try await controller.requestAndWait(requestID: old) }
    await wait { reply != nil }
    XCTAssertFalse(controller.request())
    controller.cancel(requestID: old)
    try XCTUnwrap(reply).resume(returning: f.quotes); reply = nil
    let firstAdvanced = try await first.value; XCTAssertFalse(firstAdvanced)
    let second = Task { try await controller.requestAndWait(requestID: next) }
    await wait { reply != nil }
    controller.cancel(requestID: old)
    XCTAssertTrue(controller.isPreparing); XCTAssertFalse(controller.request())
    try XCTUnwrap(reply).resume(returning: f.quotes); reply = nil
    let secondAdvanced = try await second.value; XCTAssertTrue(secondAdvanced)
    XCTAssertFalse(controller.isPreparing); XCTAssertNil(controller.message)
    XCTAssertNil(f.page.state.restartDepartureAttemptID)
  }

  func testDepartureIsRecordedBeforeGenerationAndFailedGenerationDoesNotEraseIt() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
    f.input("a")
    let oldID = f.page.state.session.automaticInputAttemptID, disk = try f.register.read().revision
    var reply: CheckedContinuation<[OfflineQuote], Error>?
    let controller = try f.bind(loadQuotes: { _ in
      XCTAssertEqual(f.page.state.session.outcome, .abandoned)
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
      return try await withCheckedThrowingContinuation { reply = $0 }
    })
    XCTAssertTrue(controller.request())
    XCTAssertFalse(controller.request(), "A duplicate request must not close/count twice")
    await wait { reply != nil }
    XCTAssertFalse(f.page.acceptsInput(for: oldID))
    reply?.resume(throwing: Failure.generation); reply = nil
    await wait { !controller.isPreparing }
    XCTAssertNotNil(controller.message)
    XCTAssertEqual(f.page.state.session.typed, "a")
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(f.page.state.restartDepartureAttemptID, oldID)
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertTrue(controller.request())
    await wait { reply != nil }
    reply?.resume(returning: f.quotes); reply = nil
    await wait { !controller.isPreparing }
    XCTAssertNil(controller.message)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, oldID)
    XCTAssertNil(f.page.state.restartDepartureAttemptID)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
  }

  func testSavingPolicyComesFromThePublishedDraftAndPriorLedgerSurvivesTransition() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"custom","resultSaving":false}"#)
    var state = f.page.state
    state.priorAttemptLedger.recordRestart(engagedDuration: 2, accuracy: 90, savingEnabled: true)
    f.page.replace(state); f.input("a")
    let controller = try f.bind()
    XCTAssertTrue(controller.request())
    await wait { !controller.isPreparing }
    XCTAssertNil(controller.message)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(f.page.state.priorAttemptLedger.priorAttemptEngagedDuration, 2)
    XCTAssertEqual(f.page.state.priorAttemptLedger.incompletePractice?.attempts.first?.accuracy, 90)
  }

  func testNoQuitRejectsBeforeClosingOrRecording() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"custom","funbox":["no_quit"]}"#)
    f.input("a")
    let controller = try f.bind(), id = f.page.state.session.automaticInputAttemptID
    XCTAssertFalse(controller.request(repeatingRequested: true))
    await wait { !controller.isPreparing }
    XCTAssertNotNil(controller.message)
    XCTAssertFalse(f.page.state.session.isFinished)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    XCTAssertNil(f.page.state.restartDepartureAttemptID)
    XCTAssertTrue(f.page.acceptsInput(for: id))
  }

  func testDepartureUsesOneClockSampleAndCarriesItsFrozenMetrics() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let seed = try XCTUnwrap(f.page.state.practice?.session)
    var time: TimeInterval = 0, samples = 0
    var state = f.page.state
    state.session = seed.withElapsedClock(.init { samples += 1; return time })
    f.page.replace(state); f.input("a")
    time = 2; samples = 0
    let controller = try f.bind()
    XCTAssertTrue(controller.request(repeatingRequested: true))
    await wait { !controller.isPreparing }
    XCTAssertNil(controller.message)
    XCTAssertEqual(samples, 1)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(f.page.state.priorAttemptLedger.priorAttemptEngagedDuration, 1, accuracy: 0.0001,
      "Two wall-clock intervals contain one empty interval; preserve AFK subtraction")
    XCTAssertEqual(f.page.state.priorAttemptLedger.incompletePractice?.attempts.first?.accuracy, 100)
    XCTAssertEqual(f.page.state.practice?.repetition.repeatsWordset, true)
  }

  func testCancellationKeepsAcceptedDepartureAndLateGenerationCannotInstall() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off"}"#)
    f.input("a")
    let id = f.page.state.session.automaticInputAttemptID
    var reply: CheckedContinuation<[OfflineQuote], Error>?
    var returned = false
    let controller = try f.bind(loadQuotes: { _ in
      let value: [OfflineQuote] = try await withCheckedThrowingContinuation { reply = $0 }
      returned = true; return value
    })
    XCTAssertTrue(controller.request())
    await wait { reply != nil }
    controller.cancel()
    XCTAssertFalse(controller.isPreparing)
    XCTAssertEqual(f.page.state.session.outcome, .abandoned)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertFalse(f.page.acceptsInput(for: id))
    XCTAssertTrue(f.page.acceptsAttemptCallback(for: id), "Retry commands remain possible")
    reply?.resume(returning: f.quotes); reply = nil
    await wait { returned }
    for _ in 0..<10 { await Task.yield() }
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, id)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertNotNil(controller.message)
    f.page.detach()
    XCTAssertNil(f.page.restartController)
    XCTAssertFalse(controller.request())
  }

  func testAcceptedDepartureConsumesOldFailureMarkerBeforeRetry() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"difficulty":"master","repeatQuotes":"typing"}"#)
    f.input("x")
    XCTAssertEqual(f.page.state.session.outcome, .failed)
    let accepted = try f.coordinator.beginRestart(for: f.page)
    XCTAssertTrue(f.coordinator.cancel(accepted))
    var drew = false
    let retry = try await f.coordinator.prepareRestart(for: f.page, loadQuotes: { _ in drew = true; return f.quotes })
    XCTAssertTrue(drew, "Source restart clears failReason before init; a cancelled init must not replay the old failure again")
    guard case .advanced = try f.coordinator.advance(retry, to: f.page) else { throw Failure.publication }
    XCTAssertEqual(f.page.state.practice?.repetition, WebsitePracticeRepetition.none)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
  }

  func testNewConfigurationPreservesLedgerAndClearsDepartureOnBothInstallationPaths() async throws {
    for direct in [false, true] {
      let f = try Fixture(); defer { f.close() }
      try await f.publish(); f.input("a")
      let controller = try f.bind()
      let accepted = try f.coordinator.beginRestart(for: f.page)
      XCTAssertTrue(f.coordinator.cancel(accepted))
      let resources = try f.coordinator.prepareResources(for: f.coordinator.prepare(#"{"mode":"custom"}"#),
        localFont: .absent, localBackground: .absent)
      let ready = try await f.coordinator.preparePractice(for: resources, scope: .init(customText: "new"))
      if direct {
        guard case .committed = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else { throw Failure.publication }
      } else {
        guard case .committed(let publication) = try f.coordinator.commit(ready) else { throw Failure.publication }
        let display = try WebsiteConfigPublishedPresentation(publication: publication, owner: f.page.owner, systemIsDark: false)
        f.page.replace(try f.page.state.applying(display, owner: f.page.owner, router: f.router))
      }
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
      XCTAssertNil(f.page.state.restartDepartureAttemptID)
      XCTAssertNil(f.page.restartController)
      XCTAssertFalse(controller.request())
      XCTAssertEqual(f.page.state.session.prompt, "new")
    }
  }

  func testInvalidationDuringDepartureClockRejectsWithoutClosingOrRecording() async throws {
    for changesFile in [false, true] {
      let f = try Fixture(); defer { f.close() }
      try await f.publish()
      let seed = try XCTUnwrap(f.page.state.practice?.session)
      let disk = try XCTUnwrap(f.register.read().revision)
      let external = try WebsiteConfigNativeProfile.prepareDraft(#"{"words":17}"#, pointsPerRem: 16, context: .init())
      var armed = false
      var state = f.page.state
      state.session = seed.withElapsedClock(.init {
        if armed {
          armed = false
          if changesFile {
            do {
              guard case .committed = try f.register.commit(external, replacing: disk) else { XCTFail("Fixture update failed"); return 1 }
            } catch { XCTFail("Fixture update error: \(error)") }
          } else { f.input("b") }
        }
        return 1
      })
      f.page.replace(state); f.input("a")
      let controller = try f.bind()
      armed = true
      XCTAssertFalse(controller.request())
      XCTAssertNotNil(controller.message)
      XCTAssertFalse(f.page.state.session.isFinished)
      XCTAssertNil(f.page.state.restartDepartureAttemptID)
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
      XCTAssertEqual(f.page.state.session.typed, changesFile ? "a" : "ab")
    }
  }

  func testBusyAdmissionDoesNotCloseAttemptAndRetryCountsOnce() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(); f.input("a")
    let controller = try f.bind()
    let descriptor = Darwin.open(f.directory.appendingPathComponent(WebsiteConfigFileRegister.lockFilename).path,
      O_RDWR | O_CLOEXEC | O_NOFOLLOW)
    XCTAssertGreaterThanOrEqual(descriptor, 0); defer { Darwin.close(descriptor) }
    XCTAssertEqual(typebar_file_lock(descriptor, LOCK_EX | LOCK_NB), 0)
    defer { _ = typebar_file_lock(descriptor, LOCK_UN) }
    XCTAssertFalse(controller.request())
    XCTAssertFalse(f.page.state.session.isFinished)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    XCTAssertEqual(typebar_file_lock(descriptor, LOCK_UN), 0)
    XCTAssertTrue(controller.request())
    await wait { !controller.isPreparing }
    XCTAssertNil(controller.message)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
  }

  func testDetachDuringGenerationRetiresControllerAndLateReply() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off"}"#)
    f.input("a")
    let id = f.page.state.session.automaticInputAttemptID
    var reply: CheckedContinuation<[OfflineQuote], Error>?
    var returned = false
    let controller = try f.bind(loadQuotes: { _ in
      let value: [OfflineQuote] = try await withCheckedThrowingContinuation { reply = $0 }
      returned = true; return value
    })
    XCTAssertTrue(controller.request())
    await wait { reply != nil }
    f.page.detach()
    XCTAssertNil(f.page.restartController)
    XCTAssertFalse(controller.isPreparing)
    XCTAssertFalse(controller.request())
    reply?.resume(returning: f.quotes); reply = nil
    await wait { returned }
    for _ in 0..<10 { await Task.yield() }
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, id)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
  }
}
