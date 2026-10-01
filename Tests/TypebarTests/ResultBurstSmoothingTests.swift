import XCTest
@testable import Typebar

final class ResultBurstSmoothingTests: XCTestCase {
  private func points(_ bursts: [Int]) -> [ResultPerformancePoint] {
    bursts.enumerated().map { index, burst in
      .init(elapsed: Double(index + 1), wpm: 30 + index, rawWpm: 35 + index,
        burstWpm: Double(burst), errorCount: index % 2)
    }
  }

  private func assertBursts(
    _ points: [ResultPerformancePoint], _ expected: [Double],
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(points.count, expected.count, file: file, line: line)
    for (point, value) in zip(points, expected) {
      XCTAssertEqual(Double(point.burstWpm), value, accuracy: 0.000_000_001, file: file, line: line)
    }
  }

  func testSharpChangesOutsideTheValueWindowStayVisible() {
    let original = points([20, 100, 20, 20])
    XCTAssertEqual(ResultBurstSmoothingPolicy.points(original, enabled: true), original)
  }

  func testSmallChangesUseAnEqualMeanAndRetainFractionalPrecision() {
    assertBursts(ResultBurstSmoothingPolicy.points(points([10, 11, 13]), enabled: true),
      [10.5, 34.0 / 3, 12])
  }

  func testExactlyOneQuarterOfTheMaximumIsIncludedButOutsideIsNot() {
    assertBursts(ResultBurstSmoothingPolicy.points(points([60, 80]), enabled: true), [70, 70])
    assertBursts(ResultBurstSmoothingPolicy.points(points([59, 80]), enabled: true), [59, 80])
  }

  func testValueWindowComesFromTheWholeSeriesNotOnlyLocalNeighbors() {
    assertBursts(ResultBurstSmoothingPolicy.points(points([20, 30, 0, 120]), enabled: true),
      [25, 50.0 / 3, 15, 120])
  }

  func testAveragesReadTheOriginalSeriesAndDoNotCascadePreviousOutput() {
    let original = points([8, 10, 11])
    let smoothed = ResultBurstSmoothingPolicy.points(original, enabled: true)
    assertBursts(smoothed, [9, 29.0 / 3, 10.5])
    XCTAssertEqual(original, points([8, 10, 11]))
    XCTAssertEqual(smoothed.map(\.elapsed), original.map(\.elapsed))
    XCTAssertEqual(smoothed.map(\.id), original.map(\.id))
    XCTAssertEqual(smoothed.map(\.wpm), original.map(\.wpm))
    XCTAssertEqual(smoothed.map(\.rawWpm), original.map(\.rawWpm))
    XCTAssertEqual(smoothed.map(\.errorCount), original.map(\.errorCount))
  }

  func testEmptySingleFlatAndZeroSeriesHaveNoPhantomNeighbors() {
    for original in [points([]), points([7]), points([0]), points([7, 7, 7]), points([0, 0, 0])] {
      XCTAssertEqual(ResultBurstSmoothingPolicy.points(original, enabled: true), original)
    }
  }

