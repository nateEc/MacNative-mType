import Darwin
import TypebarSystem
import XCTest
import Observation
@testable import Typebar

@MainActor final class WebsitePracticeRestartControllerTests: XCTestCase {
  func testFreshCustomRepeatUsesItsGeneratedRecordsAndSourceSectionQuota() async throws {
    let f = try Fixture(); defer { f.close() }
    let resources = try f.coordinator.prepareResources(for: f.coordinator.prepare(#"{"mode":"custom","repeatedPace":false}"#),
      localFont: .absent, localBackground: .absent)
    let custom = try WebsiteCustomTextSettings(value: .object([
      "text": .array([.string("Aa Bb"), .string("I")]), "mode": .string("repeat"),
      "limit": .object(["mode": .string("word"), "value": .number(2)]), "pipeDelimiter": .bool(true)]))
    let ready = try await f.coordinator.preparePractice(for: resources, scope: .init(websiteCustomText: custom))
    guard case .committed = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else {
      return XCTFail("Fresh custom publication failed")
    }
    XCTAssertEqual(f.page.state.session.prompt, "Aa Bb I")
    let disk = try f.register.read().revision
    f.input("A")
    let old = f.page.state.session.automaticInputAttemptID
    let controller = try f.bind()
    let repeated = try await controller.requestAndWait(requestID: UUID(), repeatingRequested: true)
    XCTAssertTrue(repeated)
    XCTAssertEqual(f.page.state.practice?.repetition, .sameWordset(repeatedPace: false))
    XCTAssertEqual(f.page.state.session.prompt, "Aa Bb")
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, old)
    XCTAssertEqual(f.page.state.session.typed, "")
    XCTAssertEqual(f.page.state.session.generatedWordReplayHistory?.count, 3)
    XCTAssertEqual(try f.register.read().revision, disk)
  }

  private enum Failure: Error { case generation, publication }

