import XCTest
@testable import Typebar

final class ResultWPMConsistencyTests: XCTestCase {
  private func insert(_ units: [UInt16], at: Double = 0, field: Int = 0,
    payload: [UInt16] = [97], last: Bool = false, correct: Bool = true, commits: Bool? = nil
  ) -> TypingReplayEvent {
    .init(offset: at, kind: .insert, units: payload, commitsWord: commits,
      inputField: .init(index: field, units: units), inputCorrectness: payload.map { _ in correct },
      inputPosition: .init(charIndex: max(0, units.count - 1), lastWord: last))
  }

  func testActualSourceSeparatesInputCadenceFromWPMCredit() {
    let events = [insert([120], payload: [120], correct: false),
      TypingReplayEvent(offset: 0.5, kind: .delete, units: [], inputField: .init(index: 0, units: [])),
      insert([97], at: 1.2)]
    XCTAssertEqual(ResultConsistencyPolicy.metrics(events: events, duration: 2).typing, 100)
    XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: "ab", events: events, duration: 2), 8.90)
  }

  func testActualSourceTrimAndFractionalTailUseCreditedHistory() {
    XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: "ab", events: [
      insert([97,98,32], payload: [32], last: true, correct: false, commits: true)
    ], duration: 2), 66.67)
    XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: "ab", events: [
      insert([97]), insert([97,98], at: 1.5, payload: [98])
    ], duration: 3.5), 76.64)
    XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: "a", events: [insert([97])], duration: 24), 2.72)
  }

  func testSavedKoreanBasisChangesOnlyWPMCreditNotInputCadence() {
    let events = [insert([0xad05], payload: [0xad05])]
    XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: "괅", events: events,
      duration: 2, sourceScoringBasis: .koreanJamo), 66.67)
    XCTAssertEqual(ResultConsistencyPolicy.metrics(events: events, duration: 2).typing, 8.90)
    XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: "괅", events: events, duration: 2), 66.67)
  }

  func testActualSourceKoreanReplacementStoppedSpaceAndFieldOrderHistories() {
    let replacement = [insert([0xac00], payload: [0xac00], correct: false),
      insert([0xac01], at: 1.5, payload: [0xac01])]
    XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: "각", events: replacement, duration: 3.5,
      sourceScoringBasis: .koreanJamo), denseConsistency([24,18,12,10]))
    let stopped = TypingReplayEvent(offset: 0, kind: .insert, units: [32], inputStopped: true,
      inputField: .init(index: 0, units: [0xac00]), inputCorrectness: [false],
      inputPosition: .init(charIndex: 1, lastWord: true))
    XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: "각", events: [stopped], duration: 2,
      sourceScoringBasis: .koreanJamo), 0)
    let ordered = [insert([0xac00], field: 1, payload: [0xac00]),
      insert([0xad05,32], at: 0.5, payload: [32])]
    XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: "괅 가", events: ordered, duration: 2,
      sourceScoringBasis: .koreanJamo), denseConsistency([24,12]))
    let regressed = [insert([0xad05,120], payload: [120]),
      insert([0xac00], at: 0.5, field: 1, payload: [0xac00]),
      TypingReplayEvent(offset: 1.5, kind: .delete, units: [], inputField: .init(index: 0, units: [0xad05]),
        discardedInputUnits: 1, clearedNextWord: true)]
    XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: "괅x가", events: regressed, duration: 2,
      configuration: .words(0).with(modifiers: [.noSpaces]),
      targetWordDirectory: .init(words: ["괅x","가"], noSpace: true), sourceScoringBasis: .koreanJamo),
      denseConsistency([96,12]))
  }

  func testNoFieldOrUnknownNoSpaceHistoryIsUnavailableNotInvented() {
    let old = [TypingReplayEvent(offset: 0, kind: .insert, text: "a")]
    XCTAssertNil(ResultPerformanceTrace.wpmConsistency(prompt: "a", events: old, duration: 2))
    XCTAssertNil(ResultPerformanceTrace.wpmConsistency(prompt: "a", events: [insert([97])], duration: 2,
      configuration: .words(0).with(modifiers: [.noSpaces])))
    XCTAssertNil(ResultPerformanceTrace.wpmConsistency(prompt: "a", events: [], duration: 2))
  }

  private func denseConsistency(_ samples: [Double]) -> Double {
    guard !samples.isEmpty else { return 0 }
    let mean = samples.reduce(0, +) / Double(samples.count)
    guard mean > 0 else { return 0 }
    let deviation = sqrt(samples.reduce(0) { $0 + pow($1 - mean, 2) } / Double(samples.count))
    let cov = deviation / mean
    return ((100 * (1 - tanh(cov + pow(cov, 3) / 3 + pow(cov, 5) / 5)) + Double.ulpOfOne)
      * 100).rounded() / 100
  }

  func testWholeTestAfterChartHorizonMatchesTheActualSource() {
    var events = (0..<122).map { insert(Array(repeating: 97, count: $0 + 1), at: Double($0)) }
    events.append(.init(offset: 122.1, kind: .delete, units: [], inputField: .init(index: 0, units: [])))
    XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: String(repeating: "a", count: 150),
      events: events, duration: 150), 50.72)
    XCTAssertTrue(ResultPerformanceTrace.points(prompt: "a", events: events, duration: 150).isEmpty)
  }

  func testCompressedConstantCreditRunsMatchIndependentDensePopulationIncludingHalfTies() {
    for credit in [1, 2, 5, 16, 127, 4096] {
      for duration in [24.0, 49, 123.5, 377, 8192] {
        var times = (1...Int(duration)).map(Double.init)
        if TestInactivityPolicy.retainsFractionalTail(duration: duration) { times.append(duration) }
        let samples = times.map { (Double(credit) / 5 / ($0 / 60)).rounded() }
        let input = Array(repeating: UInt16(97), count: credit)
        XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: String(repeating: "a", count: credit),
          events: [insert(input)], duration: duration), denseConsistency(samples), "\(credit), \(duration)")
      }
    }
  }

  func testDeterministicChangingCreditSpansMatchIndependentDenseStatistics() {
    var seed: UInt64 = 730_191
    func random(_ limit: Int) -> Int {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1
      return Int(seed >> 32) % limit
    }
    for _ in 0..<100 {
      let duration = Double(1 + random(400)) + [0, 0.497, 0.6, 0.997][random(4)]
      let generated: [(Double, Int)] = (0..<20).map { _ in
        let offset = Double(random(Int(duration) + 1)) + [0.0, 0.2][random(2)]
        return (offset, random(257))
      }
      let ordered = generated.enumerated().sorted { lhs, rhs in
        lhs.element.0 == rhs.element.0 ? lhs.offset < rhs.offset : lhs.element.0 < rhs.element.0
      }
      let updates: [(Double, Int)] = ordered.map { $0.element }.filter { $0.0 <= duration }
      let events = updates.map { insert(Array(repeating: 97, count: $0.1), at: $0.0) }
      var times = (1...Int(duration)).map(Double.init)
      if TestInactivityPolicy.retainsFractionalTail(duration: duration) { times.append(duration) }
      let samples = times.map { time in
        let credit = updates.last { $0.0 <= time }?.1 ?? 0
        return (Double(credit) / 5 / (time / 60)).rounded()
      }
      XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: String(repeating: "a", count: 256),
        events: events, duration: duration), denseConsistency(samples))
    }
  }

  func testHugeFiniteDurationRetainsImplicitZerosWithoutDurationSizedWork() {
    let began = ProcessInfo.processInfo.systemUptime
    for duration in [1e20, Double.greatestFiniteMagnitude] {
      XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: "a", events: [insert([97])], duration: duration), 0)
    }
    XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - began, 1)
  }

  func testTenThousandChangingFieldsDoNotRescanEveryPriorWordAtEverySecond() throws {
    let count = 10_000
    let events: [TypingReplayEvent] = (0..<count).map { index in
      let units: [UInt16] = index == count - 1 ? [97] : [97,32]
      return insert(units, at: Double(index), field: index, payload: units)
    }
    let duration = Double(count) - 0.5
    var expected = (1..<count).map { second in
      let credit = min(2 * (second + 1), 2 * count - 1)
      return (Double(credit) / 5 / (Double(second) / 60)).rounded()
    }
    expected.append((Double(2 * count - 1) / 5 / (duration / 60)).rounded())
    let began = ProcessInfo.processInfo.systemUptime
    let actual = try XCTUnwrap(ResultPerformanceTrace.wpmConsistency(
      prompt: Array(repeating: "a", count: count).joined(separator: " "), events: events, duration: duration))
    XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - began, 5,
      "Changing fields require incremental credit totals, not quadratic whole-field scans")
    XCTAssertEqual(actual, denseConsistency(expected))
  }

  func testActualSourceNonemptyMaximumDeletionReentryAndFirstAppearanceStayIndependent() {
    let events: [TypingReplayEvent] = [insert([98], field: 1, payload: [98]),
      insert([97,32], at: 1.2, payload: [32]),
      .init(offset: 2.2, kind: .delete, units: [], inputField: .init(index: 1, units: [])),
      insert([99], at: 3.2, field: 2, payload: [99]),
      .init(offset: 4.2, kind: .delete, units: [], inputField: .init(index: 2, units: [])),
      insert([98,32], at: 5.2, field: 1, payload: [32]),
      insert([99], at: 6.2, field: 2, payload: [99])]
    XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: "a b c", events: events, duration: 7),
      denseConsistency([12,6,0,9,0,8,9]))
  }

  func testStableOffsetsLateEventsAndInvalidTimesDoNotChangeTheResult() {
    let valid = [insert([97]), insert([97,98], at: 1.5, payload: [98])]
    XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: "ab", events: valid.reversed() + [
      insert([120], at: .nan), insert([120], at: -1), insert([120], at: .infinity),
      insert([120], at: 4, field: Int.max)
    ], duration: 3.5), 76.64)
    let tied = [insert([120]), TypingReplayEvent(offset: 0, kind: .delete, units: [],
      inputField: .init(index: 0, units: [])), insert([97])]
    XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: "a", events: tied, duration: 2), 66.67)
  }

  func testModeTailGateAndNoSamplesRemainDistinctFromUnavailableEvidence() {
    for duration in [Double.nan, .infinity, -.infinity, -1, 0] {
      XCTAssertNil(ResultPerformanceTrace.wpmConsistency(prompt: "a", events: [insert([97])], duration: duration))
    }
    XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: "a", events: [insert([97])], duration: 0.493), 0)
    XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: "a", events: [insert([97])], duration: 0.497), 100)
    for config in [TestConfiguration.timed(seconds: 1), .words(0)] {
      XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: "a", events: [insert([97])],
        duration: 0.497, configuration: config), 0)
    }
  }

  func testNoSpaceDirectoryZenAndMalformedFieldBoundaries() {
    let events = [insert([0xad05], payload: [0xad05])]
    let config = TestConfiguration.words(0).with(modifiers: [.noSpaces])
    XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: "괅", events: events, duration: 2,
      configuration: config, targetWordDirectory: .init(words: ["괅"], noSpace: true),
      sourceScoringBasis: .koreanJamo), 66.67)
    XCTAssertNil(ResultPerformanceTrace.wpmConsistency(prompt: "괅", events: events, duration: 2,
      configuration: config, targetWordDirectory: .init(words: ["각"], noSpace: true)))
    XCTAssertNil(ResultPerformanceTrace.wpmConsistency(prompt: "a", events: [insert([97], field: Int.max)], duration: 2))
    let zen = TestConfiguration(mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())
    XCTAssertEqual(ResultPerformanceTrace.wpmConsistency(prompt: "", events: events, duration: 2,
      configuration: zen, sourceScoringBasis: .koreanJamo), 66.67)
  }

  func testCSVAppendsIndependentMetricAndRoundTripLeavesStoredScoresIntact() throws {
    let start = Date(timeIntervalSince1970: 100)
    let events = [insert([120], payload: [120]),
      TypingReplayEvent(offset: 0.5, kind: .delete, units: [], inputField: .init(index: 0, units: [])),
      insert([97], at: 1.2)]
    let original = CompletedTestResult(id: UUID(), configuration: .words(1), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(2), typedCharacterCount: 2,
      correctCharacterCount: 1, errorCount: 1, wpm: 37, rawWpm: 53, accuracy: 50, prompt: "ab", replayEvents: events)
    let saved = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(original))
    XCTAssertEqual(saved, original)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: saved).portableResult), saved)
    func fields(_ value: CompletedTestResult) -> [String: String] {
      let row = ResultCSVExport.csvString(for: [value]).components(separatedBy: "\r\n")[1].components(separatedBy: ",")
      XCTAssertEqual(row.count, ResultCSVExport.columns.count)
      return Dictionary(uniqueKeysWithValues: zip(ResultCSVExport.columns, row))
    }
    let columns = fields(saved)
    XCTAssertEqual(columns["typing_consistency_percent"], "100.00")
    XCTAssertEqual(columns["wpm_consistency_percent"], "8.90")
    XCTAssertEqual(columns["wpm"], "37")
    XCTAssertEqual(columns["raw_wpm"], "53")
    XCTAssertEqual(RemoteResultSubmission(result: saved).consistency, 100)
    var old = original
    old = .init(id: old.id, configuration: old.configuration, outcome: old.outcome,
      startedAt: old.startedAt, finishedAt: old.finishedAt, typedCharacterCount: old.typedCharacterCount,
      correctCharacterCount: old.correctCharacterCount, errorCount: old.errorCount,
      wpm: old.wpm, rawWpm: old.rawWpm, accuracy: old.accuracy, prompt: old.prompt,
      replayEvents: [.init(offset: 0, kind: .insert, text: "a")])
    XCTAssertEqual(fields(old)["wpm_consistency_percent"], "")
    XCTAssertTrue(ResultCSVExport.columns.contains("wpm_consistency_percent"))
  }
}
