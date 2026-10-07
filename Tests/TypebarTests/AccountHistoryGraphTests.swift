import Foundation
import XCTest
@testable import Typebar

final class AccountHistoryGraphTests: XCTestCase {
  private func row(_ speed: Double, time: Double, accuracy: Double = 98.31, duration: Double? = 60) throws -> RemoteAccountResult {
    var object: [String: Any] = ["id": UUID().uuidString, "mode": "time", "mode2": "60", "durationSeconds": 60, "language": "english",
      "wpm": Int(speed.rounded()), "rawWpm": 420, "accuracy": 98, "preciseAccuracy": accuracy,
      "consistency": 80.11, "errorCount": 1, "eventCount": 75, "tags": [],
      "startedAt": time - 60, "finishedAt": time,
      "startedAtReferenceTime": time - 60, "finishedAtReferenceTime": time,
      "restartCount": 0, "practiceTiming": ["version": 1, "terminalEngagedMilliseconds": 60000,
        "priorAttemptEngagedMilliseconds": 0]]
    if speed <= 420 { object["speedPrecision"] = ["version": 1, "wpm": speed, "rawWpm": 420] }
    if let duration { object["elapsedTime"] = ["version": 1, "seconds": duration] }
    if duration == 0 {
      object["mode"] = "zen"; object["mode2"] = "zen"; object.removeValue(forKey: "durationSeconds")
      object["startedAt"] = time; object["startedAtReferenceTime"] = time
      object["practiceTiming"] = ["version": 1, "terminalEngagedMilliseconds": 0, "priorAttemptEngagedMilliseconds": 0]
    }
    return try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: object))
  }

  func testReferenceAllowsBothPrimaryTracesOffWithoutChangingAveragePreferences() {
    let visibility = HistoryChartVisibility(speed: false, accuracy: true, average10: false, average100: true)
    XCTAssertEqual(visibility.applying { $0.accuracy = false },
      .init(speed: false, accuracy: false, average10: false, average100: true))
  }

  func testWholeMatchedCacheUsesChronologyAndPartialOldTailForBothAverages() throws {
    let rows = try (0..<125).map { try row(Double($0) + 20.25, time: Double($0) + 1000, accuracy: 80 + Double($0 % 20)) }
    let graph = AccountHistoryGraphs(AccountHistoryQuery.sorted(rows, by: .wpm, direction: .ascending))
    XCTAssertEqual(graph.points.map(\.id), rows.reversed().map(\.id))
    XCTAssertEqual(graph.points.first?.position, 124); XCTAssertEqual(graph.points.last?.position, 0)
    XCTAssertEqual(graph.points.first?.speed10, 139.75)
    XCTAssertEqual(graph.points.first?.speed100, 94.75)
    XCTAssertEqual(graph.points.last?.speed10, 20.25)
    XCTAssertEqual(graph.points.last?.accuracy100, 80)
    XCTAssertEqual(graph.points[123].accuracy10, 80.5)
    XCTAssertEqual(graph.points.first?.envelope, 144.25)
  }

  func testEnvelopeIsFilteredRunningMaximumNotCurrentOrHistoricalPBFlag() throws {
    let graph = AccountHistoryGraphs(try [row(95, time: 300), row(110, time: 200), row(90, time: 100)])
    XCTAssertEqual(graph.points.map(\.envelope), [110,110,90])
    XCTAssertTrue(graph.points.allSatisfy { $0.row.historicalPersonalBest == nil })
    XCTAssertEqual(AccountHistoryGraphs([graph.points[0].row, graph.points[2].row]).points.map(\.envelope), [95,90])
  }

  func testUnknownMetricInvalidatesItsWindowsEnvelopeAndTrendWithoutInventingZero() throws {
    let graph = AccountHistoryGraphs(try [row(120, time: 300), row(500, time: 200), row(80, time: 100)])
    XCTAssertEqual(graph.points.map(\.speed), [120,nil,80])
    XCTAssertEqual(graph.points.map(\.speed10), [nil,nil,80])
    XCTAssertEqual(graph.points.map(\.envelope), [nil,nil,80])
    XCTAssertTrue(graph.points.allSatisfy { $0.accuracy10 != nil })
    XCTAssertNil(graph.speedChangePerTypingHour)
    XCTAssertEqual(AccountHistoryHistogram(points: graph.points, unit: .wpm).unknownCount, 1)
    XCTAssertEqual(AccountHistoryGraphs.averages([1,nil,3,4], window: 2), [nil,nil,3.5,4])
    XCTAssertEqual(graph.line(\.speed).map(\.segment), [0,1], "Unknown observations must split the drawn line")
  }

  func testTrendUsesFractionalCanonicalSpeedsAndTypingEvidenceNotCalendarSpacing() throws {
    let graph = AccountHistoryGraphs(try [row(120.25, time: 9999999), row(100.25, time: 100)])
    XCTAssertEqual(graph.speedChangePerTypingHour, 600)
    XCTAssertNil(AccountHistoryGraphs(try [row(120, time: 300, duration: nil), row(100, time: 100)]).speedChangePerTypingHour)
    XCTAssertThrowsError(try row(120, time: 300, duration: 0), "The service decoder rejects zero-duration completed rows before graphing")
    XCTAssertNil(AccountHistoryGraphs(try [row(120, time: 100)]).speedChangePerTypingHour)
    XCTAssertNil(AccountHistoryGraphs([]).speedChangePerTypingHour)
    XCTAssertEqual(AccountHistoryGraphs.fittedChange([10,30,20]), 10)
  }

  func testSelectionUsesStableIDInIndependentlySortedTableAndNeverShrinksLoadedPage() throws {
    let rows = try (0..<27).map { try row(Double(100 - $0), time: Double($0) + 1000) }
    let graph = AccountHistoryGraphs(rows), table = AccountHistoryQuery.sorted(rows, by: .wpm)
    XCTAssertEqual(graph.nearest(to: 10.5)?.id, rows[11].id)
    XCTAssertEqual(graph.nearest(to: -99)?.id, rows[0].id)
    XCTAssertEqual(graph.nearest(to: 999)?.id, rows[26].id)
    XCTAssertNil(graph.nearest(to: .nan)); XCTAssertNil(AccountHistoryGraphs([]).nearest(to: 0))
    XCTAssertEqual(AccountHistoryGraphs.visibleLimit(for: rows[10].id, in: table, current: 10), 20)
    XCTAssertEqual(AccountHistoryGraphs.visibleLimit(for: rows[26].id, in: table, current: 10), 27)
    XCTAssertEqual(AccountHistoryGraphs.visibleLimit(for: rows[0].id, in: table, current: 20), 20)
    XCTAssertNil(AccountHistoryGraphs.visibleLimit(for: UUID(), in: table, current: 10))
  }

  func testHistogramPreservesSourceRoundedAssignmentUnroundedExtentAndFractionalLabels() throws {
    let graph = AccountHistoryGraphs(try [row(9.9, time: 100)])
    let histogram = AccountHistoryHistogram(points: graph.points, unit: .wpm)
    XCTAssertEqual(histogram.buckets.map(\.label), ["0-9"])
    XCTAssertEqual(histogram.buckets.map(\.count), [0])
    XCTAssertEqual(histogram.omittedByReferenceRounding, 1)
    let fractional = AccountHistoryHistogram(points: AccountHistoryGraphs(try [row(60, time: 100)]).points, unit: .wps)
    XCTAssertEqual(fractional.buckets.map(\.label), ["0--0.5","0.5-0","1-0.5"])
    XCTAssertEqual(fractional.buckets.map(\.count), [0,0,1])
    XCTAssertTrue(AccountHistoryHistogram(points: [], unit: .wpm).buckets.isEmpty)
  }

  func testDualAxesReverseAccuracyAndUseSelectedUnitAndZeroPreference() throws {
    let points = AccountHistoryGraphs(try [row(80, time: 100, accuracy: 98), row(100, time: 200, accuracy: 96)]).points
    let zero = AccountHistoryGraphScale(points: points, unit: .cpm, startsAtZero: true, speedVisible: true)
    XCTAssertEqual(zero.speedLower, 0); XCTAssertEqual(zero.speedUpper, 500)
    XCTAssertEqual(zero.speedPosition(100), 100)
    XCTAssertEqual(zero.accuracyPosition(100), 0); XCTAssertEqual(zero.accuracyPosition(0), 100)
    let zoom = AccountHistoryGraphScale(points: points, unit: .cpm, startsAtZero: false, speedVisible: false)
    XCTAssertEqual(zoom.speedLower, 400); XCTAssertEqual(zoom.accuracyLower, 95)
    XCTAssertEqual(zoom.accuracyPosition(96), 80)
    XCTAssertEqual(zoom.speed(at: 50), 450); XCTAssertEqual(zoom.accuracy(at: 50), 97.5)
    for unit in TypingSpeedUnit.allCases {
      let scale = AccountHistoryGraphScale(points: points, unit: unit, startsAtZero: false, speedVisible: true)
      XCTAssertEqual(scale.speed(at: scale.speedPosition(80)), unit.converted(wpm: 80), accuracy: 1e-9)
    }
  }

  func testNumberPreferencesKeepUnknownDistinctAndTooltipForcesTwoDecimals() {
    XCTAssertEqual(AccountHistoryNumberPresentation.text(80.49, unit: .cpm, decimals: false), "402")
    XCTAssertEqual(AccountHistoryNumberPresentation.text(80.49, unit: .cpm, decimals: true), "402.45")
    XCTAssertEqual(AccountHistoryNumberPresentation.text(98.31, decimals: false, forceDecimals: true), "98.31")
    XCTAssertEqual(AccountHistoryNumberPresentation.text(nil, decimals: false), "未知")
    XCTAssertEqual(AccountHistoryNumberPresentation.text(.infinity, decimals: true), "未知")
    XCTAssertEqual(AccountHistoryNumberPresentation.text(80.5, decimals: false), "81")
    XCTAssertEqual(AccountHistoryNumberPresentation.text(0.49999999999999994, decimals: false), "0")
    XCTAssertEqual(AccountHistoryNumberPresentation.text(-0.5000000000000001, decimals: false), "-1")
    XCTAssertEqual(AccountHistoryNumberPresentation.text(-0.0, decimals: false), "0")
    XCTAssertEqual(AccountHistoryNumberPresentation.text(1.005, decimals: true), "1.01")
    XCTAssertEqual(AccountHistoryNumberPresentation.text(10.125, decimals: true), "10.13")
    XCTAssertEqual(AccountHistoryNumberPresentation.restartRatio(1.5), "1.5")
    XCTAssertEqual(AccountHistoryNumberPresentation.restartRatio(1.25), "1.3")
    XCTAssertEqual(AccountHistoryNumberPresentation.restartRatio(1.15), "1.1")
    XCTAssertEqual(AccountHistoryNumberPresentation.restartRatio(1.35), "1.4")
    XCTAssertEqual(AccountHistoryNumberPresentation.restartRatio(0), "0.0")
    XCTAssertEqual(AccountHistoryNumberPresentation.restartRatio(nil), "未知")
  }

  @MainActor func testExistingSettingsPersistAllOffUnitsZeroAndDecimalsWithoutNewSchema() throws {
    let suite = "TypebarTests.account-graph.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.mutateHistoryChartVisibility { $0.speed = false; $0.accuracy = false; $0.average10 = false }
    settings.typingSpeedUnit = .wps; settings.startGraphsAtZero = false; settings.alwaysShowDecimalPlaces = true
    let restored = AppSettings(defaults: defaults)
    XCTAssertEqual(restored.historyChartVisibility, .init(speed: false, accuracy: false, average10: false, average100: true))
    XCTAssertEqual(restored.typingSpeedUnit, .wps); XCTAssertFalse(restored.startGraphsAtZero)
    XCTAssertTrue(restored.alwaysShowDecimalPlaces)
  }

  func testPinnedCompleteSourceFunctionsMatchNativeSequencesAndFiveUnits() throws {
    guard let root = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Set TYPEBAR_REFERENCE_ROOT for pinned numeric source comparisons")
    }
    struct Fixture: Decodable {
      struct Bucket: Decodable { let x: String; let y: Int }
      struct Format: Decodable { let value: Double; let decimals: Bool; let text: String }
      struct Ratio: Decodable { let value: Double; let text: String }
      let unit: TypingSpeedUnit
      let speeds: [Double], accuracies: [Double]
      let speed10: [Double], speed100: [Double], accuracy10: [Double], accuracy100: [Double], envelope: [Double]
      let trend: Double?
      let buckets: [Bucket]
      let formats: [Format]
      let ratios: [Ratio]
    }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-account-history-graphs.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", script.path, root, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let error = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: error, as: UTF8.self))
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 60)
    XCTAssertEqual(fixtures.flatMap(\.formats).count, 120)
    XCTAssertEqual(fixtures.flatMap(\.ratios).count, 10)
    for fixture in fixtures {
      for ratio in fixture.ratios { XCTAssertEqual(AccountHistoryNumberPresentation.restartRatio(ratio.value), ratio.text) }
      for format in fixture.formats {
        XCTAssertEqual(AccountHistoryNumberPresentation.text(format.value, unit: fixture.unit, decimals: format.decimals),
          format.text, "\(fixture.unit) \(format.value) \(format.decimals)")
      }
      let rows = try fixture.speeds.enumerated().map { index, speed in
        try row(speed, time: Double(fixture.speeds.count - index) + 1000, accuracy: fixture.accuracies[index])
      }
      let graph = AccountHistoryGraphs(rows)
      for (key, expected) in [(\AccountHistoryGraphPoint.speed10, fixture.speed10),
        (\.speed100, fixture.speed100), (\.accuracy10, fixture.accuracy10),
        (\.accuracy100, fixture.accuracy100), (\.envelope, fixture.envelope)] {
        XCTAssertEqual(graph.points.count, expected.count)
        for (point, value) in zip(graph.points, expected) {
          XCTAssertEqual(try XCTUnwrap(point[keyPath: key]), value, accuracy: 1e-8, "\(fixture.unit), \(key)")
        }
      }
      if let trend = fixture.trend { XCTAssertEqual(try XCTUnwrap(graph.speedChangePerTypingHour), trend, accuracy: 1e-8) }
      else { XCTAssertNil(graph.speedChangePerTypingHour) }
      let histogram = AccountHistoryHistogram(points: graph.points, unit: fixture.unit)
      XCTAssertEqual(histogram.buckets.map(\.label), fixture.buckets.map(\.x), fixture.unit.rawValue)
      XCTAssertEqual(histogram.buckets.map(\.count), fixture.buckets.map(\.y), fixture.unit.rawValue)
    }
  }
}
