import XCTest
@testable import Typebar

final class FieldPerformanceTraceTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 908_700_000)

  private func delayedResult(unicode: Bool, finish: Bool) throws -> CompletedTestResult {
    let first = unicode ? "é" : "a"
    var session = TypingSession(configuration: .words(2,
      rules: .init(deleteOnErrorMode: .letter), language: .codeSwift), prompt: first + " \tb")
    session.insertBatch(first + " ", at: start, defersAutomaticInput: true)
    session.insertBatch("\t", at: start.addingTimeInterval(1), defersAutomaticInput: true)
    XCTAssertEqual(session.processNextAutomaticInput(for: session.automaticInputAttemptID,
      executedAt: start.addingTimeInterval(3)), [false])
    XCTAssertEqual(session.typed, first + " ")
    if finish { session.insertBatch("\tb", at: start.addingTimeInterval(4)) }
    else { session.bailOut(at: start.addingTimeInterval(4)) }
    return try XCTUnwrap(session.result())
  }

  func testActualRawDelayedTabChartUsesFieldSnapshotsInsteadOfCrossWordDeletion() throws {
    let result = try delayedResult(unicode: true, finish: false)
    let points = ResultPerformanceTrace.points(prompt: result.prompt, events: result.replayEvents,
      duration: 4, configuration: result.configuration)
    XCTAssertEqual(points.map(\.wpm), [36,18,12,9])
    XCTAssertEqual(points.map(\.rawWpm), [36,18,12,9])
    XCTAssertEqual(points.map(\.errorCount), [1,0,0,0])
    XCTAssertEqual(points.map(\.burstWpm), [48,0,0,0])
  }

  func testLaterCorrectRawFieldRestoresTheSourceFinalChartWithoutRescoringResult() throws {
    let result = try delayedResult(unicode: true, finish: true)
    let points = ResultPerformanceTrace.points(prompt: result.prompt, events: result.replayEvents,
      duration: 4, configuration: result.configuration)
    XCTAssertEqual(points.map(\.wpm), [36,18,12,12])
    XCTAssertEqual(points.map(\.rawWpm), [36,18,12,12])
    XCTAssertEqual(points.map(\.errorCount), [1,0,0,0])
    XCTAssertEqual(points.map(\.burstWpm), [48,0,0,24])
    XCTAssertEqual(result.wpm, 12)
    XCTAssertEqual(result.rawWpm, 12)
  }

  func testActualASCIIJudgmentFieldLogGetsTheSameSnapshotChart() throws {
    let result = try delayedResult(unicode: false, finish: false)
    XCTAssertTrue(result.replayEvents.allSatisfy { $0.textUTF16 == nil })
    let points = ResultPerformanceTrace.points(prompt: result.prompt, events: result.replayEvents,
      duration: 4, configuration: result.configuration)
    XCTAssertEqual(points.map(\.wpm), [36,18,12,9])
    XCTAssertEqual(points.map(\.rawWpm), [36,18,12,9])
    XCTAssertEqual(points.map(\.errorCount), [1,0,0,0])
  }

  func testSourceFirstAppearanceOrderAndInferredActiveFieldAreNotNumericSorting() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "c", inputField: .init(index: 1, value: "c")),
      .init(offset: 1, kind: .insert, text: "a", inputField: .init(index: 0, value: "a")),
      .init(offset: 1, kind: .insert, text: "b", inputField: .init(index: 0, value: "ab")),
      .init(offset: 1, kind: .insert, text: " ", inputField: .init(index: 0, value: "ab "))]
    let points = ResultPerformanceTrace.points(prompt: "ab cd x", events: events, duration: 2)
    XCTAssertEqual(points.map(\.wpm), [12,6])
    XCTAssertEqual(points.map(\.rawWpm), [12,6])
  }

  func testForwardGapUsesTheRecordedTargetIndexWithoutPlaceholderWords() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "a", inputField: .init(index: 0, value: "a")),
      .init(offset: 0, kind: .insert, text: " ", inputField: .init(index: 0, value: "a ")),
      .init(offset: 1, kind: .insert, text: "c", inputField: .init(index: 2, value: "c"))]
    let points = ResultPerformanceTrace.points(prompt: "a b c", events: events, duration: 2)
    XCTAssertEqual(points.map(\.wpm), [36,18])
    XCTAssertEqual(points.map(\.rawWpm), [36,18])
  }

  func testNativeWrongSeparatorGetsNoWholeWordCreditInTheChart() throws {
    var session = TypingSession(configuration: .words(3), prompt: "é beta\nlast")
    session.insertBatch("é\n", at: start)
    session.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    let points = ResultPerformanceTrace.points(prompt: result.prompt, events: result.replayEvents,
      duration: 2, configuration: result.configuration)
    XCTAssertEqual(points.map(\.wpm), [0,0])
    XCTAssertEqual(points.map(\.rawWpm), [24,12])
    XCTAssertEqual(points.map(\.errorCount), [1,0])
  }

  func testStoppedSpaceOwnsActivityButSourceInferenceDoesNotCreditAnUncommittedPrefix() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "a", inputField: .init(index: 0, value: "a")),
      .init(offset: 1, kind: .insert, text: " ", inputStopped: true,
        inputField: .init(index: 0, value: "a"), inputCorrectness: [false])]
    let points = ResultPerformanceTrace.points(prompt: "ab cd", events: events, duration: 2)
    XCTAssertEqual(points.map(\.wpm), [0,0])
    XCTAssertEqual(points.map(\.rawWpm), [12,6])
    XCTAssertEqual(points.map(\.errorCount), [1,0])
    XCTAssertEqual(points.map(\.burstWpm), [24,0])
  }

  func testRawFieldSnapshotCannotConfuseLoneSurrogateWithLiteralReplacement() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, units: [55357],
        inputField: .init(index: 0, units: [55357]), inputCorrectness: [false])]
    let point = ResultPerformanceTrace.point(prompt: "�x", events: events, elapsed: 1)
    XCTAssertEqual(point.wpm, 0)
    XCTAssertEqual(point.rawWpm, 12)
    XCTAssertEqual(point.errorCount, 1)
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "🙂x", events: events, elapsed: 1).wpm, 12)
  }

  func testGroupedReturnUsesEachDestinationSnapshotAndLeavesPastAttempts() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, units: [233,32], inputField: .init(index: 0, units: [233,32])),
      .init(offset: 1, kind: .insert, units: [99], inputField: .init(index: 1, units: [99])),
      .init(offset: 2, kind: .delete, units: [], wordDeletionCount: 2,
        inputField: .init(index: 1, units: [])),
      .init(offset: 2, kind: .delete, units: [], inputField: .init(index: 0, units: [233]))]
    let point = ResultPerformanceTrace.point(prompt: "é cd", events: events, elapsed: 2)
    XCTAssertEqual(point.wpm, 6)
    XCTAssertEqual(point.rawWpm, 6)
    XCTAssertEqual(point.burstWpm, 0)
    XCTAssertEqual(point.errorCount, 0)
  }

  func testRawJudgmentsBeatFieldTextAndForcedInputDoesNotAlterSnapshotSpeedCredit() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, units: [233], forceError: true,
        inputField: .init(index: 0, units: [233]), inputCorrectness: [false])]
    let point = ResultPerformanceTrace.point(prompt: "éx", events: events, elapsed: 1)
    XCTAssertEqual(point.wpm, 12)
    XCTAssertEqual(point.errorCount, 1)
    let zen = TestConfiguration(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init())
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "", events: events,
      elapsed: 1, configuration: zen).errorCount, 0)
  }

  func testPartialTailAndSinglePointKeepOriginalIntervalBoundaries() throws {
    let result = try delayedResult(unicode: true, finish: false)
    let points = ResultPerformanceTrace.points(prompt: result.prompt, events: result.replayEvents,
      duration: 3.5, configuration: result.configuration)
    XCTAssertEqual(points.map(\.wpm), [36,18,12,10])
    XCTAssertEqual(points.last, ResultPerformanceTrace.point(prompt: result.prompt,
      events: result.replayEvents, elapsed: 3.5, configuration: result.configuration))
    let first = ResultPerformanceTrace.point(prompt: result.prompt, events: result.replayEvents,
      elapsed: 0.5, configuration: result.configuration)
    XCTAssertEqual(first.wpm, 48)
    XCTAssertEqual(first.rawWpm, 48)
    XCTAssertEqual(first.errorCount, 1)
    XCTAssertEqual(first.burstWpm, 72)
  }

  func testPortableAndFormalArchiveKeepFieldCurvesWithoutChangingStoredResults() throws {
    for unicode in [false, true] {
      let result = try delayedResult(unicode: unicode, finish: false)
      let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [result], presets: [], at: start)
      let archive = try TypebarDataTransfer.importArchive(from: data)
      let portable = try XCTUnwrap(TestResultRecord(result: result).portableResult)
      for restored in [archive.results[0], portable] {
        XCTAssertEqual(restored, result)
        let points = ResultPerformanceTrace.points(prompt: restored.prompt, events: restored.replayEvents,
          duration: 4, configuration: restored.configuration)
        XCTAssertEqual(points.map(\.wpm), [36,18,12,9])
      }
      XCTAssertEqual(archive.version, TypebarArchive.currentVersion)
    }
  }

  func testMissingFieldsKeepThePriorRawAndLegacyPathsWithoutInventingSnapshots() {
    let raw: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, units: [233],
      inputField: .init(index: 0, units: [233])), .init(offset: 1, kind: .delete, units: [])]
    let legacy: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, text: "ab",
      inputField: .init(index: 0, value: "ab")), .init(offset: 1, kind: .delete, text: "")]
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "éx", events: raw, elapsed: 2).rawWpm, 0)
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "ab", events: legacy, elapsed: 2).wpm, 6)
  }

  func testHugeNegativeAndMalformedFieldMetadataDoNotBecomeTargetDirectories() {
    for field in [TypingReplayInputField(index: Int.max, value: "a"),
      .init(index: -1, value: "a"), .init(index: 0, value: "a", valueUTF16: [98])] {
      let event = TypingReplayEvent(offset: 0, kind: .insert, text: "a", inputField: field)
      XCTAssertEqual(ResultPerformanceTrace.point(prompt: "ab", events: [event], elapsed: 1).wpm, 12)
    }
  }

  func testNoSpaceMetadataDoesNotGuessUnsavedTargetWordSlices() {
    let configuration = TestConfiguration.words(2).with(modifiers: [.noSpaces])
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "ax", inputField: .init(index: 0, value: "ax")),
      .init(offset: 1, kind: .insert, text: "cd", inputField: .init(index: 1, value: "cd"))]
    let point = ResultPerformanceTrace.point(prompt: "abcd", events: events, elapsed: 2,
      configuration: configuration)
    XCTAssertEqual(point.wpm, 18, "Still the prior flat fallback, not a claim of hidden word credit")
    XCTAssertEqual(point.rawWpm, 24)
  }

  func testGenuineArchiveTwelveKeepsItsMetricsWhileFieldChartReadsOriginalSnapshots() throws {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "a", inputField: .init(index: 0, value: "a")),
      .init(offset: 0, kind: .insert, text: " ", inputField: .init(index: 0, value: "a ")),
      .init(offset: 0, kind: .insert, text: "\t", automatic: true,
        inputField: .init(index: 1, value: "\t\t")),
      .init(offset: 0, kind: .delete, text: "", automatic: true, inputField: .init(index: 1, value: "\t")),
      .init(offset: 0, kind: .delete, text: "", automatic: true, inputField: .init(index: 1, value: "")),
      .init(offset: 1, kind: .insert, text: "\t", inputField: .init(index: 1, value: "\t"))]
    let original = CompletedTestResult(id: UUID(), configuration: .words(2, language: .codeSwift),
      outcome: .bailedOut, startedAt: start, finishedAt: start.addingTimeInterval(4),
      typedCharacterCount: 2, correctCharacterCount: 2, errorCount: 1, wpm: 6, rawWpm: 6, accuracy: 75,
      prompt: "a \tb", replayEvents: events)
    let archive = TypebarArchive(version: 12, exportedAt: start, settings: .init(), results: [original], presets: [])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let restored = try TypebarDataTransfer.importArchive(from: encoder.encode(archive))
    XCTAssertEqual(restored.version, 12)
    XCTAssertEqual(restored.results[0], original)
    let points = ResultPerformanceTrace.points(prompt: original.prompt, events: restored.results[0].replayEvents,
      duration: 4, configuration: original.configuration)
    XCTAssertEqual(points.map(\.wpm), [36,18,12,9])
    XCTAssertEqual(points.map(\.errorCount), [1,0,0,0])
    XCTAssertEqual(restored.results[0].wpm, 6, "A chart does not rewrite the archived score")
  }

  func testReferenceSpaceNormalizationDoesNotLoseUnitIdentityOrAttemptJudgments() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, units: [97,12288],
        inputField: .init(index: 0, units: [97,12288]), inputCorrectness: [true,true]),
      .init(offset: 0, kind: .insert, units: [98],
        inputField: .init(index: 1, units: [98]), inputCorrectness: [true])]
    let point = ResultPerformanceTrace.point(prompt: "a b", events: events, elapsed: 1)
    XCTAssertEqual(point.wpm, 36)
    XCTAssertEqual(point.rawWpm, 36)
    XCTAssertEqual(point.errorCount, 0)
    XCTAssertEqual(events[0].inputField?.valueUTF16, [97,12288], "Only derivation normalizes spaces")
  }

  func testNonFiniteOffsetsAreFilteredBeforeFieldEligibilityAndStableTiesUseLastSnapshot() {
    let events: [TypingReplayEvent] = [
      .init(offset: .nan, kind: .insert, text: "x"),
      .init(offset: 0, kind: .insert, units: [233], inputField: .init(index: 0, units: [233])),
      .init(offset: 0, kind: .delete, units: [], inputField: .init(index: 0, units: [])),
      .init(offset: 0, kind: .insert, units: [233], inputField: .init(index: 0, units: [233]))]
    let point = ResultPerformanceTrace.point(prompt: "éx", events: events, elapsed: 1)
    XCTAssertEqual(point.wpm, 12)
    XCTAssertEqual(point.rawWpm, 12)
    XCTAssertEqual(point.burstWpm, 24)
  }
}
