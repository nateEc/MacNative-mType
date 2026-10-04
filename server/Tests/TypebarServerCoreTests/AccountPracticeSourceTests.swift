import Foundation
import XCTest
@testable import TypebarServerCore

final class AccountPracticeSourceTests: XCTestCase {
  func testDifferentialAgainstActualPinnedAccountFunctions() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Read-only source comparison requires TYPEBAR_REFERENCE_ROOT; readiness gate sets it")
    }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Scripts/check-source-account-practice.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    let node = ProcessInfo.processInfo.environment["TYPEBAR_PRACTICE_SOURCE_NODE"]
    process.executableURL = URL(fileURLWithPath: node ?? "/usr/bin/env")
    process.arguments = (node == nil ? ["node"] : []) + ["--experimental-vm-modules", script.path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: errorData, as: UTF8.self))
    struct Streak: Decodable { let length: Int; let maxLength: Int; let lastResultTimestamp: Double; let hourOffset: Double? }
    struct StreakFixture: Decodable { let label: String; let prior: Streak; let nowMilliseconds: Double; let streak: Streak }
    struct Activity: Decodable { let testsByDays: [Int?]; let lastDay: Double }
    struct ActivityFixture: Decodable { let label: String; let nowMilliseconds: Double; let activityByYear: [String: [Int?]]; let activity: Activity? }
    struct TypingUpdate: Decodable { let startedTests: Int; let completedTests: Int; let timeTyping: Double }
    struct TypingFixture: Decodable { let restarts: Int; let seconds: Double; let update: TypingUpdate }
    struct Document: Decodable { let referenceCommit: String; let streakFixtures: [StreakFixture]; let activityFixtures: [ActivityFixture]; let typingFixtures: [TypingFixture] }
    let document = try JSONDecoder().decode(Document.self, from: data)
    XCTAssertEqual(document.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(document.streakFixtures.count, 360)
    XCTAssertEqual(document.activityFixtures.count, 126)
    XCTAssertEqual(document.typingFixtures.count, 16)
    for fixture in document.streakFixtures {
      var record = AccountPracticeRecord()
      record.completedTests = fixture.prior.maxLength
      record.startedTests = record.completedTests
      record.activityByYear = ["1970": [record.completedTests]]
      record.streakLength = fixture.prior.length
      record.maximumStreakLength = fixture.prior.maxLength
      record.lastResultMilliseconds = fixture.prior.lastResultTimestamp
      try record.record(restarts: 0, seconds: 0,
        at: Date(timeIntervalSince1970: fixture.nowMilliseconds / 1_000), offsetHours: fixture.prior.hourOffset ?? 0)
      XCTAssertEqual(record.streakLength, fixture.streak.length, fixture.label)
      XCTAssertEqual(record.maximumStreakLength, fixture.streak.maxLength, fixture.label)
      XCTAssertEqual(record.lastResultMilliseconds, fixture.streak.lastResultTimestamp, accuracy: 0.001, fixture.label)
    }
    for fixture in document.activityFixtures {
      var record = AccountPracticeRecord(); record.activityByYear = fixture.activityByYear
      let activity = record.activity(endingAt: Date(timeIntervalSince1970: fixture.nowMilliseconds / 1_000))
      XCTAssertEqual(activity?.testsByDays, fixture.activity?.testsByDays, fixture.label)
      XCTAssertEqual(activity?.lastDay.timeIntervalSince1970, fixture.activity.map { $0.lastDay / 1_000 }, fixture.label)
      if activity != nil { XCTAssertEqual(activity?.dayBoundaryOffsetHours, 0) }
    }
    for fixture in document.typingFixtures {
      var record = AccountPracticeRecord()
      try record.record(restarts: fixture.restarts, seconds: fixture.seconds,
        at: Date(timeIntervalSince1970: 1_800_000_000), offsetHours: 0)
      XCTAssertEqual(record.completedTests, fixture.update.completedTests)
      XCTAssertEqual(record.startedTests, fixture.update.startedTests)
      XCTAssertEqual(record.typingSeconds, fixture.update.timeTyping)
    }
  }
}
