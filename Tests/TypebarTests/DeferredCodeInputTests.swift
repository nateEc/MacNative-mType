import XCTest
@testable import Typebar

final class DeferredCodeInputTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 907_100_000)

  private func saved(_ input: TypingSession) throws -> CompletedTestResult {
    var ended = input
    ended.bailOut(at: start.addingTimeInterval(3))
    return try XCTUnwrap(ended.result())
  }

  func testLaterBatchCharacterIsProcessedBeforeQueuedTabAndChangesItsCorrectness() throws {
    var input = TypingSession(configuration: .words(10, language: .codeSwift), prompt: "\t\tgo() tail")
    XCTAssertEqual(TypingLiveInputFeedback.insertBatch("\tX", into: &input, at: start), [false, false])
    XCTAssertEqual(input.typed, "\tX\t")
    let result = try saved(input)
    XCTAssertEqual(result.replayEvents.map(\.text), ["\t", "X", "\t"])
    XCTAssertEqual(result.replayEvents.map(\.automatic), [false, false, true])
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 1)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 3)
  }

  func testDistinctScheduledRequestsAreNotMergedOrRevalidatedAtExecution() throws {
    var input = TypingSession(configuration: .words(10, language: .codeSwift), prompt: "\t\t\tgo() tail")
    XCTAssertEqual(TypingLiveInputFeedback.insertBatch("\t\t", into: &input, at: start), [true, true, false])
    XCTAssertEqual(input.typed, "\t\t\t\t")
    let result = try saved(input)
    XCTAssertEqual(result.replayEvents.map(\.automatic), [false, false, true, true])
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 3)
  }

  func testFullyTypedBatchFinishesBeforeQueuedTabCanMutateOrSound() throws {
    var input = TypingSession(configuration: .words(1, language: .codeSwift), prompt: "\t\tgo()")
    XCTAssertEqual(TypingLiveInputFeedback.insertBatch("\t\tgo()", into: &input, at: start), [true])
    XCTAssertEqual(input.typed, "\t\tgo()")
    XCTAssertEqual(input.outcome, .completed)
    let result = try XCTUnwrap(input.result())
    XCTAssertFalse(result.replayEvents.contains(where: \.automatic))
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 6)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 6)
  }

  func testOrdinaryBatchStillHasOneFinalFeedbackAndNoAutomaticEvents() throws {
    var input = TypingSession(configuration: .words(10), prompt: "abc tail")
    XCTAssertEqual(TypingLiveInputFeedback.insertBatch("xb", into: &input, at: start), [true])
    XCTAssertEqual(input.typed, "xb")
    XCTAssertFalse(try saved(input).replayEvents.contains(where: \.automatic))
  }

  func testLiveDeferralLeavesManualBatchUntouchedUntilOneCallbackRuns() throws {
    var input = TypingSession(configuration: .words(10, language: .codeSwift), prompt: "\t\tgo() tail")
    XCTAssertEqual(TypingLiveInputFeedback.insertBatch("\tX", into: &input, at: start,
      defersAutomaticInput: true), [false])
    XCTAssertEqual(input.typed, "\tX")
    XCTAssertTrue(input.hasPendingAutomaticInput)
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID), [false])
    XCTAssertEqual(input.typed, "\tX\t")
    XCTAssertFalse(input.hasPendingAutomaticInput)
    XCTAssertEqual(try saved(input).replayEvents.map(\.automatic), [false, false, true])
  }

  func testEachCallbackQueuesAtMostOneSuccessorAndPreservesTimestamp() throws {
    var input = TypingSession(configuration: .words(10, language: .codeSwift), prompt: "ab \t\t\tgo() tail")
    _ = input.insertBatch("ab ", at: start, defersAutomaticInput: true)
    XCTAssertEqual(input.typed, "ab ")
    for tabs in 1...3 {
      XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID), [true])
      XCTAssertEqual(input.typed, "ab " + String(repeating: "\t", count: tabs))
      XCTAssertEqual(input.hasPendingAutomaticInput, tabs < 3)
    }
    let automatic = try saved(input).replayEvents.filter(\.automatic)
    XCTAssertEqual(automatic.count, 3)
    XCTAssertTrue(automatic.allSatisfy { $0.offset == 0 })
  }

  func testDeletionDoesNotCancelAnAlreadyScheduledTab() throws {
    var input = TypingSession(configuration: .words(10,
      rules: .init(codeUnindentOnBackspace: true), language: .codeSwift), prompt: "\t\tgo() tail")
    _ = input.insertBatch("\t", at: start, defersAutomaticInput: true)
    input.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "")
    XCTAssertTrue(input.hasPendingAutomaticInput)
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID), [true])
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID), [true])
    XCTAssertEqual(input.typed, "\t\t")
    let result = try saved(input)
    XCTAssertEqual(result.replayEvents.filter(\.automatic).map(\.offset), [0, 0])
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 3)
    // The reference also sorts old-timestamp callbacks before the later
    // deletion in a result log; do not fabricate a new timestamp here.
  }

  func testChangedLiveDeletionRuleIsAppliedWhenCallbackActuallyExecutes() throws {
    var input = TypingSession(configuration: .words(10, language: .codeSwift), prompt: "\t\tgo() tail")
    _ = input.insertBatch("\tX", at: start, defersAutomaticInput: true)
    input.synchronizeLiveInputRules(.init(deleteOnErrorMode: .letter))
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID), [false])
    XCTAssertEqual(input.typed, "\t")
    XCTAssertFalse(input.hasPendingAutomaticInput)
    let result = try saved(input)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 3)
    XCTAssertEqual(result.replayEvents.filter(\.automatic).map(\.kind), [.insert, .delete, .delete])
  }

  func testAutomaticWrongTabAndItsErrorRecoveryStayAutomaticAndNotPhysical() throws {
    var input = TypingSession(configuration: .words(10, language: .codeSwift), prompt: "\t\tgo() tail")
    _ = input.insertBatch("\tX", at: start, origin: .virtualKeyboard, defersAutomaticInput: true)
    input.synchronizeLiveInputRules(.init(deleteOnErrorMode: .word))
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID), [false])
    XCTAssertEqual(input.typed, "")
    XCTAssertTrue(input.hasUsedOnlyVirtualKeyboard)
    let result = try saved(input)
    XCTAssertTrue(result.replayEvents.dropFirst(2).allSatisfy(\.automatic))
    XCTAssertEqual(result.replayEvents.filter(\.automatic).first?.kind, .insert)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 3)
  }

  func testOldAttemptCallbackCannotConsumeNewAttemptsPendingRequest() {
    var old = TypingSession(configuration: .words(10, language: .codeSwift), prompt: "\t\tgo() tail")
    _ = old.insertBatch("\t", at: start, defersAutomaticInput: true)
    var replacement = old.repeatedAttempt()
    XCTAssertNotEqual(replacement.automaticInputAttemptID, old.automaticInputAttemptID)
    XCTAssertFalse(replacement.hasPendingAutomaticInput)
    _ = replacement.insertBatch("\t", at: start.addingTimeInterval(1), defersAutomaticInput: true)
    XCTAssertEqual(replacement.processNextAutomaticInput(for: old.automaticInputAttemptID), [])
    XCTAssertEqual(replacement.typed, "\t")
    XCTAssertTrue(replacement.hasPendingAutomaticInput)
    XCTAssertEqual(replacement.processNextAutomaticInput(for: replacement.automaticInputAttemptID), [true])
    XCTAssertEqual(replacement.typed, "\t\t")
  }

  func testTerminalOutcomesSuppressQueuedInputWithoutSoundOrAttempts() throws {
    for terminal in 0..<3 {
      var input = TypingSession(configuration: .timed(seconds: 1, language: .codeSwift), prompt: "\t\tgo() tail")
      _ = input.insertBatch("\t", at: start, defersAutomaticInput: true)
      if terminal == 0 { input.bailOut(at: start.addingTimeInterval(1)) }
      else if terminal == 1 { input.abandon(at: start.addingTimeInterval(1)) }
      else { input.tick(at: start.addingTimeInterval(1)) }
      XCTAssertTrue(input.isFinished)
      XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID), [])
      XCTAssertEqual(input.typed, "\t")
      XCTAssertFalse(input.hasPendingAutomaticInput)
    }
  }

  func testCancellationDropsOnlyQueueAndDoesNotInventReplayOrAttempts() throws {
    var input = TypingSession(configuration: .words(10, language: .codeSwift), prompt: "\t\tgo() tail")
    _ = input.insertBatch("\t", at: start, defersAutomaticInput: true)
    let before = try saved(input)
    input.cancelAutomaticInput()
    let after = try saved(input)
    XCTAssertFalse(input.hasPendingAutomaticInput)
    XCTAssertEqual(after.inputMetrics, before.inputMetrics)
    XCTAssertEqual(after.replayEvents, before.replayEvents)
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID), [])
  }

  func testNoSpaceBoundaryAndVirtualOriginSurviveSeparateAutomaticTurns() {
    var input = TypingSession(configuration: .words(10, language: .codeSwift).with(modifiers: [.noSpaces]),
      prompt: "ab\t\tgo()tail", noSpaceWordEndIndices: [2, 8, 12],
      noSpaceTargetWords: ["ab", "\t\tgo()", "tail"])
    _ = input.insertBatch("ab", at: start, origin: .virtualKeyboard, defersAutomaticInput: true)
    XCTAssertEqual(input.typed, "ab")
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID), [true])
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID), [true])
    XCTAssertEqual(input.typed, "ab\t\t")
    XCTAssertTrue(input.hasUsedOnlyVirtualKeyboard)
  }

  func testAutomaticFinalTabCanFinishAndPendingTapeRoundTripsWithoutQueueState() throws {
    var input = TypingSession(configuration: .words(1, language: .codeSwift), prompt: "\t\t")
    _ = input.insertBatch("\t", at: start, defersAutomaticInput: true)
    XCTAssertEqual(input.outcome, .active)
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID), [true])
    XCTAssertEqual(input.outcome, .completed)
    let result = try XCTUnwrap(input.result())
    let decoded = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result))
    XCTAssertEqual(decoded, result)
    XCTAssertEqual(TypingReplay.typedText(events: decoded.replayEvents, through: 1), "\t\t")
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    XCTAssertEqual(archive.results[0], result)
  }

  func testDelayedAutomaticCompletionUsesExecutionClockButOriginalReplayTimestamp() throws {
    var input = TypingSession(configuration: .words(1, language: .codeSwift), prompt: "\t\t")
    _ = input.insertBatch("\t", at: start, defersAutomaticInput: true)
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID,
      executedAt: start.addingTimeInterval(1)), [true])
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(result.finishedAt, start.addingTimeInterval(1))
    XCTAssertEqual(result.replayEvents.map(\.offset), [0, 0])
    XCTAssertEqual(result.outcome, .completed)
  }

  func testDelayedAutomaticMasterFailureUsesExecutionClock() throws {
    var configuration = TestConfiguration.words(10, language: .codeSwift)
    configuration.difficulty = .master
    var input = TypingSession(configuration: configuration, prompt: "\t\t\tgo() tail")
    _ = input.insertBatch("\t\t", at: start, defersAutomaticInput: true)
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID,
      executedAt: start.addingTimeInterval(1)), [true])
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID,
      executedAt: start.addingTimeInterval(2)), [false])
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(result.finishedAt, start.addingTimeInterval(2))
    XCTAssertEqual(result.outcome, .failed)
    XCTAssertEqual(result.replayEvents.map(\.offset), [0, 0, 0, 0])
  }

  @MainActor private final class FIFO {
    var actions: [TypingAutomaticInputScheduler.Action] = []
    func runNext() { actions.removeFirst()() }
  }

  @MainActor
  func testSchedulerDefersAndDeduplicatesOnlyTheWakeupNotInputRequests() {
    let fifo = FIFO()
    let scheduler = TypingAutomaticInputScheduler(enqueue: { fifo.actions.append($0) })
    let attempt = UUID()
    var callbacks = 0
    scheduler.schedule(for: attempt) { callbacks += 1 }
    scheduler.schedule(for: attempt) { callbacks += 10 }
    XCTAssertEqual(callbacks, 0)
    XCTAssertEqual(fifo.actions.count, 1)
    fifo.runNext()
    XCTAssertEqual(callbacks, 1)
  }

  @MainActor
  func testSchedulerOldAttemptTicketCannotClearOrRunNewAttemptTicket() {
    let fifo = FIFO()
    let scheduler = TypingAutomaticInputScheduler(enqueue: { fifo.actions.append($0) })
    var callbacks = 0
    scheduler.schedule(for: UUID()) { callbacks += 1 }
    scheduler.schedule(for: UUID()) { callbacks += 10 }
    fifo.runNext()
    XCTAssertEqual(callbacks, 0)
    fifo.runNext()
    XCTAssertEqual(callbacks, 10)
  }

  @MainActor
  func testCancelAndRequeueSameAttemptDoesNotReviveOldTicket() {
    let fifo = FIFO()
    let scheduler = TypingAutomaticInputScheduler(enqueue: { fifo.actions.append($0) })
    let attempt = UUID()
    var callbacks = 0
    scheduler.schedule(for: attempt) { callbacks += 1 }
    scheduler.cancel()
    scheduler.schedule(for: attempt) { callbacks += 10 }
    fifo.runNext()
    XCTAssertEqual(callbacks, 0)
    fifo.runNext()
    XCTAssertEqual(callbacks, 10)
  }

  @MainActor
  func testQueuedClosureDoesNotRetainReleasedSchedulerOwner() {
    let fifo = FIFO()
    var scheduler: TypingAutomaticInputScheduler? = .init(enqueue: { fifo.actions.append($0) })
    weak var weakScheduler = scheduler
    var callbacks = 0
    scheduler?.schedule(for: UUID()) { callbacks += 1 }
    scheduler = nil
    XCTAssertNil(weakScheduler)
    fifo.runNext()
    XCTAssertEqual(callbacks, 0)
  }

  @MainActor
  func testActualMainQueueDefaultSchedulerIsNotInline() async {
    let scheduler = TypingAutomaticInputScheduler()
    defer { scheduler.cancel() }
    var ran = false
    await withCheckedContinuation { continuation in
      scheduler.schedule(for: UUID()) {
        ran = true
        continuation.resume()
      }
      XCTAssertFalse(ran)
    }
    XCTAssertTrue(ran)
  }

  func testLongIndentChainIsIterativeAndKeepsEachAutomaticPrimitive() throws {
    let count = 1_000
    var input = TypingSession(configuration: .words(10, language: .codeSwift),
      prompt: String(repeating: "\t", count: count) + "go() tail")
    _ = input.insertBatch("\t", at: start, defersAutomaticInput: true)
    var callbacks = 0
    while input.hasPendingAutomaticInput {
      XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID), [true])
      callbacks += 1
    }
    XCTAssertEqual(callbacks, count - 1)
    XCTAssertEqual(input.typed, String(repeating: "\t", count: count))
    XCTAssertEqual(try saved(input).replayEvents.filter(\.automatic).count, count - 1)
  }
}
