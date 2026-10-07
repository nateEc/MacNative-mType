import Foundation
import XCTest
@testable import Typebar

final class AccountDailyActivityTests: XCTestCase {
  private func row(speed: Double = 80.49, at date: Date, duration: Double? = 15,
    restarts: Int = 0, prior: Int? = 0) throws -> RemoteAccountResult {
    let time = date.timeIntervalSinceReferenceDate, wall = duration ?? 15
    var object: [String: Any] = ["id": UUID().uuidString, "mode": "time", "mode2": String(Int(wall)), "durationSeconds": Int(wall),
      "language": "english", "wpm": Int(speed.rounded()), "rawWpm": speed <= 420 ? 420 : 500,
      "accuracy": 98, "preciseAccuracy": 98.31, "consistency": 80.11,
      "errorCount": 1, "eventCount": 75, "tags": [], "restartCount": restarts,
      "startedAt": time-wall, "finishedAt": time, "startedAtReferenceTime": time-wall, "finishedAtReferenceTime": time]
    if speed <= 420 { object["speedPrecision"] = ["version": 1, "wpm": speed, "rawWpm": 420] }
    if let duration { object["elapsedTime"] = ["version": 1, "seconds": duration] }
    if let prior { object["practiceTiming"] = ["version": 1, "terminalEngagedMilliseconds": 14000,
      "priorAttemptEngagedMilliseconds": prior] }
    return try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: object))
  }

  private func model(_ rows: [RemoteAccountResult], unit: TypingSpeedUnit = .wpm,
    zero: Bool = false, calendar: Calendar = Calendar(identifier: .gregorian)) -> AccountDailyActivity {
    .init(days: AccountHistoryQuery.days(rows, calendar: calendar), unit: unit, startsAtZero: zero)
  }

  func testTrendClipsAtItsZeroIntersectionInsteadOfChangingSlopeAtLastDay() throws {
    let first = Date(timeIntervalSince1970: 1_000_000)
    let observations = [10.0, 0.25, 0.25].enumerated().map {
      ActivityBarPoint(day: first.addingTimeInterval(Double($0.offset) * 86400),
        completedTests: 1, typingSeconds: $0.element * 60)
    }
    let points = ActivityTypingMinutesTrendPolicy.points(for: observations)
    XCTAssertEqual(try XCTUnwrap(points.first).minutes, 8.375, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(points.last).minutes, 0, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(points.last).day.timeIntervalSince(first) / 86400, 8.375 / 4.875, accuracy: 1e-9)
  }

  func testFitRemainsSignedAndClippingIntersectsBothRangeBoundaries() throws {
    let first = Date(timeIntervalSince1970: 1_000_000), last = first.addingTimeInterval(86400)
    let line: [ActivityTypingMinutesTrendPoint] = [.init(day: first, minutes: -5), .init(day: last, minutes: 15)]
    let clipped = ActivityTypingMinutesTrendPolicy.clipped(line, upper: 10)
    XCTAssertEqual(clipped.map(\.minutes), [0,10])
    XCTAssertEqual(clipped.map { $0.day.timeIntervalSince(first) }, [21600,64800])
    let descending = ActivityTypingMinutesTrendPolicy.clipped([.init(day: first, minutes: 15), .init(day: last, minutes: -5)], upper: 10)
    XCTAssertEqual(descending.map(\.minutes), [10,0])
    XCTAssertEqual(descending.map { $0.day.timeIntervalSince(first) }, [21600,64800])
    let observations = [10.0,0.25,0.25].enumerated().map {
      ActivityBarPoint(day: first.addingTimeInterval(Double($0.offset)*86400), completedTests: 1, typingSeconds: $0.element*60)
    }
    XCTAssertEqual(try XCTUnwrap(ActivityTypingMinutesTrendPolicy.fitted(for: observations).last).minutes, -1.375, accuracy: 1e-9)
  }

  func testFlatOutsideDegenerateAndInvalidFitsNeverProduceInventedTrend() {
    let first = Date(timeIntervalSince1970: 1_000_000), last = first.addingTimeInterval(86400)
    for value in [-1.0,11,.infinity,.nan] {
      XCTAssertTrue(ActivityTypingMinutesTrendPolicy.clipped([.init(day: first, minutes: value), .init(day: last, minutes: value)], upper: 10).isEmpty)
    }
    XCTAssertEqual(ActivityTypingMinutesTrendPolicy.clipped([.init(day: first, minutes: 0), .init(day: last, minutes: 0)], upper: 10).count,2)
    for points in [[],[ActivityBarPoint(day: first, completedTests: 1, typingSeconds: 60)],
      [.init(day: first, completedTests: 1, typingSeconds: 60), .init(day: first, completedTests: 1, typingSeconds: 120)],
      [.init(day: first, completedTests: 1, typingSeconds: .infinity), .init(day: last, completedTests: 1, typingSeconds: 120)]] {
      XCTAssertTrue(ActivityTypingMinutesTrendPolicy.points(for: points).isEmpty)
    }
  }

  func testUnknownMinutesRemainUnknownButKnownSpeedStillHasIndependentAxis() throws {
    let first = Date(timeIntervalSince1970: 1_000_000)
    let activity = model(try [row(at: first), row(speed: 100.25, at: first.addingTimeInterval(86400), prior: nil)])
    XCTAssertEqual(activity.days.count,2); XCTAssertEqual(activity.unknownMinuteDays,1)
    XCTAssertNil(activity.days[1].statistics.timeTyping)
    XCTAssertEqual(activity.speeds.map(\.wpm),[80.49,100.25]); XCTAssertTrue(activity.trend.isEmpty)
    XCTAssertGreaterThanOrEqual(activity.scale.speedUpper,100.25)
    let speedOnly = model(try [row(at: first, prior: nil)])
    XCTAssertEqual(speedOnly.scale.minutesUpper,1); XCTAssertEqual(speedOnly.speeds.count,1)
    XCTAssertTrue(speedOnly.trend.isEmpty)
  }

  func testUnknownSpeedSplitsLineWithoutHidingKnownMinutes() throws {
    let first = Date(timeIntervalSince1970: 1_000_000)
    let activity = model(try [row(at: first), row(speed: 500, at: first.addingTimeInterval(86400)),
      row(at: first.addingTimeInterval(172800))])
    XCTAssertEqual(activity.days.count,3); XCTAssertEqual(activity.unknownMinuteDays,0)
    XCTAssertNil(activity.days[1].statistics.averageWpm)
    XCTAssertEqual(activity.speeds.map(\.segment),[0,1]); XCTAssertEqual(activity.trend.count,2)
  }

  func testFiveUnitsAndZeroPreferenceDoNotChangeMinutesOrCanonicalFit() throws {
    let first = Date(timeIntervalSince1970: 1_000_000)
    let rows = try [row(at: first),row(speed: 100.25, at: first.addingTimeInterval(86400), duration: 30)]
    let baseline = model(rows)
    for unit in TypingSpeedUnit.allCases {
      for zero in [false,true] {
        let activity = model(rows,unit:unit,zero:zero)
        XCTAssertEqual(activity.trend.map(\.minutes),baseline.trend.map(\.minutes))
        XCTAssertEqual(activity.scale.minutesUpper,baseline.scale.minutesUpper)
        XCTAssertEqual(activity.scale.speed(at: activity.scale.ordinate(wpm:80.49)),unit.converted(wpm:80.49),accuracy:1e-9)
        XCTAssertEqual(activity.scale.ticks.first,0); XCTAssertEqual(activity.scale.ticks.last,activity.scale.minutesUpper)
        XCTAssertGreaterThan(activity.scale.speedUpper,activity.scale.speedLower)
        if zero { XCTAssertEqual(activity.scale.speedLower,0) }
        else { XCTAssertGreaterThan(activity.scale.speedLower,0) }
      }
    }
  }

  func testAllLoadedDaysAreChronologicalAndSelectionTiesPreferEarlierDay() throws {
    let first = Date(timeIntervalSince1970: 1_000_000)
    let rows = try (0..<27).reversed().map { try row(at:first.addingTimeInterval(Double($0)*86400)) }
    let activity = model(rows)
    XCTAssertEqual(activity.days.count,27); XCTAssertEqual(activity.speeds.count,27)
    XCTAssertEqual(activity.nearest(to:activity.days[0].day.addingTimeInterval(43200))?.day,activity.days[0].day)
    XCTAssertEqual(activity.nearest(to:Date.distantFuture)?.day,activity.days.last?.day)
    XCTAssertEqual(activity.nearest(to:Date.distantPast)?.day,activity.days.first?.day)
    XCTAssertNil(activity.nearest(to:Date(timeIntervalSinceReferenceDate:.nan)))
    XCTAssertNil(model([]).nearest(to:first)); XCTAssertTrue(model([]).trend.isEmpty)
  }

  func testUnknownOnlyDatesKeepSelectableNondegenerateViewportWithoutSyntheticRows() throws {
    let first = Date(timeIntervalSince1970:1_000_000)
    let single = model(try [row(speed:500,at:first,prior:nil)])
    XCTAssertEqual(single.days.count,1); XCTAssertTrue(single.speeds.isEmpty); XCTAssertTrue(single.trend.isEmpty)
    XCTAssertTrue(single.dateDomain.contains(single.days[0].day))
    XCTAssertGreaterThan(single.dateDomain.upperBound,single.dateDomain.lowerBound)
    let sparse = model(try [row(speed:500,at:first,prior:nil),row(speed:500,at:first.addingTimeInterval(864000),prior:nil)])
    XCTAssertEqual(sparse.days.count,2); XCTAssertEqual(sparse.unknownMinuteDays,2)
    XCTAssertEqual(sparse.dateDomain.lowerBound,sparse.days[0].day)
    XCTAssertEqual(sparse.dateDomain.upperBound,sparse.days[1].day)
    XCTAssertEqual(sparse.nearest(to:sparse.dateDomain.upperBound)?.day,sparse.days[1].day)
    XCTAssertGreaterThan(model([]).dateDomain.upperBound,model([]).dateDomain.lowerBound)
  }

  func testDayGroupingPreservesDSTSpacingAndDoesNotSynthesizeGaps() throws {
    var calendar = Calendar(identifier:.gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier:"America/Los_Angeles"))
    let parser = ISO8601DateFormatter()
    for (dates,hours) in [(["2026-03-08T09:00:00Z","2026-03-09T09:00:00Z"],23.0),
      (["2026-11-01T09:00:00Z","2026-11-02T09:00:00Z"],25.0)] {
      let rows = try dates.map { try row(at:XCTUnwrap(parser.date(from:$0))) }
      let activity = model(rows,calendar:calendar)
      XCTAssertEqual(activity.days.count,2)
      XCTAssertEqual(activity.days[1].day.timeIntervalSince(activity.days[0].day),hours*3600)
    }
    let sparse = model(try [row(at:Date(timeIntervalSince1970:1_000_000)),row(at:Date(timeIntervalSince1970:1_000_000+864000))])
    XCTAssertEqual(sparse.days.count,2); XCTAssertEqual(sparse.speeds.count,2)
  }

  func testSameDayAggregatesPrecisionAndExplicitPriorWithoutSubtractingEngagedTime() throws {
    let date = Date(timeIntervalSince1970:1_000_000)
    let activity = model(try [row(at:date,restarts:2,prior:2345),row(speed:60.41,at:date)])
    let stats = try XCTUnwrap(activity.days.first).statistics
    XCTAssertEqual(stats.completed,2); XCTAssertEqual(stats.timeTyping,32.345)
    XCTAssertEqual(try XCTUnwrap(stats.averageWpm),70.45,accuracy:1e-9); XCTAssertEqual(stats.maximumWpm,80.49)
    XCTAssertEqual(stats.restartsPerCompleted,1); XCTAssertEqual(stats.averageAccuracy,98.31)
    XCTAssertTrue(activity.trend.isEmpty)
  }

  func testPinnedPluginFitAndCompleteClippingUsingOwnedAffineScaleAdapters() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_REFERENCE_ROOT"], let archive = environment["TYPEBAR_DAILY_TREND_SOURCE_ARCHIVE"] else {
      throw XCTSkip("Requires pinned reference and verified QA-only trendline archive")
    }
    struct Fixture: Decodable { let dates:[Double]; let minutes:[Double?]; let upper:Double; let raw:[[Double]]; let clipped:[[Double]] }
    let project = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
    process.arguments = ["node",project.appendingPathComponent("Scripts/check-source-account-daily-activity.mjs").path,reference,archive,"--emit-fixtures"]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus,0)
    let fixtures = try JSONDecoder().decode([Fixture].self,from:data)
    XCTAssertEqual(fixtures.count,15)
    for fixture in fixtures {
      let points = zip(fixture.dates,fixture.minutes).compactMap { date,minutes -> ActivityBarPoint? in
        minutes.map { .init(day:Date(timeIntervalSince1970:date/1000),completedTests:1,typingSeconds:$0*60) }
      }
      let raw = ActivityTypingMinutesTrendPolicy.fitted(for:points)
      let clipped = ActivityTypingMinutesTrendPolicy.clipped(raw,upper:fixture.upper)
      for (actual,expected) in [(raw,fixture.raw),(clipped,fixture.clipped)] {
        XCTAssertEqual(actual.count,expected.count)
        for (point,source) in zip(actual,expected) {
          // The pinned plugin uses uncentered Unix-ms normal equations. Native
          // centering avoids cancellation; these bounds remain far below a day.
          XCTAssertEqual(point.day.timeIntervalSince1970,source[0]/1000,accuracy:0.5)
          XCTAssertEqual(point.minutes,source[1],accuracy:0.00002)
        }
      }
    }
  }
}
