import Foundation
import XCTest
@testable import Typebar

final class LeaderboardMinimumSpeedTests: XCTestCase {
  private func page(_ value: Any? = nil) throws -> RemoteLeaderboardPage {
    var json: [String: Any] = ["entries": []]
    if let value { json["minWpm"] = value }
    return try JSONDecoder().decode(RemoteLeaderboardPage.self,
      from: JSONSerialization.data(withJSONObject: json))
  }
  private func object(_ page: RemoteLeaderboardPage) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(page)) as? [String: Any])
  }
  func testMissingLegacyMinimumIsNotInventedAsZero() throws {
    XCTAssertNil(try object(page())["minWpm"])
  }
  func testExplicitZeroAndFractionalMinimumSurviveWireRoundTrip() throws {
    for speed in [0.0, 49.25, 600.0] {
      XCTAssertEqual(try object(page(speed))["minWpm"] as? Double, speed)
    }
  }
  func testExplicitBadMinimumIsNotSilentlyTreatedAsLegacyAbsence() throws {
    for value: Any in [NSNull(), -1, "40", true] {
      XCTAssertThrowsError(try page(value))
    }
    XCTAssertThrowsError(try JSONDecoder().decode(RemoteLeaderboardPage.self,
      from: Data(#"{"entries":[],"minWpm":1e999}"#.utf8)))
  }
  func testDailyHintUsesConfirmedTailIncludingAnEmptyBoard() throws {
    let value = try page(49.25)
    XCTAssertEqual(LeaderboardMinimumSpeedPresentation.message(minWpm: value.minWpm,
      period: .day, scope: .global, unit: .wpm), "当前榜单榜尾速度 49.25 WPM（入榜参考）")
    XCTAssertEqual(LeaderboardMinimumSpeedPresentation.message(minWpm: 0,
      period: .yesterday, scope: .friends, unit: .wpm), "当前好友榜榜尾速度 0.00 WPM（入榜参考）")
  }
  func testLegacyAndNonDailyResponsesDoNotAcquireADailyHint() {
    for period in RemoteLeaderboardPeriod.allCases {
      XCTAssertNil(LeaderboardMinimumSpeedPresentation.message(minWpm: nil, period: period,
        scope: .global, unit: .wpm))
      if period != .day && period != .yesterday {
        XCTAssertNil(LeaderboardMinimumSpeedPresentation.message(minWpm: 60, period: period,
          scope: .global, unit: .wpm))
      }
    }
    for value in [-1, Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude] {
      XCTAssertNil(LeaderboardMinimumSpeedPresentation.message(minWpm: value,
        period: .day, scope: .global, unit: .wph))
    }
  }
  func testHintRespectsEachExistingSpeedUnitWithoutTruncatingFractionalMetadata() {
    for (unit, expected) in [(TypingSpeedUnit.wpm, "60.50 WPM"), (.cpm, "302.50 CPM"),
      (.wps, "1.01 WPS"), (.cps, "5.04 CPS"), (.wph, "3630.00 WPH")] {
      XCTAssertTrue(LeaderboardMinimumSpeedPresentation.message(minWpm: 60.5, period: .day,
        scope: .friends, unit: unit)?.contains(expected) == true)
    }
  }
}
