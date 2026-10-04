import Foundation
import XCTest
@testable import TypebarServerCore

final class WeeklyExperienceRewardConfigurationTests: XCTestCase {
  func testConfiguredRewardBracketsSurviveTheActualConfigurationCodec() throws {
    let value = try WeeklyExperienceLeaderboardConfiguration.fromJSON(
      #"{"enabled":true,"expirationTimeInDays":15,"xpRewardBrackets":[{"minRank":1,"maxRank":10,"minReward":50,"maxReward":200}]}"#)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as? [String:Any])
    let brackets = try XCTUnwrap(object["xpRewardBrackets"] as? [[String:Int]])
    XCTAssertEqual(brackets,[["minRank":1,"maxRank":10,"minReward":50,"maxReward":200]])
  }
  func testMalformedExplicitBracketsCannotBeSilentlyIgnored() {
    for brackets in ["null","{}","[{}]","[{\"minRank\":-1,\"maxRank\":10,\"minReward\":50,\"maxReward\":200}]"] {
      XCTAssertThrowsError(try WeeklyExperienceLeaderboardConfiguration.fromJSON(
        "{\"enabled\":true,\"expirationTimeInDays\":15,\"xpRewardBrackets\":\(brackets)}"))
    }
  }
  func testOldMissingRewardConfigurationRemainsEmptyAndDoesNotInventRewards() throws {
    let old = try WeeklyExperienceLeaderboardConfiguration.fromJSON(#"{"enabled":true,"expirationTimeInDays":15}"#)
    XCTAssertTrue(old.xpRewardBrackets.isEmpty)
    XCTAssertEqual(old,.typebarDefault)
    XCTAssertThrowsError(try WeeklyExperienceSettlementPlanner.queryPageSize(configuration:old))
    XCTAssertNil(try WeeklyExperienceSettlementPlanner.queryPageSize(configuration:.init(enabled:false,expirationTimeInDays:15)))
  }
  func testStrictBracketShapeAndSafeDomainPreserveLegitimateReversedRanges() throws {
    let bracket = WeeklyExperienceRewardBracket(minRank:10,maxRank:1,minReward:200,maxReward:50)
    let valid = WeeklyExperienceLeaderboardConfiguration(enabled:true,expirationTimeInDays:15,xpRewardBrackets:[bracket])
    try valid.validate()
    XCTAssertNil(try WeeklyExperienceSettlementPlanner.reward(for:1,brackets:[bracket]))
    for text in [
      #"{"minRank":1,"maxRank":2,"minReward":3,"maxReward":4,"other":1}"#,
      #"{"minRank":1.5,"maxRank":2,"minReward":3,"maxReward":4}"#,
      #"{"minRank":true,"maxRank":2,"minReward":3,"maxReward":4}"#] {
      XCTAssertThrowsError(try JSONDecoder().decode(WeeklyExperienceRewardBracket.self,from:Data(text.utf8)))
    }
    XCTAssertThrowsError(try WeeklyExperienceRewardBracket(minRank:0,maxRank:Int.max,minReward:0,maxReward:1).validate())
  }

  func testActualStoreFreezesNewBracketsAndReadsOldMissingBracketsWithoutBackfill() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-reward-config-\(UUID())")
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
    defer { try? FileManager.default.removeItem(at:directory) }
    let file = directory.appendingPathComponent("store.json"), now = Date(timeIntervalSince1970:1_800_000_000)
    let bracket = WeeklyExperienceRewardBracket(minRank:1,maxRank:10,minReward:50,maxReward:200)
    let first = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development,
      weeklyExperienceConfiguration:.init(enabled:true,expirationTimeInDays:15,xpRewardBrackets:[bracket]))
    let owner = try await first.register(.init(email:"reward-config@example.com",password:"a secure password",displayName:"Config"),now:now)
    let input = ResultSubmissionRequest(id:UUID(),mode:"words",language:"english",durationSeconds:nil,wordLimit:25,
      wpm:60,rawWpm:60,accuracy:100,errorCount:0,eventCount:75,startedAt:now.addingTimeInterval(-15),finishedAt:now)
    let receipt = try await first.submitResult(input,accessToken:owner.accessToken,now:now)
    let bytes = try Data(contentsOf:file)
    let changed = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development,
      weeklyExperienceConfiguration:.init(enabled:true,expirationTimeInDays:15,xpRewardBrackets:[]))
    let retry = try await changed.submitResult(input,accessToken:owner.accessToken,now:now)
    XCTAssertEqual(retry.totalExperience,receipt.totalExperience)
    XCTAssertEqual(try Data(contentsOf:file),bytes,"Retry must not replace frozen configuration")
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any])
    var awards = try XCTUnwrap(object["experienceAwards"] as? [[String:Any]])
    var cachedReceipt = try XCTUnwrap(awards[0]["weeklyCacheReceipt"] as? [String:Any])
    var configuration = try XCTUnwrap(cachedReceipt["configuration"] as? [String:Any])
    let stored = try XCTUnwrap(configuration["xpRewardBrackets"] as? [[String:Int]])
    XCTAssertEqual(stored.first?["maxReward"],200)
    configuration.removeValue(forKey:"xpRewardBrackets")
    cachedReceipt["configuration"] = configuration; awards[0]["weeklyCacheReceipt"] = cachedReceipt
    object["experienceAwards"] = awards
    let oldBytes = try JSONSerialization.data(withJSONObject:object,options:.sortedKeys)
    try oldBytes.write(to:file,options:.atomic)
    let old = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let oldRetry = try await old.submitResult(input,accessToken:owner.accessToken,now:now)
    XCTAssertEqual(oldRetry.totalExperience,receipt.totalExperience)
    XCTAssertEqual(try Data(contentsOf:file),oldBytes,"Old reads never invent historical reward brackets")
  }
}