  func testRawToggleAndLegacyVisibilityRoundTripDoNotRewritePoints() throws {
    let original = points([10, 11, 13])
    XCTAssertEqual(ResultBurstSmoothingPolicy.points(original, enabled: false), original)
    _ = ResultBurstSmoothingPolicy.points(original, enabled: true)
    XCTAssertEqual(ResultBurstSmoothingPolicy.points(original, enabled: false), original)
    let legacy = try JSONDecoder().decode(ResultPerformanceVisibility.self, from: Data(
      #"{"raw":true,"burst":true,"errors":true}"#.utf8))
    XCTAssertTrue(legacy.smoothBurst)
    var raw = legacy
    raw.smoothBurst = false
    XCTAssertEqual(try JSONDecoder().decode(ResultPerformanceVisibility.self,
      from: JSONEncoder().encode(raw)), raw)
  }

  func testInspectionUsesTheSmoothedFractionWithoutChangingTouchedWords() throws {
    let smoothed = ResultBurstSmoothingPolicy.points(points([10, 11, 13]), enabled: true)
    let inspection = try XCTUnwrap(ResultPerformanceInspectionPolicy.inspection(
      nearestTo: 2, points: smoothed,
      reviews: [.init(index: 0, target: "a", typed: "a"), .init(index: 1, target: "bc", typed: "bc")],
      events: [
        .init(offset: 0, kind: .insert, text: "a"),
        .init(offset: 1, kind: .insert, text: " "),
        .init(offset: 1.5, kind: .insert, text: "b"),
        .init(offset: 2, kind: .insert, text: "c"),
      ]))
    XCTAssertEqual(Double(inspection.point.burstWpm), 34.0 / 3, accuracy: 0.000_000_001)
    XCTAssertEqual(inspection.wordIndexes, [1])
    XCTAssertEqual(TypingSpeedUnit.wpm.formatted(
      wpm: Double(inspection.point.burstWpm), alwaysShowDecimalPlaces: true), "11.33")
    XCTAssertEqual(TypingSpeedUnit.cpm.formatted(
      wpm: Double(inspection.point.burstWpm), alwaysShowDecimalPlaces: true), "56.67")
    XCTAssertEqual(TypingSpeedUnit.wps.formatted(
      wpm: Double(inspection.point.burstWpm), alwaysShowDecimalPlaces: true), "0.19")
    XCTAssertEqual(TypingSpeedUnit.cps.formatted(
      wpm: Double(inspection.point.burstWpm), alwaysShowDecimalPlaces: true), "0.94")
    XCTAssertEqual(TypingSpeedUnit.wph.formatted(
      wpm: Double(inspection.point.burstWpm), alwaysShowDecimalPlaces: true), "680.00")
  }

  func testGraphAndInspectionConvertBeforeRoundingToTwoDecimals() {
    let canonical = 34.0 / 3
    for (unit, expected, text) in [
      (TypingSpeedUnit.wpm, 11.33, "11.33"),
      (.cpm, 56.67, "56.67"),
      (.wps, 0.19, "0.19"),
      (.cps, 0.94, "0.94"),
      (.wph, 680, "680.00"),
    ] {
      XCTAssertEqual(ResultBurstDisplayPolicy.value(wpm: canonical, unit: unit), expected)
      XCTAssertEqual(ResultBurstDisplayPolicy.text(wpm: canonical, unit: unit), text)
    }
    XCTAssertEqual(ResultBurstDisplayPolicy.value(wpm: 1.005, unit: .wpm), 1.01)
    XCTAssertEqual(ResultBurstDisplayPolicy.text(wpm: 1.005, unit: .wpm), "1.01")
    XCTAssertEqual(ResultBurstDisplayPolicy.value(wpm: 0, unit: .wps), 0)
  }

  func testFractionalTailIsOneNeighborPositionAndIsNotDurationWeighted() {
    let original: [ResultPerformancePoint] = [
      .init(elapsed: 1, wpm: 30, rawWpm: 35, burstWpm: 60, errorCount: 0),
      .init(elapsed: 1.5, wpm: 31, rawWpm: 36, burstWpm: 72, errorCount: 1),
    ]
    assertBursts(ResultBurstSmoothingPolicy.points(original, enabled: true), [66, 66])
  }

  func testCompletedFiniteReplayRetainsFractionsThroughPresentation() throws {
    let start = Date(timeIntervalSince1970: 100)
    var session = TypingSession(configuration: .words(1), prompt: "ab")
    session.insert("a", at: start)
    session.insert("b", at: start.addingTimeInterval(1.8))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .completed)
    let trace = ResultPerformanceTrace.points(
      prompt: result.prompt, events: result.replayEvents,
      duration: result.elapsedDuration, configuration: result.configuration)
    assertBursts(trace, [12, 15])
    let smoothed = ResultBurstSmoothingPolicy.points(trace, enabled: true)
    assertBursts(smoothed, [13.5, 13.5])
    XCTAssertEqual(ResultBurstDisplayPolicy.text(wpm: smoothed[1].burstWpm, unit: .wps), "0.23")
    XCTAssertEqual(ResultBurstDisplayPolicy.text(wpm: smoothed[1].burstWpm, unit: .cps), "1.13")
    XCTAssertEqual(result.wpm, 13)
    XCTAssertEqual(result.rawWpm, 13)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
      through: result.elapsedDuration), "ab")
  }
}
