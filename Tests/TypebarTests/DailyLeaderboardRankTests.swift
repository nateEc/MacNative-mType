import Foundation
import XCTest
@testable import Typebar

final class DailyLeaderboardRankTests: XCTestCase {
  private func entry(friendsRank: Any? = nil) throws -> RemoteLeaderboardEntry {
    let id = UUID().uuidString
    var value: [String:Any] = ["id":id,"userID":id,"rank":7,"displayName":"Owner","mode":"words",
      "language":"english","wpm":60,"accuracy":100,"finishedAt":0]
    if let friendsRank { value["friendsRank"] = friendsRank }
    return try JSONDecoder().decode(RemoteLeaderboardEntry.self,from:JSONSerialization.data(withJSONObject:value))
  }
  func testFriendAndGlobalIdentitiesSurviveResponseRoundTrip() throws {
    let value = try entry(friendsRank:2)
    XCTAssertEqual(value.rank,7)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as? [String:Any])
    XCTAssertEqual(object["friendsRank"] as? Int,2)
  }
  func testFriendPositionDrivesPageStandingAndMemoryWithoutHidingGlobalRank() throws {
    let value = try entry(friendsRank:2)
    XCTAssertEqual(value.rank(in:.friends),2); XCTAssertEqual(value.rank(in:.global),7)
    XCTAssertEqual(value.rankLabel(in:.friends),"好友 #2 · 全局 #7")
    XCTAssertEqual(LeaderboardPaginationPolicy.pageIndex(containingRank:value.rank(in:.friends),total:2,pageSize:1),1)
    XCTAssertEqual(LeaderboardRankStanding(rank:value.rank(in:.friends),total:2),.top(percent:100))
    XCTAssertEqual(LeaderboardRankChange(previousRank:3,currentRank:value.rank(in:.friends)),.improved(1))
  }
  func testOldResponsesKeepLocalRankWithoutFabricatingGlobalIdentity() throws {
    let value = try entry()
    XCTAssertNil(value.friendsRank); XCTAssertEqual(value.rank(in:.friends),7)
    XCTAssertEqual(value.rankLabel(in:.friends),"#7"); XCTAssertNil(try entry(friendsRank:NSNull()).friendsRank)
  }
  func testInvalidFriendPositionDoesNotBecomeALegacyResponse() throws {
    for position: Any in [0,-1,1.5,"2"] { XCTAssertThrowsError(try entry(friendsRank:position)) }
  }
}
