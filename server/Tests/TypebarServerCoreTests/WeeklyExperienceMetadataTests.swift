import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class WeeklyExperienceMetadataTests: XCTestCase {
  private let now = Date(timeIntervalSince1970:1_800_000_000.875)
  private let password = "a secure password"
  private func request(at date: Date, seconds: Double = 15.25) -> ResultSubmissionRequest {
    let speed = Int((900 / seconds).rounded())
    return .init(id:UUID(),mode:"words",language:"english",durationSeconds:nil,wordLimit:25,
      wpm:speed,rawWpm:speed,accuracy:100,errorCount:0,eventCount:75,
      practiceTiming:.init(version:1,terminalEngagedMilliseconds:Int(seconds * 1_000),priorAttemptEngagedMilliseconds:0),
      startedAt:date.addingTimeInterval(-seconds),finishedAt:date)
  }
  private func account(_ store: AuthStore) async throws -> AuthSessionResponse {
    try await store.register(.init(email:"metadata@example.com",password:password,displayName:"Metadata"),now:now)
  }
  private func json<T: Encodable>(_ value: T) throws -> [String:Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as? [String:Any])
  }

  func testPublicMetadataAccumulatesOnlyAcceptedCacheWritesAndKeepsMillisecondClock() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await account(store), first = request(at:now)
    _ = try await store.submitResult(first,accessToken:owner.accessToken,now:now)
    let later = now.addingTimeInterval(30)
    _ = try await store.submitResult(request(at:later,seconds:30.5),accessToken:owner.accessToken,now:later)
    _ = try await store.submitResult(first,accessToken:owner.accessToken,now:later.addingTimeInterval(1))
    _ = try await store.deleteResults(.init(currentPassword:password),accessToken:owner.accessToken,now:later)
    let page = try await store.experienceLeaderboard(now:later)
    let object = try json(XCTUnwrap(page.entries.first))
    XCTAssertEqual(object["timeTypedSeconds"] as? Double,45.75)
    XCTAssertEqual(object["lastActivityTimestamp"] as? Int,1_800_000_030_875)
  }

  func testSelectingBadgeDoesNotRefreshWeeklySnapshotUntilNextAcceptedWrite() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await account(store)
    _ = try await store.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    _ = try await store.updateProfile(.init(selectedBadgeID:"first-finish"),accessToken:owner.accessToken,now:now)
    let before = try await store.experienceLeaderboard(now:now)
    XCTAssertNil(before.entries.first?.selectedBadge)
    _ = try await store.submitResult(request(at:now.addingTimeInterval(1)),accessToken:owner.accessToken,now:now.addingTimeInterval(1))
    let after = try await store.experienceLeaderboard(now:now.addingTimeInterval(1))
    XCTAssertEqual(after.entries.first?.selectedBadge?.id,"first-finish")
    _ = try await store.updateProfile(.init(selectedBadgeID:""),accessToken:owner.accessToken,now:now.addingTimeInterval(1))
    _ = try await store.deleteResults(.init(currentPassword:password),accessToken:owner.accessToken,now:now.addingTimeInterval(1))
    let retained = try await store.experienceLeaderboard(now:now.addingTimeInterval(1))
    XCTAssertEqual(retained.entries.first?.selectedBadge?.id,"first-finish")
    _ = try await store.submitResult(request(at:now.addingTimeInterval(2)),accessToken:owner.accessToken,now:now.addingTimeInterval(2))
    let cleared = try await store.experienceLeaderboard(now:now.addingTimeInterval(2))
    XCTAssertNil(cleared.entries.first?.selectedBadge)
  }

  func testAvatarSnapshotChangesOnlyOnWriteButPrivacyAndUnlinkRemainImmediate() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await account(store), firstHash = String(repeating:"a",count:32), nextHash = String(repeating:"b",count:32)
    let first = OAuthProviderIdentity(provider:.discord,subject:"123456789012345678",email:"metadata@example.com",avatarHash:firstHash)
    let next = OAuthProviderIdentity(provider:.discord,subject:first.subject,email:first.email,avatarHash:nextHash)
    _ = try await store.linkOAuth(first,accessToken:owner.accessToken,now:now)
    _ = try await store.updateProfile(.init(profileDetails:.init(showDiscordAvatar:true)),accessToken:owner.accessToken,now:now)
    _ = try await store.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    _ = try await store.linkOAuth(next,accessToken:owner.accessToken,now:now)
    let unchanged = try await store.experienceLeaderboard(now:now)
    XCTAssertEqual(unchanged.entries.first?.discordAvatar?.avatarHash,firstHash)
    _ = try await store.updateProfile(.init(profileDetails:.init(showDiscordAvatar:false)),accessToken:owner.accessToken,now:now)
    let hidden = try await store.experienceLeaderboard(now:now); XCTAssertNil(hidden.entries.first?.discordAvatar)
    _ = try await store.updateProfile(.init(profileDetails:.init(showDiscordAvatar:true)),accessToken:owner.accessToken,now:now)
    _ = try await store.submitResult(request(at:now.addingTimeInterval(1)),accessToken:owner.accessToken,now:now.addingTimeInterval(1))
    let refreshed = try await store.experienceLeaderboard(now:now.addingTimeInterval(1))
    XCTAssertEqual(refreshed.entries.first?.discordAvatar?.avatarHash,nextHash)
    let confirmation = try await store.reauthenticateWithPassword(.init(currentPassword:password),accessToken:owner.accessToken,now:now.addingTimeInterval(1))
    _ = try await store.unlinkOAuth(.discord,accessToken:owner.accessToken,reauthenticationToken:confirmation.reauthenticationToken,now:now.addingTimeInterval(1))
    let unlinked = try await store.experienceLeaderboard(now:now.addingTimeInterval(1)); XCTAssertNil(unlinked.entries.first?.discordAvatar)
  }

  func testAllFourHTTPViewsExposeTimingAndKeepTheSameMetadataSnapshot() async throws {
    let date = Date.now, store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await store.register(.init(email:"http-metadata@example.com",password:password,displayName:"HTTP Metadata"),now:date)
    _ = try await store.submitResult(request(at:date),accessToken:owner.accessToken,now:date)
    let app = try await Application.make(.testing)
    do {
      try configure(app,authStore:store)
      for suffix in ["","/friends","/rank","/friends/rank"] {
        try await app.test(.GET,"v1/leaderboards/experience"+suffix,beforeRequest: { request in
          request.headers.bearerAuthorization = .init(token:owner.accessToken)
        }) { response async throws in
          XCTAssertEqual(response.status,.ok)
          let entry: ExperienceLeaderboardEntry?
          if suffix.hasSuffix("rank") { entry = try response.content.decode(ExperienceLeaderboardRankResponse.self).entry }
          else { entry = try response.content.decode(ExperienceLeaderboardResponse.self).entries.first }
          XCTAssertEqual(entry?.timeTypedSeconds,15.25)
          XCTAssertEqual(entry?.lastActivityTimestamp,Int((date.timeIntervalSince1970 * 1_000).rounded(.towardZero)))
        }
      }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }

  func testOldMissingSnapshotDoesNotInventCurrentBadgeAndReadsDoNotWriteBackup() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-week-metadata-\(UUID())")
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
    defer { try? FileManager.default.removeItem(at:directory) }
    let file = directory.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await account(store)
    _ = try await store.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    _ = try await store.updateProfile(.init(selectedBadgeID:"first-finish"),accessToken:owner.accessToken,now:now)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
    var cache = try XCTUnwrap(object["weeklyExperienceCache"] as? [String:Any])
    var buckets = try XCTUnwrap(cache["buckets"] as? [[String:Any]])
    var entries = try XCTUnwrap(buckets[0]["entries"] as? [[String:Any]])
    entries[0].removeValue(forKey:"profileSnapshot"); buckets[0]["entries"] = entries
    cache["buckets"] = buckets; object["weeklyExperienceCache"] = cache
    let bytes = try JSONSerialization.data(withJSONObject:object); try bytes.write(to:file,options:.atomic)
    let reload = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let board = try await reload.experienceLeaderboard(now:now)
    XCTAssertNil(board.entries.first?.selectedBadge)
    XCTAssertEqual(board.entries.first?.timeTypedSeconds,15.25)
    XCTAssertEqual(board.entries.first?.lastActivityTimestamp,1_800_000_000_875)
    XCTAssertEqual(try Data(contentsOf:file),bytes)
    for snapshot: Any in [NSNull(),["version":99],["version":1,"discordAvatar":["subject":"1","avatarHash":"../unsafe"]]] {
      entries[0]["profileSnapshot"] = snapshot; buckets[0]["entries"] = entries
      cache["buckets"] = buckets; object["weeklyExperienceCache"] = cache
      let invalid = try JSONSerialization.data(withJSONObject:object); try invalid.write(to:file,options:.atomic)
      XCTAssertThrowsError(try AuthStore(fileURL:file,bcryptCost:4))
      XCTAssertEqual(try Data(contentsOf:file),invalid)
    }
  }

  func testMixedLegacyRewardsDoNotPresentPartialNewCacheTimeAsWholeWeekTime() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-week-metadata-legacy-\(UUID())")
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
    defer { try? FileManager.default.removeItem(at:directory) }
    let file = directory.appendingPathComponent("store.json")
    let first = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await account(first)
    _ = try await first.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
    var awards = try XCTUnwrap(object["experienceAwards"] as? [[String:Any]])
    awards[0].removeValue(forKey:"weeklyCacheReceipt"); object["experienceAwards"] = awards
    object.removeValue(forKey:"weeklyExperienceCache")
    try JSONSerialization.data(withJSONObject:object).write(to:file,options:.atomic)
    let next = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let legacy = try await next.experienceLeaderboard(now:now)
    XCTAssertNil(legacy.entries.first?.timeTypedSeconds); XCTAssertNil(legacy.entries.first?.lastActivityTimestamp)
    _ = try await next.submitResult(request(at:now.addingTimeInterval(1)),accessToken:owner.accessToken,now:now.addingTimeInterval(1))
    let bytes = try Data(contentsOf:file), combined = try await next.experienceLeaderboard(now:now.addingTimeInterval(1))
    XCTAssertGreaterThan(try XCTUnwrap(combined.entries.first?.totalExperience),try XCTUnwrap(legacy.entries.first?.totalExperience))
    XCTAssertNil(combined.entries.first?.timeTypedSeconds); XCTAssertNil(combined.entries.first?.lastActivityTimestamp)
    XCTAssertEqual(try Data(contentsOf:file),bytes)
  }

  func testSnapshotSaveFailureRollsBackAndRetryPreservesBothTimingAndProfileOnReload() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-week-metadata-rollback-\(UUID())")
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
    defer { try? FileManager.default.removeItem(at:directory) }
    let file = directory.appendingPathComponent("store.json"), backup = directory.appendingPathComponent("backup.json")
    let store = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await account(store)
    _ = try await store.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    _ = try await store.updateProfile(.init(selectedBadgeID:"first-finish"),accessToken:owner.accessToken,now:now)
    let input = request(at:now.addingTimeInterval(1))
    try FileManager.default.moveItem(at:file,to:backup)
    try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
    do { _ = try await store.submitResult(input,accessToken:owner.accessToken,now:now.addingTimeInterval(1)); XCTFail("Save must fail") }
    catch { }
    let unchanged = try await store.experienceLeaderboard(now:now.addingTimeInterval(1))
    XCTAssertNil(unchanged.entries.first?.selectedBadge)
    XCTAssertEqual(unchanged.entries.first?.timeTypedSeconds,15.25)
    XCTAssertEqual(unchanged.entries.first?.lastActivityTimestamp,1_800_000_000_875)
    try FileManager.default.removeItem(at:file); try FileManager.default.moveItem(at:backup,to:file)
    _ = try await store.submitResult(input,accessToken:owner.accessToken,now:now.addingTimeInterval(1))
    let reload = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let board = try await reload.experienceLeaderboard(now:now.addingTimeInterval(1))
    XCTAssertEqual(board.entries.first?.selectedBadge?.id,"first-finish")
    XCTAssertEqual(board.entries.first?.timeTypedSeconds,30.5)
    XCTAssertEqual(board.entries.first?.lastActivityTimestamp,1_800_000_001_875)
  }
}
