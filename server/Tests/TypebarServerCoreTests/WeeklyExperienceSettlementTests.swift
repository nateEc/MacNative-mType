import Foundation
import XCTest
@testable import TypebarServerCore

final class WeeklyExperienceSettlementTests: XCTestCase {
  private func bracket(_ first: Int, _ last: Int, _ minimum: Int, _ maximum: Int) -> WeeklyExperienceRewardBracket {
    .init(minRank:first,maxRank:last,minReward:minimum,maxReward:maximum)
  }
  private func entry(_ id: UUID = UUID(), score: Double = 10, seconds: Double = 15.25) -> WeeklyExperienceCache.Entry {
    .init(userID:id,score:score,displayName:"Reward",timeTypedSeconds:seconds,lastActivityMilliseconds:1_800_000_000_875)
  }
  func testInterpolationSingletonOverlappingAndUnmatchedBrackets() throws {
    let brackets = [bracket(1,3,50,101),bracket(2,2,1,80)]
    XCTAssertEqual(try WeeklyExperienceSettlementPlanner.reward(for:1,brackets:brackets),101)
    XCTAssertEqual(try WeeklyExperienceSettlementPlanner.reward(for:2,brackets:[brackets[0]]),75.5)
    XCTAssertEqual(try WeeklyExperienceSettlementPlanner.reward(for:2,brackets:brackets),80)
    XCTAssertEqual(try WeeklyExperienceSettlementPlanner.reward(for:3,brackets:brackets),50)
    XCTAssertNil(try WeeklyExperienceSettlementPlanner.reward(for:4,brackets:brackets))
    XCTAssertEqual(try WeeklyExperienceSettlementPlanner.reward(for:2,brackets:[bracket(1,3,100,50)]),75)
  }
  func testPreparationUsesCacheGlobalIdentityAndDoesNotCreditAccounts() throws {
    let first = UUID(uuidString:"00000000-0000-0000-0000-00000000000A")!
    let second = UUID(uuidString:"00000000-0000-0000-0000-00000000000B")!
    let entries = [entry(first,score:10.75),entry(second,score:10.75),entry(score:1)]
    let config = WeeklyExperienceLeaderboardConfiguration(enabled:true,expirationTimeInDays:15,
      xpRewardBrackets:[bracket(1,2,75,100)])
    let prepared = try WeeklyExperienceSettlementPlanner.prepare(entries:entries,configuration:config,inboxEnabled:true)
    XCTAssertEqual(prepared.map(\.userID),[second,first]); XCTAssertEqual(prepared.map(\.rank),[1,2])
    XCTAssertEqual(prepared.map(\.rewardExperience),[100,75]); XCTAssertEqual(prepared.map(\.totalExperience),[10,10])
    XCTAssertEqual(prepared.map(\.timeTypedSeconds),[15.25,15.25])
    XCTAssertEqual(entries.map(\.score),[10.75,10.75,1],"The plan never mutates cache or rewards")
  }
  func testZeroRewardProducesARewardMailButUnmatchedRanksDoNot() throws {
    let config = WeeklyExperienceLeaderboardConfiguration(enabled:true,expirationTimeInDays:15,
      xpRewardBrackets:[bracket(2,2,0,0)])
    let prepared = try WeeklyExperienceSettlementPlanner.prepare(entries:[entry(score:20),entry(score:10)],configuration:config,inboxEnabled:true)
    XCTAssertEqual(prepared.map(\.rank),[2]); XCTAssertEqual(prepared.map(\.rewardExperience),[0])
  }
  func testDisabledInboxCannotHideAnEnabledEmptyBracketWorkerError() throws {
    XCTAssertThrowsError(try WeeklyExperienceSettlementPlanner.prepare(entries:[],configuration:.typebarDefault,inboxEnabled:false))
    let config = WeeklyExperienceLeaderboardConfiguration(enabled:true,expirationTimeInDays:15,xpRewardBrackets:[bracket(1,1,100,100)])
    XCTAssertTrue(try WeeklyExperienceSettlementPlanner.prepare(entries:[entry()],configuration:config,inboxEnabled:false).isEmpty)
    XCTAssertTrue(try WeeklyExperienceSettlementPlanner.prepare(entries:[],configuration:config,inboxEnabled:true).isEmpty)
    XCTAssertTrue(try WeeklyExperienceSettlementPlanner.prepare(entries:[entry()],configuration:.init(enabled:false,expirationTimeInDays:0),inboxEnabled:true).isEmpty)
  }
  func testRoundingHappensAfterInterpolationAndRankZeroBracketsDoNotAwardPeople() throws {
    let config = WeeklyExperienceLeaderboardConfiguration(enabled:true,expirationTimeInDays:15,xpRewardBrackets:[bracket(1,3,50,101)])
    let values = try WeeklyExperienceSettlementPlanner.prepare(entries:[entry(score:30),entry(score:20),entry(score:10)],configuration:config,inboxEnabled:true)
    XCTAssertEqual(values.map(\.rewardExperience),[101,76,50])
    let zero = WeeklyExperienceLeaderboardConfiguration(enabled:true,expirationTimeInDays:15,xpRewardBrackets:[bracket(0,0,100,100)])
    XCTAssertTrue(try WeeklyExperienceSettlementPlanner.prepare(entries:[entry()],configuration:zero,inboxEnabled:true).isEmpty)
  }
  func testInvalidCacheAndClockInputsRejectInsteadOfSilentlyDroppingAwards() throws {
    let config = WeeklyExperienceLeaderboardConfiguration(enabled:true,expirationTimeInDays:15,xpRewardBrackets:[bracket(1,3,1,3)])
    let value = entry()
    for entries in [[value,value],[entry(score:.nan)],[entry(seconds:-1)],[entry(score:9_007_199_254_740_992)]] {
      XCTAssertThrowsError(try WeeklyExperienceSettlementPlanner.prepare(entries:entries,configuration:config,inboxEnabled:true))
    }
    XCTAssertThrowsError(try WeeklyExperienceRewardSchedule(partitionKey:1))
    let schedule = try WeeklyExperienceRewardSchedule(partitionKey:0)
    XCTAssertThrowsError(try schedule.delayMilliseconds(at:Date(timeIntervalSince1970:.infinity)))
  }
  func testScheduleUsesFrozenPartitionPlusSevenDaysAndOneMinute() throws {
    let key = 1_799_712_000_000, schedule = try WeeklyExperienceRewardSchedule(partitionKey:key)
    XCTAssertEqual(schedule.dueMilliseconds,key + 604_800_000 + 60_000)
    XCTAssertEqual(try schedule.delayMilliseconds(at:Date(timeIntervalSince1970:Double(schedule.dueMilliseconds)/1_000 + 1)),-1_000)
    XCTAssertEqual(WeeklyExperienceRewardSchedule.maximumAttempts,23)
    XCTAssertEqual(WeeklyExperienceRewardSchedule.retryDelayMilliseconds,3_600_000)
    XCTAssertEqual(schedule.identity,try WeeklyExperienceRewardSchedule(partitionKey:key).identity)
  }

