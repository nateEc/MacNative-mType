import Foundation
import XCTest
import Vapor
@testable import TypebarServerCore

final class WeeklyExperienceRewardJobTests: XCTestCase {
  private let now = Date(timeIntervalSince1970:1_800_000_000)
  private let password = "a secure password"
  private func configuration(_ reward: Int = 100) -> WeeklyExperienceLeaderboardConfiguration {
    .init(enabled:true,expirationTimeInDays:15,xpRewardBrackets:[.init(minRank:1,maxRank:10,minReward:reward,maxReward:reward)])
  }
  private func store(_ file: URL? = nil, reward: Int = 100) throws -> AuthStore {
    try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development,
      weeklyExperienceTimeZone:TimeZone(identifier:"UTC")!,weeklyExperienceConfiguration:configuration(reward))
  }
  private func account(_ store: AuthStore, at date: Date) async throws -> AuthSessionResponse {
    try await store.register(.init(email:"weekly-job@example.com",password:password,displayName:"Weekly"),now:date)
  }
  private func request(at date: Date) -> ResultSubmissionRequest {
    .init(id:UUID(),mode:"words",language:"english",durationSeconds:nil,wordLimit:25,wpm:60,rawWpm:60,
      accuracy:100,errorCount:0,eventCount:75,startedAt:date.addingTimeInterval(-15),finishedAt:date)
  }
  private func directory() throws -> URL {
    let value = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-weekly-jobs-\(UUID())")
    try FileManager.default.createDirectory(at:value,withIntermediateDirectories:false); return value
  }
  func testActualSubmissionSchedulesOnceAndDueTaskDeliversWithoutClaiming() async throws {
    let store = try store(), owner = try await account(store,at:now), input = request(at:now)
    let receipt = try await store.submitResult(input,accessToken:owner.accessToken,now:now)
    _ = try await store.submitResult(input,accessToken:owner.accessToken,now:now)
    let jobs = await store.weeklyExperienceRewardJobs()
    XCTAssertEqual(jobs.count,1); XCTAssertEqual(jobs[0].attempts,0); XCTAssertEqual(jobs[0].status,.pending)
    let due = Date(timeIntervalSince1970:Double(jobs[0].nextAttempt)/1_000)
    let tooSoon = try await store.processDueWeeklyExperienceRewards(now:due.addingTimeInterval(-0.001)); XCTAssertTrue(tooSoon.isEmpty)
    let processed = try await store.processDueWeeklyExperienceRewards(now:due)
    XCTAssertEqual(processed.first?.status,.complete); XCTAssertEqual(processed.first?.attempts,1)
    let inbox = try await store.rewardInbox(accessToken:owner.accessToken,now:due)
    XCTAssertEqual(inbox.inbox.count,1); XCTAssertEqual(inbox.inbox[0].rewards,[.xp(100)]); XCTAssertFalse(inbox.inbox[0].read)
    let user = try await store.authenticatedUser(for:owner.accessToken,now:due)
    XCTAssertEqual(user.totalExperience,receipt.totalExperience)
    let again = try await store.processDueWeeklyExperienceRewards(now:due.addingTimeInterval(1)); XCTAssertTrue(again.isEmpty)
    let claimed = try await store.updateRewardInbox(.init(mailIdsToMarkRead:[inbox.inbox[0].id]),accessToken:owner.accessToken,now:due)
    XCTAssertEqual(claimed.user.totalExperience,receipt.totalExperience + 100)
  }
  func testRestartUsesSettlementConfigurationNotFrozenSubmissionConfiguration() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), first = try store(file,reward:100)
    let owner = try await account(first,at:now)
    _ = try await first.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    let scheduled = await first.weeklyExperienceRewardJobs()
    let job = try XCTUnwrap(scheduled.first)
    let due = Date(timeIntervalSince1970:Double(job.nextAttempt)/1_000), next = try store(file,reward:75)
    try await next.processDueWeeklyExperienceRewards(now:due)
    let inbox = try await next.rewardInbox(accessToken:owner.accessToken,now:due)
    XCTAssertEqual(inbox.inbox[0].rewards,[.xp(75)])
    let reload = try store(file,reward:200)
    let noReplay = try await reload.processDueWeeklyExperienceRewards(now:due); XCTAssertTrue(noReplay.isEmpty)
    let retained = try await reload.rewardInbox(accessToken:owner.accessToken,now:due); XCTAssertEqual(retained.inbox,inbox.inbox)
  }
  func testEnabledEmptyBracketsRetryHourlyThenTerminateAt23WithoutMail() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development,weeklyExperienceTimeZone:TimeZone(identifier:"UTC")!)
    let owner = try await account(store,at:now)
    _ = try await store.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    let jobs = await store.weeklyExperienceRewardJobs(), due = try XCTUnwrap(jobs.first).nextAttempt
    for attempt in 1...23 {
      let date = Date(timeIntervalSince1970:Double(due + (attempt - 1)*3_600_000)/1_000)
      let processed = try await store.processDueWeeklyExperienceRewards(now:date)
      XCTAssertEqual(processed.first?.attempts,attempt); XCTAssertEqual(processed.first?.lastFailure,"emptyRewardBrackets")
      XCTAssertEqual(processed.first?.status,attempt == 23 ? .failed : .pending)
      let early = try await store.processDueWeeklyExperienceRewards(now:date.addingTimeInterval(3_599)); XCTAssertTrue(early.isEmpty)
    }
    let final = try await store.processDueWeeklyExperienceRewards(now:Date(timeIntervalSince1970:Double(due + 24*3_600_000)/1_000))
    XCTAssertTrue(final.isEmpty)
    let inbox = try await store.rewardInbox(accessToken:owner.accessToken,now:now); XCTAssertTrue(inbox.inbox.isEmpty)
  }
  func testFailedFileCommitLeavesPendingTaskAndNoPartialDelivery() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), backup = dir.appendingPathComponent("backup.json"), store = try store(file)
    let owner = try await account(store,at:now)
    _ = try await store.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    let jobs = await store.weeklyExperienceRewardJobs(), due = Date(timeIntervalSince1970:Double(try XCTUnwrap(jobs.first).nextAttempt)/1_000)
    try FileManager.default.moveItem(at:file,to:backup); try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
    do { try await store.processDueWeeklyExperienceRewards(now:due); XCTFail("Save must fail") } catch { }
    let pending = await store.weeklyExperienceRewardJobs(); XCTAssertEqual(pending.first?.attempts,0)
    let unchanged = try await store.rewardInbox(accessToken:owner.accessToken,now:due); XCTAssertTrue(unchanged.inbox.isEmpty)
    try FileManager.default.removeItem(at:file); try FileManager.default.moveItem(at:backup,to:file)
    let reloaded = try self.store(file)
    try await reloaded.processDueWeeklyExperienceRewards(now:due)
    let inbox = try await reloaded.rewardInbox(accessToken:owner.accessToken,now:due); XCTAssertEqual(inbox.inbox.count,1)
  }
  func testMissingManagedJobsRejectButTrueOlderReceiptDoesNotInventHistoricalTask() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), first = try store(file), owner = try await account(first,at:now)
    _ = try await first.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
    object.removeValue(forKey:"weeklyRewardJobs")
    let broken = try JSONSerialization.data(withJSONObject:object,options:.sortedKeys); try broken.write(to:file,options:.atomic)
    XCTAssertThrowsError(try store(file)); XCTAssertEqual(try Data(contentsOf:file),broken)
    var awards = try XCTUnwrap(object["experienceAwards"] as? [[String:Any]])
    for index in awards.indices {
      var receipt = try XCTUnwrap(awards[index]["weeklyCacheReceipt"] as? [String:Any])
      receipt.removeValue(forKey:"settlementScheduled"); awards[index]["weeklyCacheReceipt"] = receipt
    }
    object["experienceAwards"] = awards
    object.removeValue(forKey:"weeklyRewardJobsManaged")
    let old = try JSONSerialization.data(withJSONObject:object,options:.sortedKeys); try old.write(to:file,options:.atomic)
    let restored = try store(file), jobs = await restored.weeklyExperienceRewardJobs()
    XCTAssertTrue(jobs.isEmpty); XCTAssertEqual(try Data(contentsOf:file),old)
  }
  func testMissingCompletedJobsCannotBeMistakenForLegacyAfterAccountReset() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), store = try store(file), owner = try await account(store,at:now)
    _ = try await store.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    let scheduled = await store.weeklyExperienceRewardJobs(), due = try XCTUnwrap(scheduled.first).nextAttempt
    try await store.processDueWeeklyExperienceRewards(now:Date(timeIntervalSince1970:Double(due)/1_000))
    _ = try await store.resetAccount(.init(currentPassword:password),accessToken:owner.accessToken,now:now)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
    object.removeValue(forKey:"weeklyRewardJobs")
    let bytes = try JSONSerialization.data(withJSONObject:object,options:.sortedKeys); try bytes.write(to:file,options:.atomic)
    XCTAssertThrowsError(try self.store(file)); XCTAssertEqual(try Data(contentsOf:file),bytes)
  }
  func testActualLifecycleWorkerRunsAndStopsWithoutGUIOrDuplicateDelivery() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), store = try store(file)
    let past = Date.now.addingTimeInterval(-8*86_400), owner = try await account(store,at:past)
    _ = try await store.submitResult(request(at:past),accessToken:owner.accessToken,now:past)
    let worker = WeeklyExperienceRewardWorker(store:store,intervalNanoseconds:10_000_000)
    let app = try await Application.make(.testing)
    app.lifecycle.use(worker)
    try await app.asyncBoot(); try await app.asyncBoot()
    for _ in 0..<100 {
      if await store.weeklyExperienceRewardJobs().first?.status == .complete { break }
      try? await Task.sleep(nanoseconds:10_000_000)
    }
    try await app.asyncShutdown()
    let jobs = await store.weeklyExperienceRewardJobs(); XCTAssertEqual(jobs.first?.status,.complete)
    let inbox = try await store.rewardInbox(accessToken:owner.accessToken); XCTAssertEqual(inbox.inbox.count,1)
    await worker.start(); await Task.yield(); await worker.stop()
    let same = try await store.rewardInbox(accessToken:owner.accessToken); XCTAssertEqual(same.inbox,inbox.inbox)
  }

  func testDisabledInboxZeroCapacityAndZeroRewardRetainSourceDeliveryDistinctions() async throws {
    for mode in 0..<3 {
      let configuration = WeeklyExperienceLeaderboardConfiguration(enabled:true,expirationTimeInDays:15,
        xpRewardBrackets:[.init(minRank:1,maxRank:10,minReward:0,maxReward:0)])
      let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development,
        weeklyExperienceTimeZone:TimeZone(identifier:"UTC")!,weeklyExperienceConfiguration:configuration,
        rewardInboxConfiguration:.init(enabled:mode != 0,maxMail:mode == 1 ? 0 : 100))
      let owner = try await account(store,at:now)
      _ = try await store.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
      let jobs = await store.weeklyExperienceRewardJobs(), due = try XCTUnwrap(jobs.first).nextAttempt
      let processed = try await store.processDueWeeklyExperienceRewards(now:Date(timeIntervalSince1970:Double(due)/1_000))
      XCTAssertEqual(processed.first?.status,.complete)
      if mode != 0 {
        let inbox = try await store.rewardInbox(accessToken:owner.accessToken,now:now)
        XCTAssertEqual(inbox.inbox.count,mode == 1 ? 0 : 1)
        if mode == 2 { XCTAssertEqual(inbox.inbox[0].rewards,[.xp(0)]); XCTAssertFalse(inbox.inbox[0].read) }
      }
    }
  }
}
