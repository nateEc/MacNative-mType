import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class DailyLeaderboardRewardJobTests: XCTestCase {
  private let now = Date(timeIntervalSince1970:1_800_000_000)
  private let password = "a secure password"
  private func configuration(reward: Int = 100, enabled: Bool = true, days: Double = 2,
    capacity: Int = 1000, scheduled: Bool = true, brackets: Bool = true, announced: Int = 1) throws -> DailyLeaderboardConfiguration {
    let rules = scheduled ? #"[{"language":"english","mode":".*","mode2":".*"}]"# : "[]"
    let rewards = brackets ? "[{\"minRank\":1,\"maxRank\":10,\"minReward\":\(reward),\"maxReward\":\(reward)}]" : "[]"
    return try .fromJSON("""
      {"enabled":\(enabled),"expirationTimeInDays":\(days),"maxResults":\(capacity),
       "validModeRules":[{"language":"english","mode":".*","mode2":".*"}],
       "scheduleRewardsModeRules":\(rules),"topResultsToAnnounce":\(announced),"xpRewardBrackets":\(rewards)}
      """)
  }
  private func store(_ file: URL? = nil, reward: Int = 100, config: DailyLeaderboardConfiguration? = nil,
    inbox: RewardInboxConfiguration = .typebarDefault) throws -> AuthStore {
    try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development,
      weeklyExperienceConfiguration:.init(enabled:false,expirationTimeInDays:0),
      rewardInboxConfiguration:inbox,dailyLeaderboardConfiguration:config ?? configuration(reward:reward))
  }
  private func account(_ store: AuthStore, at date: Date) async throws -> AuthSessionResponse {
    try await store.register(.init(email:"daily-reward@example.com",password:password,displayName:"Daily Winner"),now:date)
  }
  private func request(at date: Date, wpm: Int = 60, mode: String = "words") -> ResultSubmissionRequest {
    .init(id:UUID(),mode:mode,language:"english",durationSeconds:mode == "time" ? 15 : nil,
      wordLimit:mode == "words" ? 25 : nil,wpm:wpm,rawWpm:wpm,
      accuracy:100,errorCount:0,eventCount:75,startedAt:date.addingTimeInterval(-900 / Double(wpm)),finishedAt:date)
  }
  private func directory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-daily-rewards-\(UUID())")
    try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:false); return dir
  }
  private func due(_ store: AuthStore) async throws -> Date {
    let jobs = await store.dailyLeaderboardRewardJobs()
    return Date(timeIntervalSince1970:Double(try XCTUnwrap(jobs.first).nextAttempt)/1_000)
  }
  func testExistingLifecycleDeliversDailyRewardAndNativeAnnouncementWithoutClaimingXP() async throws {
    let store = try store(), past = Date.now.addingTimeInterval(-86_400)
    let owner = try await account(store,at:past)
    let receipt = try await store.submitResult(request(at:past),accessToken:owner.accessToken,now:past)
    let worker = WeeklyExperienceRewardWorker(store:store,intervalNanoseconds:10_000_000)
    await worker.start()
    for _ in 0..<100 {
      if try await store.rewardInbox(accessToken:owner.accessToken).inbox.count == 1 { break }
      try? await Task.sleep(nanoseconds:10_000_000)
    }
    await worker.stop()
    let inbox = try await store.rewardInbox(accessToken:owner.accessToken)
    XCTAssertEqual(inbox.inbox.count,1,"Configured daily placement must reach the existing native inbox")
    XCTAssertEqual(inbox.inbox.first?.rewards,[.xp(100)])
    let user = try await store.authenticatedUser(for:owner.accessToken)
    XCTAssertEqual(user.totalExperience,receipt.totalExperience,"Delivery is not claiming")
    let announcements = await store.publicAnnouncements()
    XCTAssertEqual(announcements.announcements.count,1,"Daily winners must be visible through the native announcement consumer")
  }
  func testSubmissionSchedulesAcceptedDayAndConcreteModeOnceEvenForUnchangedAttempt() async throws {
    let store = try store(), owner = try await account(store,at:now)
    let input = request(at:now.addingTimeInterval(-86_400))
    _ = try await store.submitResult(input,accessToken:owner.accessToken,now:now)
    _ = try await store.submitResult(input,accessToken:owner.accessToken,now:now.addingTimeInterval(1))
    let unchanged = try await store.submitResult(request(at:now.addingTimeInterval(2)),accessToken:owner.accessToken,now:now.addingTimeInterval(2))
    XCTAssertNil(unchanged.dailyLeaderboardRank)
    let first = await store.dailyLeaderboardRewardJobs()
    XCTAssertEqual(first.count,1); XCTAssertEqual(first[0].key,try DailyLeaderboardCache.key(at:now))
    XCTAssertEqual(first[0].modeRule,.init(language:"english",mode:"words",mode2:"25"))
    XCTAssertEqual(first[0].nextAttempt,first[0].key+86_460_000)
    _ = try await store.submitResult(request(at:now,mode:"time"),accessToken:owner.accessToken,now:now)
    let separate = await store.dailyLeaderboardRewardJobs(); XCTAssertEqual(separate.count,2)
    let due = try await due(store)
    let early = try await store.processDueDailyLeaderboardRewards(now:due.addingTimeInterval(-0.001)); XCTAssertTrue(early.isEmpty)
    let processed = try await store.processDueDailyLeaderboardRewards(now:due,maximumJobs:1)
    XCTAssertEqual(processed.count,1); XCTAssertEqual(processed[0].status,.complete)
    let rest = try await store.processDueDailyLeaderboardRewards(now:due); XCTAssertEqual(rest.count,1)
    let later = try await store.processDueDailyLeaderboardRewards(now:due); XCTAssertTrue(later.isEmpty)
  }
  func testEvictedAndImmediatelyExpiredAttemptsStillScheduleAndCompleteWithoutMail() async throws {
    for config in [try configuration(days:0),try configuration(capacity:0)] {
      let store = try store(config:config), owner = try await account(store,at:now)
      let receipt = try await store.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
      XCTAssertNil(receipt.dailyLeaderboardRank)
      let jobs = await store.dailyLeaderboardRewardJobs(); XCTAssertEqual(jobs.count,1)
      let processed = try await store.processDueDailyLeaderboardRewards(now:due(store)); XCTAssertEqual(processed[0].status,.complete)
      let inbox = try await store.rewardInbox(accessToken:owner.accessToken,now:now); XCTAssertTrue(inbox.inbox.isEmpty)
      let announcements = await store.publicAnnouncements(); XCTAssertTrue(announcements.announcements.isEmpty)
    }
  }
  func testNoRewardRuleOrDisabledSubmissionIsNeverBackfilledOnEnableOrRetry() async throws {
    for config in [try configuration(enabled:false),try configuration(scheduled:false)] {
      let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
      let file = dir.appendingPathComponent("store.json"), first = try store(file,config:config)
      let owner = try await account(first,at:now), input = request(at:now)
      _ = try await first.submitResult(input,accessToken:owner.accessToken,now:now)
      let before = await first.dailyLeaderboardRewardJobs(); XCTAssertTrue(before.isEmpty)
      let next = try store(file)
      _ = try await next.submitResult(input,accessToken:owner.accessToken,now:now)
      let after = await next.dailyLeaderboardRewardJobs(); XCTAssertTrue(after.isEmpty)
    }
  }
  func testRestartUsesCurrentRewardConfigurationAndWinningNameAfterHistoryDeletion() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), first = try store(file), owner = try await account(first,at:now)
    let receipt = try await first.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    _ = try await first.updateProfile(.init(displayName:"Changed"),accessToken:owner.accessToken,now:now)
    _ = try await first.deleteResults(.init(currentPassword:password),accessToken:owner.accessToken,now:now)
    let date = try await due(first), bytes = try Data(contentsOf:file), next = try store(file,reward:75)
    XCTAssertEqual(try Data(contentsOf:file),bytes)
    try await next.processDueDailyLeaderboardRewards(now:date)
    let inbox = try await next.rewardInbox(accessToken:owner.accessToken,now:date)
    XCTAssertEqual(inbox.inbox.first?.rewards,[.xp(75)]); XCTAssertTrue(inbox.inbox[0].body.contains("Daily Winner"))
    XCTAssertFalse(inbox.inbox[0].body.contains("Changed"))
    let claimed = try await next.updateRewardInbox(.init(mailIdsToMarkRead:[inbox.inbox[0].id]),accessToken:owner.accessToken,now:date)
    XCTAssertEqual(claimed.user.totalExperience,receipt.totalExperience+75)
    let reload = try store(file,reward:200), noReplay = try await reload.processDueDailyLeaderboardRewards(now:date)
    XCTAssertTrue(noReplay.isEmpty)
    let retained = try await reload.rewardInbox(accessToken:owner.accessToken,now:date)
    XCTAssertTrue(retained.inbox[0].read); XCTAssertTrue(retained.inbox[0].rewards.isEmpty)
    let announcements = await reload.publicAnnouncements(); XCTAssertEqual(announcements.announcements.count,1)
  }
  func testEmptyBracketsDisabledInboxAndZeroCapacityStillAnnounceButDisabledBoardDoesNot() async throws {
    for variant in 0..<5 {
      let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
      let file = dir.appendingPathComponent("store.json")
      let first = try store(file,config:configuration(reward:0,brackets:variant != 0),
        inbox:.init(enabled:variant != 1,maxMail:variant == 2 ? 0 : 100))
      let owner = try await account(first,at:now)
      _ = try await first.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
      let date = try await due(first)
      let next = variant == 3 ? try store(file,config:configuration(enabled:false)) : first
      let processed = try await next.processDueDailyLeaderboardRewards(now:date)
      XCTAssertEqual(processed.first?.status,.complete); XCTAssertNil(processed.first?.lastFailure)
      let announcements = await next.publicAnnouncements(); XCTAssertEqual(announcements.announcements.count,variant == 3 ? 0 : 1)
      if variant != 1 {
        let inbox = try await next.rewardInbox(accessToken:owner.accessToken,now:date)
        XCTAssertEqual(inbox.inbox.count,variant == 4 ? 1 : 0)
        if variant == 4 { XCTAssertEqual(inbox.inbox[0].rewards,[.xp(0)]); XCTAssertFalse(inbox.inbox[0].read) }
      }
    }
  }
  func testConcurrentProcessingDoesNotRepeatMailOrAnnouncements() async throws {
    let store = try store(), owner = try await account(store,at:now)
    _ = try await store.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    let date = try await due(store)
    async let first = store.processDueDailyLeaderboardRewards(now:date)
    async let second = store.processDueDailyLeaderboardRewards(now:date)
    let count = try await first.count + second.count; XCTAssertEqual(count,1)
    let inbox = try await store.rewardInbox(accessToken:owner.accessToken,now:date); XCTAssertEqual(inbox.inbox.count,1)
    let announcements = await store.publicAnnouncements(); XCTAssertEqual(announcements.announcements.count,1)
  }
  func testFailedFileCommitRollsBackBothMailAndAnnouncementAndCanRetryAfterRestart() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), backup = dir.appendingPathComponent("backup.json")
    let first = try store(file), owner = try await account(first,at:now)
    _ = try await first.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    let date = try await due(first), original = try Data(contentsOf:file)
    try FileManager.default.moveItem(at:file,to:backup); try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
    do { try await first.processDueDailyLeaderboardRewards(now:date); XCTFail("Commit must fail") } catch { }
    let jobs = await first.dailyLeaderboardRewardJobs(); XCTAssertEqual(jobs[0].attempts,0); XCTAssertEqual(jobs[0].status,.pending)
    let inbox = try await first.rewardInbox(accessToken:owner.accessToken,now:date); XCTAssertTrue(inbox.inbox.isEmpty)
    let announcements = await first.publicAnnouncements(); XCTAssertTrue(announcements.announcements.isEmpty)
    XCTAssertEqual(try Data(contentsOf:backup),original)
    try FileManager.default.removeItem(at:file); try FileManager.default.moveItem(at:backup,to:file)
    let reload = try store(file); try await reload.processDueDailyLeaderboardRewards(now:date)
    let delivered = try await reload.rewardInbox(accessToken:owner.accessToken,now:date); XCTAssertEqual(delivered.inbox.count,1)
    let published = await reload.publicAnnouncements(); XCTAssertEqual(published.announcements.count,1)
  }
  func testManagedMissingNullDuplicateAndInvalidJobStatesRejectWithoutWriting() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), first = try store(file), owner = try await account(first,at:now)
    _ = try await first.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
    for variant in 0..<8 {
      var object = original
      if variant == 0 { object.removeValue(forKey:"dailyRewardJobs") }
      else if variant == 1 { object["dailyRewardJobs"] = NSNull() }
      else if variant == 6 {
        object.removeValue(forKey:"dailyRewardJobs"); object.removeValue(forKey:"dailyRewardJobsManaged")
      } else if variant == 7 {
        var awards = try XCTUnwrap(object["experienceAwards"] as? [[String:Any]])
        var receipt = try XCTUnwrap(awards[0]["dailyCacheReceipt"] as? [String:Any])
        receipt["settlementScheduled"] = NSNull(); awards[0]["dailyCacheReceipt"] = receipt
        object["experienceAwards"] = awards
      }
      else {
        var state = try XCTUnwrap(object["dailyRewardJobs"] as? [String:Any])
        var jobs = try XCTUnwrap(state["jobs"] as? [[String:Any]])
        switch variant {
        case 2: state["version"] = 2
        case 3: jobs.append(jobs[0])
        case 4: jobs[0]["attempts"] = 23
        default: jobs[0]["key"] = 1
        }
        state["jobs"] = jobs; object["dailyRewardJobs"] = state
      }
      let bytes = try JSONSerialization.data(withJSONObject:object,options:.sortedKeys); try bytes.write(to:file,options:.atomic)
      XCTAssertThrowsError(try store(file)); XCTAssertEqual(try Data(contentsOf:file),bytes)
    }
  }
  func testTrueOldReceiptDoesNotInventJobsButManagedMarkerSurvivesReset() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), first = try store(file), owner = try await account(first,at:now)
    _ = try await first.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
    object.removeValue(forKey:"dailyRewardJobs"); object.removeValue(forKey:"dailyRewardJobsManaged")
    var awards = try XCTUnwrap(object["experienceAwards"] as? [[String:Any]])
    var receipt = try XCTUnwrap(awards[0]["dailyCacheReceipt"] as? [String:Any]); receipt.removeValue(forKey:"settlementScheduled")
    awards[0]["dailyCacheReceipt"] = receipt; object["experienceAwards"] = awards
    let old = try JSONSerialization.data(withJSONObject:object,options:.sortedKeys); try old.write(to:file,options:.atomic)
    let next = try store(file), jobs = await next.dailyLeaderboardRewardJobs(); XCTAssertTrue(jobs.isEmpty)
    XCTAssertEqual(try Data(contentsOf:file),old)
    _ = try await next.resetAccount(.init(currentPassword:password),accessToken:owner.accessToken,now:now)
    object = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
    object.removeValue(forKey:"dailyRewardJobs")
    let broken = try JSONSerialization.data(withJSONObject:object,options:.sortedKeys); try broken.write(to:file,options:.atomic)
    XCTAssertThrowsError(try store(file)); XCTAssertEqual(try Data(contentsOf:file),broken)
  }
  func testOptOutPurgesFuturePlacementAndNameRemediationHidesPublicAnnouncement() async throws {
    for optedOut in [true,false] {
      let store = try store(), owner = try await account(store,at:now)
      _ = try await store.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
      if optedOut { _ = try await store.updateProfile(.init(leaderboardOptedOut:true),accessToken:owner.accessToken,now:now) }
      else { _ = try await store.setDisplayNameChangeRequired(userID:owner.user.id,required:true) }
      try await store.processDueDailyLeaderboardRewards(now:due(store))
      let announcements = await store.publicAnnouncements(); XCTAssertTrue(announcements.announcements.isEmpty)
      let inbox = try await store.rewardInbox(accessToken:owner.accessToken,now:now)
      XCTAssertEqual(inbox.inbox.count,optedOut ? 0 : 1,"Private reward does not publish a remediated name")
    }
  }
  func testDailyJobStatusRouteIsReadOnlyDeploymentScopedAndPublicAnnouncementIsReadable() async throws {
    let store = try store(), owner = try await account(store,at:now)
    _ = try await store.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    try await store.processDueDailyLeaderboardRewards(now:due(store))
    let app = try await Application.make(.testing)
    do {
      try configure(app,authStore:store,moderationKey:"daily-fixture")
      for key in [nil,"wrong","daily-fixture"] {
        try await app.test(.GET,"v1/moderation/daily-rewards",beforeRequest:{ request in
          if let key { request.headers.add(name:"X-Typebar-Moderation-Key",value:key) }
        }) { response async throws in
          XCTAssertEqual(response.status,key == "daily-fixture" ? .ok : .forbidden)
          if response.status == .ok {
            let jobs = try response.content.decode([DailyLeaderboardRewardJob].self)
            XCTAssertEqual(jobs.first?.status,.complete)
          }
        }
      }
      try await app.test(.GET,"v1/announcements") { response async throws in
        XCTAssertEqual(response.status,.ok)
        let published = try response.content.decode(PublicAnnouncementsResponse.self)
        XCTAssertEqual(published.announcements.count,1); XCTAssertTrue(published.announcements[0].message.contains("Daily Winner"))
      }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
  func testConfigurationDefaultsStrictNullAndJobRetryBounds() throws {
    let old = #"{"enabled":true,"expirationTimeInDays":2,"maxResults":1000,"validModeRules":[]}"#
    let config = try DailyLeaderboardConfiguration.fromJSON(old)
    XCTAssertEqual(config.scheduleRewardsModeRules,[]); XCTAssertEqual(config.topResultsToAnnounce,1); XCTAssertEqual(config.xpRewardBrackets,[])
    for key in ["scheduleRewardsModeRules","topResultsToAnnounce","xpRewardBrackets"] {
      var object = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(old.utf8)) as? [String:Any]); object[key] = NSNull()
      let data = try JSONSerialization.data(withJSONObject:object)
      XCTAssertThrowsError(try DailyLeaderboardConfiguration.fromJSON(String(decoding:data,as:UTF8.self)))
    }
    XCTAssertThrowsError(try configuration(announced:0)); XCTAssertThrowsError(try configuration(reward:-1))
    var job = try DailyLeaderboardRewardJob(key:try DailyLeaderboardCache.key(at:now),modeRule:.init(language:"english",mode:"words",mode2:"25"))
    for attempt in 1...23 {
      job.attempts = attempt; job.nextAttempt += DailyLeaderboardRewardJob.retryDelayMilliseconds
      job.lastFailure = "invalidRewardState"; job.status = attempt == 23 ? .failed : .pending
      XCTAssertNoThrow(try job.validate())
    }
    job.status = .pending; XCTAssertThrowsError(try job.validate())
  }
  func testActualPinnedDailyWorkerQueueLuaAndGeorgeAnnouncementSelectionDifferential() throws {
    guard let root = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the read-only source and isolated LRU/Redis runtimes")
    }
    let script = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Scripts/check-source-weekly-xp-rewards.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
    process.arguments = ["node","--experimental-vm-modules",script.path,root,"--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus,0,String(decoding:diagnostics,as:UTF8.self))
    struct Queue: Decodable { let zone:String; let timestamp:Int; let key:Int; let delay:Int; let attempts:Int; let backoff:Int }
    struct Entry: Decodable { let uid:UUID; let wpm:Int; let acc:Int; let timestamp:Int; let name:String }
    struct Mail: Decodable { let uid:UUID; let reward:Int }
    struct Worker: Decodable {
      let brackets:[WeeklyExperienceRewardBracket]; let inboxEnabled:Bool; let enabled:Bool; let empty:Bool
      let mails:[Mail]; let announced:[UUID]
    }
    struct Document: Decodable {
      let referenceCommit:String; let redisVersion:String; let lruVersion:String
      let dailyQueueFixtures:[Queue]; let dailyEntries:[Entry]; let dailyWorkerFixtures:[Worker]
    }
    let document = try JSONDecoder().decode(Document.self,from:bytes)
    XCTAssertEqual(document.referenceCommit,"91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(document.redisVersion,"6.2.6"); XCTAssertEqual(document.lruVersion,"11.5.1")
    XCTAssertEqual(document.dailyQueueFixtures.count,12); XCTAssertEqual(document.dailyWorkerFixtures.count,18)
    for fixture in document.dailyQueueFixtures {
      let key = try DailyLeaderboardCache.key(at:Date(timeIntervalSince1970:Double(fixture.timestamp)/1_000))
      XCTAssertEqual(key,fixture.key,"UTC day identity must not vary with \(fixture.zone)")
      XCTAssertEqual(try DailyLeaderboardRewardJob.due(key:key)-fixture.timestamp,fixture.delay)
      XCTAssertEqual(DailyLeaderboardRewardJob.maximumAttempts,fixture.attempts)
      XCTAssertEqual(DailyLeaderboardRewardJob.retryDelayMilliseconds,fixture.backoff)
    }
    let entries = document.dailyEntries.map { value in
      DailyLeaderboardCache.Entry(userID:value.uid,resultID:UUID(),displayName:value.name,language:"english",
        mode:"words",mode2:"25",wpm:value.wpm,accuracy:value.acc,preciseAccuracy:nil,consistency:0,
        finishedAt:Date(timeIntervalSince1970:Double(value.timestamp)/1_000),
        profileSnapshot:.init(version:1,selectedBadge:nil,discordAvatar:nil))
    }
    for fixture in document.dailyWorkerFixtures {
      let config = DailyLeaderboardConfiguration(enabled:fixture.enabled,expirationTimeInDays:2,maxResults:1000,
        validModeRules:[],topResultsToAnnounce:2,xpRewardBrackets:fixture.brackets)
      let placements = try DailyLeaderboardSettlementPlanner.prepare(entries:fixture.empty ? [] : entries,
        configuration:config,inboxEnabled:fixture.inboxEnabled)
      let rewarded = placements.filter { $0.rewardExperience != nil }
      XCTAssertEqual(rewarded.map { $0.entry.userID },fixture.mails.map(\.uid))
      XCTAssertEqual(rewarded.map { $0.rewardExperience! },fixture.mails.map(\.reward))
      XCTAssertEqual(placements.filter(\.announce).map { $0.entry.userID },fixture.announced)
    }
  }
}