  func testActualPinnedWorkerQueueAndLuaRewardPreparation() throws {
    guard let root = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the read-only pinned source and dependency runtimes")
    }
    let script = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Scripts/check-source-weekly-xp-rewards.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
    process.arguments = ["node","--experimental-vm-modules",script.path,root,"--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus,0,String(decoding:diagnostics,as:UTF8.self))
    struct Queue: Decodable { let zone:String; let timestamp:Int; let key:Int; let delay:Int; let attempts:Int; let backoff:Int }
    struct Reward: Decodable { let rank:Int; let brackets:[WeeklyExperienceRewardBracket]; let reward:Double? }
    struct Entry: Decodable { let uid:UUID; let score:Double; let seconds:Double }
    struct Mail: Decodable { let uid:UUID; let reward:Int }
    struct Worker: Decodable {
      let brackets:[WeeklyExperienceRewardBracket]; let inboxEnabled:Bool; let failed:Bool
      let executions:Int; let maxMail:Int; let mails:[Mail]
    }
    struct Document: Decodable {
      let referenceCommit:String; let redisVersion:String; let lruVersion:String
      let queueFixtures:[Queue]; let rewardFixtures:[Reward]; let entries:[Entry]; let workerFixtures:[Worker]
      let uninitializedQueueCached:Bool; let evictionEnqueues:Int
    }
    let document = try JSONDecoder().decode(Document.self,from:data)
    XCTAssertEqual(document.referenceCommit,"91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(document.redisVersion,"6.2.6"); XCTAssertEqual(document.lruVersion,"11.5.1")
    XCTAssertEqual(document.queueFixtures.count,12); XCTAssertEqual(document.rewardFixtures.count,56)
    XCTAssertEqual(document.workerFixtures.count,16)
    // These observations do not assert Typebar already has a durable queue.
    XCTAssertTrue(document.uninitializedQueueCached); XCTAssertEqual(document.evictionEnqueues,102)
    for fixture in document.queueFixtures {
      let date = Date(timeIntervalSince1970:Double(fixture.timestamp)/1_000)
      let partition = try WeeklyExperiencePartition.capture(at:date,timeZone:XCTUnwrap(TimeZone(identifier:fixture.zone)))
      XCTAssertEqual(partition.keyMilliseconds,fixture.key)
      let schedule = try WeeklyExperienceRewardSchedule(partitionKey:partition.keyMilliseconds)
      XCTAssertEqual(try schedule.delayMilliseconds(at:date),fixture.delay)
      XCTAssertEqual(WeeklyExperienceRewardSchedule.maximumAttempts,fixture.attempts)
      XCTAssertEqual(WeeklyExperienceRewardSchedule.retryDelayMilliseconds,fixture.backoff)
    }
    for fixture in document.rewardFixtures {
      XCTAssertEqual(try WeeklyExperienceSettlementPlanner.reward(for:fixture.rank,brackets:fixture.brackets),fixture.reward)
    }
    let entries = document.entries.map { entry($0.uid,score:$0.score,seconds:$0.seconds) }
    for fixture in document.workerFixtures {
      let configuration = WeeklyExperienceLeaderboardConfiguration(enabled:true,expirationTimeInDays:15,xpRewardBrackets:fixture.brackets)
      if fixture.failed {
        XCTAssertThrowsError(try WeeklyExperienceSettlementPlanner.prepare(entries:entries,
          configuration:configuration,inboxEnabled:fixture.inboxEnabled)) { error in
            XCTAssertEqual(error as? WeeklyExperienceSettlementError,.emptyRewardBrackets)
        }
      } else {
        let plan = try WeeklyExperienceSettlementPlanner.prepare(entries:entries,configuration:configuration,inboxEnabled:fixture.inboxEnabled)
        XCTAssertEqual(plan.map(\.userID),fixture.mails.map(\.uid))
        XCTAssertEqual(plan.map(\.rewardExperience),fixture.mails.map(\.reward))
        // maxMail == 0 still emits a source Mongo push; actual delivery/claim is not exercised.
        if fixture.maxMail == 0 && fixture.inboxEnabled { XCTAssertEqual(fixture.executions,1) }
      }
    }
  }
}