  func testThreeGenerationFailuresShowLastHumanReasonWithoutLosingDeparture() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
    f.input("a")
    let disk = try f.register.read().revision
    var reads = 0
    let controller = try f.bind(loadQuotes: { _ in
      reads += 1
      throw NSError(domain: "OwnedGeneration", code: reads,
        userInfo: [NSLocalizedDescriptionKey: "自有目录读取失败 \(reads)"])
    })
    let advanced = try await controller.requestAndWait(requestID: UUID())
    XCTAssertFalse(advanced)
    XCTAssertEqual(reads, 3)
    XCTAssertTrue(controller.message?.contains("三次") == true)
    XCTAssertTrue(controller.message?.contains("自有目录读取失败 3") == true)
    XCTAssertFalse(controller.message?.contains("自有目录读取失败 1") == true)
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
  }
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
    func publish(_ json: String = #"{"mode":"custom"}"#, random: WebsiteConfigSessionBuilder.Random = .init()) async throws {
      let resources = try coordinator.prepareResources(for: coordinator.prepare(json), localFont: .absent, localBackground: .absent)
      let ready = try await coordinator.preparePractice(for: resources, scope: .init(customText: "ab cd"), loadQuotes: { _ in self.quotes }, random: random)
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

  func testFailedQuoteDrawKeepsControllerAndCanRecoverAfterCatalogChanges() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
    f.input("a")
    let disk = try f.register.read().revision
    var empty = true, reads = 0
    let controller = try f.bind(loadQuotes: { _ in
      reads += 1
      return [.init(id: "owned", title: "Owned changing sample", text: empty ? "" : "ef gh", language: .english, length: .short)]
    })
    let failed = try await controller.requestAndWait(requestID: UUID())
    XCTAssertFalse(failed)
    XCTAssertEqual(reads, 3)
    XCTAssertTrue(f.page.restartController === controller)
    XCTAssertNotNil(f.page.state.quoteInitialization)
    XCTAssertEqual(f.page.state.currentQuoteInitialization?.quote?.text, "")
    XCTAssertEqual(try f.register.read().revision, disk)
    empty = false
    let recovered = try await controller.requestAndWait(requestID: UUID())
    XCTAssertTrue(recovered)
    XCTAssertEqual(reads, 4)
    XCTAssertEqual(f.page.state.session.prompt, "ef gh")
    XCTAssertNil(f.page.state.quoteInitialization)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(try f.register.read().revision, disk)
  }

  func testRepeatAfterFailedCatalogReadDoesNotReviveTheOldVisibleQuote() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
    f.input("a")
    let oldID = f.page.state.session.automaticInputAttemptID, disk = try f.register.read().revision
    var reads = 0
    let controller = try f.bind(loadQuotes: { _ in reads += 1; throw Failure.generation })
    let failed = try await controller.requestAndWait(requestID: UUID())
    XCTAssertFalse(failed)
    XCTAssertNotNil(f.page.state.quoteInitialization)
    XCTAssertNil(f.page.state.currentQuoteInitialization?.quote)
    XCTAssertEqual(reads, 3)
    let repeated = try await controller.requestAndWait(requestID: UUID(), repeatingRequested: true)
    XCTAssertFalse(repeated)
    XCTAssertEqual(reads, 3, "Failed repeat must not fetch a replacement quote")
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, oldID)
    XCTAssertEqual(f.page.state.session.outcome, .abandoned)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(try f.register.read().revision, disk)
  }

  func testOrdinaryGenerationErrorsCanRecoverOnThirdRestartAttemptWithoutSavingAgain() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
    f.input("a")
    let presentation = f.page.state.presentation, disk = try f.register.read().revision
    var reads = 0
    let controller = try f.bind(loadQuotes: { _ in
      reads += 1
      if reads < 3 { throw Failure.generation }
      return f.quotes
    })
    let advanced = try await controller.requestAndWait(requestID: UUID())
    XCTAssertTrue(advanced)
    XCTAssertEqual(reads, 3)
    XCTAssertNil(controller.message)
    XCTAssertTrue(f.page.state.presentation === presentation)
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertNil(f.page.state.restartDepartureAttemptID)
    XCTAssertFalse(f.page.state.session.hasStarted)
  }

  func testQuoteCorrectionAndOrdinaryErrorsShareOneInitializationBudget() async throws {
    for succeeds in [false, true] {
      let f = try Fixture(); defer { f.close() }
      try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
      f.input("a")
      let replacement = OfflineQuote(id: "medium", title: "Owned replacement", text: "ef gh", language: .english, length: .medium)
      var reads = 0
      var saved: WebsiteConfigFileRegister.Revision?
      let controller = try f.bind(loadQuotes: { _ in
        reads += 1
        if reads == 1 { return [replacement] }
        if reads == 2 { saved = try f.register.read().revision }
        XCTAssertEqual(try f.register.read().revision, saved)
        if reads == 2 || !succeeds { throw Failure.generation }
        return [replacement]
      })
      let advanced = try await controller.requestAndWait(requestID: UUID())
      XCTAssertEqual(advanced, succeeds)
      XCTAssertEqual(reads, 3, "Correction and generation errors must not get independent retry budgets")
      XCTAssertEqual(try f.register.read().revision, try XCTUnwrap(saved))
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
      XCTAssertTrue(f.page.restartController === controller)
      if succeeds {
        XCTAssertNil(f.page.state.configurationDeparture)
        XCTAssertEqual(f.page.state.presentation?.publication.quoteRecoveries, [.allLengths])
      } else {
        XCTAssertNotNil(f.page.state.configurationDeparture)
        XCTAssertNotNil(controller.message)
      }
    }
  }

  func testGenerationFailureCannotRetryAfterCompetingConfigurationWrite() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
    f.input("a")
    let disk = try XCTUnwrap(f.register.read().revision), presentation = f.page.state.presentation
    let competitor = try WebsiteConfigNativeProfile.prepareDraft(#"{"words":17}"#, pointsPerRem: 16, context: .init())
    var reads = 0, saved: WebsiteConfigFileRegister.Revision?
    let controller = try f.bind(loadQuotes: { _ in
      reads += 1
      guard case .committed(let revision) = try f.register.commit(competitor, replacing: disk) else { throw Failure.publication }
      saved = revision
      throw Failure.generation
    })
    let advanced = try await controller.requestAndWait(requestID: UUID())
    XCTAssertFalse(advanced)
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(try f.register.read().revision, try XCTUnwrap(saved))
    XCTAssertTrue(f.page.state.presentation === presentation)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertNil(f.page.state.configurationDeparture)
  }

  func testDetachedReaderErrorCannotConsumeAnotherGenerationAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
    f.input("a")
    let disk = try f.register.read().revision
    var reads = 0, reply: CheckedContinuation<[OfflineQuote], Error>?
    defer { reply?.resume(throwing: Failure.generation) }
    let controller = try f.bind(loadQuotes: { _ in
      reads += 1
      return try await withCheckedThrowingContinuation { reply = $0 }
    })
    let task = Task { try await controller.requestAndWait(requestID: UUID()) }
    await wait { reply != nil }
    f.page.detach()
    try XCTUnwrap(reply).resume(throwing: Failure.generation); reply = nil
    let advanced = try await task.value
    XCTAssertFalse(advanced)
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertNil(f.page.restartController)
  }

  func testQuoteRestartRecoversUnavailableLengthAndRetainsItsController() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
    f.input("a")
    let old = f.page.state, disk = try f.register.read().revision
    let replacement = OfflineQuote(id: "medium", title: "Owned replacement", text: "ef gh", language: .english, length: .medium)
    var reads = 0
    let controller = try f.bind(loadQuotes: { _ in reads += 1; return [replacement] })
    let advanced = try await controller.requestAndWait(requestID: UUID())
    XCTAssertTrue(advanced)
    XCTAssertEqual(reads, 2)
    XCTAssertTrue(f.page.restartController === controller)
    XCTAssertFalse(controller.isPreparing)
    XCTAssertNil(controller.message)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.session.prompt, replacement.text)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.quoteSelection.groups, [0, 1, 2, 3])
    XCTAssertEqual(f.page.state.presentation?.publication.quoteRecoveries, [.allLengths])
    XCTAssertTrue(f.page.state.presentation?.currentSystemIsDark == true)
    XCTAssertNotEqual(f.page.state.presentation?.publication.applicationID, old.presentation?.publication.applicationID)
    XCTAssertNotEqual(try f.register.read().revision, disk)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    let recoveredDisk = try f.register.read().revision, presentation = f.page.state.presentation
    let again = try await controller.requestAndWait(requestID: UUID())
    XCTAssertTrue(again)
    XCTAssertEqual(reads, 3)
    XCTAssertTrue(f.page.state.presentation === presentation)
    XCTAssertEqual(try f.register.read().revision, recoveredDisk)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
  }

  func testCancelledQuoteCorrectionResumesWithoutAnotherSaveOrDeparture() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
    f.input("a")
    let oldID = f.page.state.session.automaticInputAttemptID
    let replacement = OfflineQuote(id: "medium", title: "Owned replacement", text: "ef gh", language: .english, length: .medium)
    var reads = 0, reply: CheckedContinuation<[OfflineQuote], Never>?
    defer { reply?.resume(returning: [replacement]) }
    let controller = try f.bind(loadQuotes: { _ in
      reads += 1
      if reads == 2 { return await withCheckedContinuation { reply = $0 } }
      return [replacement]
    })
    let operation = UUID()
    let task = Task { try await controller.requestAndWait(requestID: operation) }
    await wait { reads > 0 && (reply != nil || !controller.isPreparing) }
    guard let pendingReply = reply else { _ = try await task.value; return XCTFail("Recovery did not enter second generation") }
    let phase = try XCTUnwrap(f.page.state.configurationDeparture)
    let saved = try f.register.read().revision
    XCTAssertEqual(phase.draft.quoteSelection.groups, [0, 1, 2, 3])
    XCTAssertTrue(f.page.restartController === controller)
    XCTAssertFalse(f.page.acceptsInput(for: oldID))
    controller.cancel(requestID: operation)
    pendingReply.resume(returning: [replacement]); reply = nil
    let cancelled = try await task.value
    XCTAssertFalse(cancelled)
    XCTAssertEqual(f.page.state.configurationDeparture?.id, phase.id)
    let resumed = try await controller.requestAndWait(requestID: UUID())
    XCTAssertTrue(resumed)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.session.prompt, replacement.text)
    XCTAssertEqual(try f.register.read().revision, saved)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(reads, 3)
  }

  func testQuoteRecoveryBudgetStopsAtThreeAndSameControllerCanRetry() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
    f.input("a")
    var invalid = true, reads = 0
    let controller = try f.bind(loadQuotes: { _ in
      reads += 1
      return [.init(id: "owned", title: "Owned budget sample", text: "ef gh", language: .english,
        length: invalid ? .all : .short)]
    })
    let exhausted = try await controller.requestAndWait(requestID: UUID())
    XCTAssertFalse(exhausted)
    XCTAssertEqual(reads, 3)
    XCTAssertTrue(controller.message?.contains("三次") == true)
    XCTAssertTrue(f.page.restartController === controller)
    let phase = try XCTUnwrap(f.page.state.configurationDeparture)
    XCTAssertEqual(phase.draft.quoteSelection.groups, [0, 1, 2, 3])
    let saved = try f.register.read().revision
    invalid = false
    let resumed = try await controller.requestAndWait(requestID: UUID())
    XCTAssertTrue(resumed)
    XCTAssertEqual(reads, 4)
    XCTAssertEqual(f.page.state.presentation?.publication.quoteRecoveries, [.allLengths, .allLengths, .allLengths])
    XCTAssertEqual(try f.register.read().revision, saved)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
  }

  func testEmptyQuoteRestartSavesWordsModeWithoutChangingLanguage() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","words":4,"quoteLength":[0],"repeatQuotes":"off"}"#)
    let disk = try f.register.read().revision
    let controller = try f.bind(loadQuotes: { _ in [] })
    let advanced = try await controller.requestAndWait(requestID: UUID())
    XCTAssertTrue(advanced)
    XCTAssertEqual(f.page.state.session.configuration.mode, .words)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 4)
    XCTAssertEqual(f.page.state.session.configuration.language, .english)
    XCTAssertEqual(f.page.state.presentation?.publication.quoteRecoveries, [.wordsMode])
    XCTAssertNotEqual(try f.register.read().revision, disk)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    let saved = try f.register.read().revision
    let next = try await controller.requestAndWait(requestID: UUID())
    XCTAssertTrue(next)
    XCTAssertEqual(try f.register.read().revision, saved)
  }

  func testQuoteCorrectionCannotOverwriteCompetingRecord() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
    f.input("a")
    let old = f.page.state.presentation, disk = try XCTUnwrap(f.register.read().revision)
    let competitor = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":17}"#,
      pointsPerRem: 16, context: .init())
    var competitorDisk: WebsiteConfigFileRegister.Revision?, reads = 0
    let controller = try f.bind(loadQuotes: { _ in
      reads += 1
      guard case .committed(let revision) = try f.register.commit(competitor, replacing: disk) else {
        throw Failure.publication
      }
      competitorDisk = revision
      return [.init(id: "medium", title: "Owned replacement", text: "ef gh", language: .english, length: .medium)]
    })
    let advanced = try await controller.requestAndWait(requestID: UUID())
    XCTAssertFalse(advanced)
    XCTAssertEqual(reads, 1)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertTrue(f.page.state.presentation === old)
    XCTAssertEqual(try f.register.read().revision, try XCTUnwrap(competitorDisk))
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(f.page.state.session.outcome, .abandoned)
  }

  func testDetachAfterQuoteCorrectionRejectsLateReplyAndKeepsSavedState() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
    f.input("a")
    let old = f.page.state.presentation
    let replacement = OfflineQuote(id: "medium", title: "Owned replacement", text: "ef gh", language: .english, length: .medium)
    var reads = 0, reply: CheckedContinuation<[OfflineQuote], Never>?
    defer { reply?.resume(returning: [replacement]) }
    let controller = try f.bind(loadQuotes: { _ in
      reads += 1
      if reads == 2 { return await withCheckedContinuation { reply = $0 } }
      return [replacement]
    })
    let task = Task { try await controller.requestAndWait(requestID: UUID()) }
    await wait { reads > 0 && (reply != nil || !controller.isPreparing) }
    guard let pendingReply = reply else { _ = try await task.value; return XCTFail("Second generation was not reached") }
    let phase = try XCTUnwrap(f.page.state.configurationDeparture), saved = try f.register.read().revision
    f.page.detach()
    pendingReply.resume(returning: [replacement]); reply = nil
    let advanced = try await task.value
    XCTAssertFalse(advanced)
    XCTAssertNil(f.page.restartController)
    XCTAssertTrue(f.page.state.presentation === old)
    XCTAssertEqual(f.page.state.configurationDeparture?.id, phase.id)
    XCTAssertEqual(try f.register.read().revision, saved)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertFalse(controller.request())
  }

  func testDirectNextCorrectionClosesAndAccountsBeforeSecondGeneration() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
    f.input("a")
    let oldID = f.page.state.session.automaticInputAttemptID, oldDisk = try f.register.read().revision
    var reads = 0
    let ready = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in
      reads += 1
      if reads == 2 {
        XCTAssertEqual(f.page.state.session.outcome, .abandoned)
        XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
        XCTAssertNotNil(f.page.state.configurationDeparture)
        XCTAssertFalse(f.page.acceptsInput(for: oldID))
        XCTAssertNotEqual(try f.register.read().revision, oldDisk)
      }
      return [.init(id: "medium", title: "Owned replacement", text: "ef gh", language: .english, length: .medium)]
    })
    let saved = try f.register.read().revision
    guard case .advanced(let previous) = try f.coordinator.advance(ready, to: f.page) else { return XCTFail("No delivery") }
    XCTAssertEqual(reads, 2)
    XCTAssertNil(previous.incomplete, "The checkpoint already recorded the departure")
    XCTAssertEqual(previous.session.automaticInputAttemptID, oldID)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(try f.register.read().revision, saved)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertTrue(f.page.state.presentation?.currentSystemIsDark == true)
  }

  func testDirectCorrectionClockInvalidationCannotSaveOrAcceptDeparture() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
    let disk = try f.register.read().revision
    var armed = false
    var state = f.page.state
    state.session = try XCTUnwrap(state.practice?.session).withElapsedClock(.init {
      if armed { armed = false; f.page.detach() }
      return 1
    })
    state.session.insert("a"); f.page.replace(state)
    armed = true
    do {
      _ = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in
        [.init(id: "medium", title: "Owned replacement", text: "ef gh", language: .english, length: .medium)]
      })
      XCTFail("A detached owner accepted a correction")
    } catch WebsiteConfigCommitCoordinatorError.stale {}
    XCTAssertFalse(armed, "The departure clock callback was exercised")
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    XCTAssertEqual(f.page.state.session.outcome, .active)
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

  func testProductionNetworkRepeatKeepsActualRandomAddressesAndDiskIdentity() async throws {
    for name in ["IPv4", "IPv6", "58008", "pseudolang"] {
      let f = try Fixture(); defer { f.close() }
      try await f.publish("{\"mode\":\"words\",\"words\":3,\"punctuation\":true,\"funbox\":[\"\(name)\"]}")
      let old = f.page.state
      let history = try XCTUnwrap(old.session.generatedWordReplayHistory)
      XCTAssertEqual(history.count, 3)
      let disk = try f.register.read().revision
      let controller = try f.bind()
      let advanced = try await controller.requestAndWait(requestID: UUID(), repeatingRequested: true)
      XCTAssertTrue(advanced)
      XCTAssertEqual(f.page.state.session.prompt, old.session.prompt)
      XCTAssertTrue(f.page.state.presentation === old.presentation)
      XCTAssertEqual(try f.register.read().revision, disk)
      for index in 0..<history.count {
        XCTAssertEqual(f.page.state.session.generatedWordReplayHistory?.word(at: index)?.target,
          history.word(at: index)?.target)
      }
    }
  }

  func testArrowRepeatCapturesRealPrefetchedChartStateWithoutAdvancingIt() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"time","time":60,"funbox":["arrows"]}"#,
      random: .init(contentUnit: { 0.5 }))
    var state = f.page.state
    let opening = try XCTUnwrap(state.session.generatedWordReplayHistory?.count)
    state.session.insertBatch(String(state.session.prompt.prefix(4)))
    let history = try XCTUnwrap(state.session.generatedWordReplayHistory)
    XCTAssertGreaterThan(history.count, opening)
    f.page.replace(state)
    XCTAssertEqual(try f.page.captureGeneration(router: f.router).scope.arrowChart, history.arrowChart)
    let disk = try f.register.read().revision
    let controller = try f.bind()
    let repeated = try await controller.requestAndWait(requestID: UUID(), repeatingRequested: true)
    XCTAssertTrue(repeated)
    XCTAssertEqual(f.page.state.practice?.scope.arrowChart, history.arrowChart)
    XCTAssertEqual(f.page.state.session.generatedWordReplayHistory?.count, history.count)
    XCTAssertEqual(try f.register.read().revision, disk)
    var expected = history.arrowChart
    let expectedPrompt = (0..<opening).map { expected.word(first: $0 == 0, randomUnit: { 0.5 })! }.joined()
    let next = try await f.coordinator.prepareNext(for: f.page, random: .init(contentUnit: { 0.5 }))
    guard case .advanced = try f.coordinator.advance(next, to: f.page) else { return XCTFail("Arrow next was not installed") }
    XCTAssertEqual(f.page.state.session.prompt, expectedPrompt)
    XCTAssertEqual(f.page.state.practice?.scope.arrowChart, expected)
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
    var failing = false, reads = 0
    let controller = try f.bind(loadQuotes: { _ in
      reads += 1
      XCTAssertEqual(f.page.state.session.outcome, .abandoned)
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
      if failing { throw Failure.generation }
      return try await withCheckedThrowingContinuation { reply = $0 }
    })
    XCTAssertTrue(controller.request())
    XCTAssertFalse(controller.request(), "A duplicate request must not close/count twice")
    await wait { reply != nil }
    XCTAssertFalse(f.page.acceptsInput(for: oldID))
    failing = true; reply?.resume(throwing: Failure.generation); reply = nil
    await wait { !controller.isPreparing }
    XCTAssertEqual(reads, 3)
    XCTAssertNotNil(controller.message)
    XCTAssertEqual(f.page.state.session.typed, "a")
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(f.page.state.restartDepartureAttemptID, oldID)
    XCTAssertEqual(try f.register.read().revision, disk)
    failing = false; XCTAssertTrue(controller.request())
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
