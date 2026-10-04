import Foundation
import XCTest
@testable import Typebar

final class AccountPracticeResponseTests: XCTestCase {
  func testSourceSparseActivityAcceptsNullDaysWithoutInventingTests() throws {
    let bytes = Data(#"{"lastDay":1000,"testsByDays":[null,1,null,2]}"#.utf8)
    let activity = try JSONDecoder().decode(RemotePublicProfileActivity.self, from: bytes)
    XCTAssertEqual(activity.testsByDays, [nil, 1, nil, 2])
    XCTAssertEqual(activity.dayBoundaryOffsetHours, 0)
    let encoded = try JSONEncoder().encode(activity)
    let again = try JSONDecoder().decode(RemotePublicProfileActivity.self, from: encoded)
    XCTAssertEqual(again.testsByDays, activity.testsByDays)
  }
  func testMalformedActivityCountsAndBoundariesCannotDecode() throws {
    for fragment in [#""testsByDays":[-1]"#, #""testsByDays":[9007199254740992]"#,
      #""testsByDays":[1],"dayBoundaryOffsetHours":0.25"#,
      #""testsByDays":[1],"dayBoundaryOffsetHours":13"#] {
      let bytes = Data((#"{"lastDay":1000,"# + fragment + "}").utf8)
      XCTAssertThrowsError(try JSONDecoder().decode(RemotePublicProfileActivity.self, from: bytes))
    }
  }
  func testLegacyProfileDoesNotInventHistoryCompleteness() throws {
    let json = #"{"id":"A0EAB332-6711-4169-8578-FEA8E91B2EB1","displayName":"Owned","joinedAt":0,"completedResultCount":1,"bestWPM":60}"#
    let profile = try JSONDecoder().decode(RemotePublicProfile.self, from: Data(json.utf8))
    XCTAssertNil(profile.practiceHistoryComplete)
  }
  func testIncompleteProfileFlagIsPreservedAlongsideHiddenCalendarAndVisibleStreak() throws {
    let json = #"{"id":"A0EAB332-6711-4169-8578-FEA8E91B2EB1","displayName":"Owned","joinedAt":0,"completedResultCount":1,"bestWPM":60,"practiceHistoryComplete":false,"streak":{"currentDays":2,"longestDays":3}}"#
    let profile = try JSONDecoder().decode(RemotePublicProfile.self, from: Data(json.utf8))
    XCTAssertEqual(profile.practiceHistoryComplete, false)
    XCTAssertNil(profile.activity)
    XCTAssertEqual(profile.streak, .init(currentDays: 2, longestDays: 3))
  }
}
