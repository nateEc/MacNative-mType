import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class WeeklyExperienceCacheTests: XCTestCase {
  private let now = Date(timeIntervalSince1970:1_800_000_000)
  private let password = "a secure password"
  private func request(at end: Date) -> ResultSubmissionRequest {
    .init(id:UUID(),mode:"words",language:"english",durationSeconds:nil,wordLimit:25,
      wpm:60,rawWpm:60,accuracy:100,errorCount:0,eventCount:75,
      startedAt:end.addingTimeInterval(-15),finishedAt:end)
  }
  private func directory() throws -> URL {
    let value = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-week-cache-\(UUID())")
    try FileManager.default.createDirectory(at:value,withIntermediateDirectories:false)
    return value
  }
  private func account(_ store: AuthStore, name: String = "Cache") async throws -> AuthSessionResponse {
    try await store.register(.init(email:"\(name.lowercased())@example.com",password:password,displayName:name),now:now)
  }
  private func utc() throws -> TimeZone { try XCTUnwrap(TimeZone(identifier:"UTC")) }
  private func configuration(_ days: Double, enabled: Bool = true) -> WeeklyExperienceLeaderboardConfiguration {
    .init(enabled:enabled,expirationTimeInDays:days)
  }
  private func json(_ file: URL) throws -> [String:Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
  }

  func testAlreadyCachedScoreIsNotRequalifiedWhenDeploymentThresholdChanges() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json")
    let first = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await account(first)
    let receipt = try await first.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    let bytes = try Data(contentsOf:file)
    let next = try AuthStore(fileURL:file,bcryptCost:4,minimumLeaderboardTypingSeconds:7_200)
    let board = try await next.experienceLeaderboard(now:now)
    let rank = try await next.experienceLeaderboardRank(accessToken:owner.accessToken,now:now)
    XCTAssertEqual(board.entries.map(\.userID),[owner.user.id])
    XCTAssertEqual(board.entries.first?.totalExperience,receipt.experienceGained)
    XCTAssertNotNil(rank.entry); XCTAssertEqual(rank.eligibility?.isEligible,false)
    XCTAssertEqual(try Data(contentsOf:file),bytes)
  }

  func testDisabledRewardsRemainAccountCreditButNeverBackfillOnEnableOrRetry() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json")
    let disabled = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development,
      weeklyExperienceConfiguration:configuration(15,enabled:false))
    let owner = try await account(disabled), input = request(at:now)
    let first = try await disabled.submitResult(input,accessToken:owner.accessToken,now:now)
    XCTAssertGreaterThan(first.totalExperience,0); XCTAssertNil(first.weeklyExperienceRank)
    do { _ = try await disabled.experienceLeaderboard(now:now); XCTFail("Disabled is not an empty page") }
    catch let error as WeeklyExperienceCacheError { XCTAssertEqual(error,.unavailable) }
    let enabled = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    _ = try await enabled.submitResult(input,accessToken:owner.accessToken,now:now)
    let empty = try await enabled.experienceLeaderboard(now:now)
    XCTAssertTrue(empty.entries.isEmpty)
    let fresh = try await enabled.submitResult(request(at:now.addingTimeInterval(1)),accessToken:owner.accessToken,now:now.addingTimeInterval(1))
    let board = try await enabled.experienceLeaderboard(now:now.addingTimeInterval(1))
    XCTAssertEqual(board.entries.first?.totalExperience,fresh.experienceGained)
    XCTAssertEqual(fresh.totalExperience,first.totalExperience * 2)
  }

  func testImmediateExpiryKeepsRewardAndSourceWriteRankButListAndRankAreEmpty() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development,
      weeklyExperienceConfiguration:configuration(0))
    let owner = try await account(store)
    let receipt = try await store.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    XCTAssertGreaterThan(receipt.totalExperience,0); XCTAssertEqual(receipt.weeklyExperienceRank,1)
    let board = try await store.experienceLeaderboard(now:now)
    let rank = try await store.experienceLeaderboardRank(accessToken:owner.accessToken,now:now)
    XCTAssertTrue(board.entries.isEmpty); XCTAssertNil(rank.entry)
  }

  func testDisableHidesSavedSubmissionRankButDoesNotErasePreviouslyCachedScore() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json")
    let first = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await account(first), input = request(at:now)
    let original = try await first.submitResult(input,accessToken:owner.accessToken,now:now)
    let disabled = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development,
      weeklyExperienceConfiguration:configuration(15,enabled:false))
    let hidden = try await disabled.submitResult(input,accessToken:owner.accessToken,now:now)
    XCTAssertNil(hidden.weeklyExperienceRank); XCTAssertEqual(hidden.totalExperience,original.totalExperience)
    let enabled = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let board = try await enabled.experienceLeaderboard(now:now)
    XCTAssertEqual(board.entries.first?.totalExperience,original.experienceGained)
  }

  func testDisabledOptOutDoesNotPurgeUnderlyingCacheButVisibilityStillRespectsOptOut() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json")
    let first = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await account(first)
    _ = try await first.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    let disabled = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development,
      weeklyExperienceConfiguration:configuration(15,enabled:false))
    _ = try await disabled.updateProfile(.init(leaderboardOptedOut:true),accessToken:owner.accessToken,now:now)
    let enabled = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let invisible = try await enabled.experienceLeaderboard(now:now)
    XCTAssertTrue(invisible.entries.isEmpty,"Typebar's explicit privacy filter is retained")
    _ = try await enabled.updateProfile(.init(leaderboardOptedOut:false),accessToken:owner.accessToken,now:now)
    let retained = try await enabled.experienceLeaderboard(now:now)
    XCTAssertEqual(retained.entries.map(\.userID),[owner.user.id])
  }

  func testExpiryBoundaryIsWholeSecondAndDoesNotResurrectFromLedgerOrRewriteOnRead() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), zone = try utc()
    let partition = try WeeklyExperiencePartition.capture(at:now,timeZone:zone)
    let days = (now.timeIntervalSince1970 * 1_000 - Double(partition.keyMilliseconds) + 1_500.875) / 86_400_000
    let config = configuration(days), deadline = try config.expiration(key:partition.keyMilliseconds)
    let store = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development,
      weeklyExperienceTimeZone:zone,weeklyExperienceConfiguration:config)
    let owner = try await account(store), input = request(at:now)
    _ = try await store.submitResult(input,accessToken:owner.accessToken,now:now)
    let bytes = try Data(contentsOf:file)
    let before = try await store.experienceLeaderboard(now:Date(timeIntervalSince1970:Double(deadline)/1_000 - 0.001))
    let after = try await store.experienceLeaderboard(now:Date(timeIntervalSince1970:Double(deadline)/1_000))
    let clockBack = try await store.experienceLeaderboard(now:now)
    XCTAssertEqual(before.entries.count,1); XCTAssertTrue(after.entries.isEmpty)
    XCTAssertTrue(clockBack.entries.isEmpty,"Eviction is permanent within this actor")
    XCTAssertEqual(try Data(contentsOf:file),bytes)
    _ = try await store.submitResult(input,accessToken:owner.accessToken,now:Date(timeIntervalSince1970:Double(deadline)/1_000))
    let reloaded = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development,
      weeklyExperienceTimeZone:zone,weeklyExperienceConfiguration:configuration(30))
    let past = try await reloaded.experienceLeaderboard(now:Date(timeIntervalSince1970:Double(deadline)/1_000))
    XCTAssertTrue(past.entries.isEmpty,"Changing retention does not renew saved deadlines")
  }

  func testSingleMemberResetsExpiryButMultipleMembersRetainItAcrossConfigurationChanges() throws {
    let partition = try WeeklyExperiencePartition.capture(at:now,timeZone:utc())
    let first = UUID(), second = UUID(); var cache = WeeklyExperienceCache()
    _ = try cache.add(userID:first,displayName:"First",xp:10,seconds:2,partition:partition,configuration:configuration(14),now:now)
    _ = try cache.add(userID:first,displayName:"First",xp:5,seconds:3,partition:partition,configuration:configuration(20),now:now)
    XCTAssertEqual(cache.buckets.first?.expiresAtMilliseconds,try configuration(20).expiration(key:partition.keyMilliseconds))
    _ = try cache.add(userID:second,displayName:"Second",xp:3,seconds:4,partition:partition,configuration:configuration(10),now:now)
    _ = try cache.add(userID:second,displayName:"Second",xp:7,seconds:5,partition:partition,configuration:configuration(1),now:now)
    XCTAssertEqual(cache.buckets.first?.expiresAtMilliseconds,try configuration(20).expiration(key:partition.keyMilliseconds))
    cache.purge(userID:first)
    _ = try cache.add(userID:second,displayName:"Second",xp:1,seconds:1,partition:partition,configuration:configuration(15),now:now)
    XCTAssertEqual(cache.buckets.first?.expiresAtMilliseconds,try configuration(15).expiration(key:partition.keyMilliseconds))
    XCTAssertEqual(cache.buckets.first?.entries.first?.score,11)
    XCTAssertEqual(cache.buckets.first?.entries.first?.timeTypedSeconds,10)
  }

  func testOptOutPurgesAndOptInDoesNotReplayOldManagedAwards() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await account(store), input = request(at:now)
    _ = try await store.submitResult(input,accessToken:owner.accessToken,now:now)
    _ = try await store.updateProfile(.init(leaderboardOptedOut:true),accessToken:owner.accessToken,now:now)
    _ = try await store.updateProfile(.init(leaderboardOptedOut:false),accessToken:owner.accessToken,now:now)
    _ = try await store.submitResult(input,accessToken:owner.accessToken,now:now)
    let empty = try await store.experienceLeaderboard(now:now)
    XCTAssertTrue(empty.entries.isEmpty)
    let next = try await store.submitResult(request(at:now.addingTimeInterval(1)),accessToken:owner.accessToken,now:now.addingTimeInterval(1))
    let board = try await store.experienceLeaderboard(now:now.addingTimeInterval(1))
    XCTAssertEqual(board.entries.first?.totalExperience,next.experienceGained)
  }

  func testCachedNameChangesOnlyWithNextAcceptedEntryWhileHistoryDeletionKeepsScore() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await account(store)
    _ = try await store.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    _ = try await store.updateProfile(.init(displayName:"Changed"),accessToken:owner.accessToken,now:now)
    _ = try await store.deleteResults(.init(currentPassword:password),accessToken:owner.accessToken,now:now)
    let old = try await store.experienceLeaderboard(now:now)
    XCTAssertEqual(old.entries.first?.displayName,"Cache")
    _ = try await store.submitResult(request(at:now.addingTimeInterval(1)),accessToken:owner.accessToken,now:now.addingTimeInterval(1))
    let updated = try await store.experienceLeaderboard(now:now.addingTimeInterval(1))
    XCTAssertEqual(updated.entries.first?.displayName,"Changed")
    XCTAssertEqual(updated.entries.first?.totalExperience,old.entries.first.map { $0.totalExperience * 2 })
  }

  func testMissingCacheCannotBeRebuiltFromManagedAwardsAndExplicitCorruptionDoesNotWrite() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await account(store)
    _ = try await store.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    let original = try json(file)
    for mutation in 0..<8 {
      var object = original
      if mutation == 0 { object.removeValue(forKey:"weeklyExperienceCache") }
      else if mutation == 1 { object["weeklyExperienceCache"] = NSNull() }
      else {
        var cache = try XCTUnwrap(object["weeklyExperienceCache"] as? [String:Any])
        var buckets = try XCTUnwrap(cache["buckets"] as? [[String:Any]])
        switch mutation {
        case 2: cache["version"] = 99
        case 3: buckets.append(buckets[0])
        case 4: buckets[0]["expiresAtMilliseconds"] = 1
        case 5: buckets[0]["expirationTimeInDays"] = -1
        default:
          var entries = try XCTUnwrap(buckets[0]["entries"] as? [[String:Any]])
          if mutation == 6 { entries.append(entries[0]) }
          else { entries[0]["score"] = 9_007_199_254_740_991 }
          buckets[0]["entries"] = entries
        }
        cache["buckets"] = buckets; object["weeklyExperienceCache"] = cache
      }
      let bytes = try JSONSerialization.data(withJSONObject:object); try bytes.write(to:file,options:.atomic)
      XCTAssertThrowsError(try AuthStore(fileURL:file,bcryptCost:4))
      XCTAssertEqual(try Data(contentsOf:file),bytes)
    }
  }

  func testPersistenceFailureRollsBackCacheAndRewardBeforeRetry() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), backup = dir.appendingPathComponent("backup.json")
    let store = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await account(store), input = request(at:now)
    try FileManager.default.moveItem(at:file,to:backup)
    try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
    do { _ = try await store.submitResult(input,accessToken:owner.accessToken,now:now); XCTFail("Rename must fail") }
    catch { }
    let empty = try await store.experienceLeaderboard(now:now)
    XCTAssertTrue(empty.entries.isEmpty)
    try FileManager.default.removeItem(at:file); try FileManager.default.moveItem(at:backup,to:file)
    let receipt = try await store.submitResult(input,accessToken:owner.accessToken,now:now)
    let reload = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let board = try await reload.experienceLeaderboard(now:now)
    XCTAssertEqual(board.entries.first?.totalExperience,receipt.experienceGained)
  }

  func testDisabledHTTPListsAndRanksReturn404WithoutDisablingResultAcceptance() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,weeklyExperienceConfiguration:configuration(15,enabled:false))
    let owner = try await store.register(.init(email:"http-cache@example.com",password:password,displayName:"HTTP Cache"))
    let app = try await Application.make(.testing)
    do {
      try configure(app,authStore:store)
      for suffix in ["","/friends","/rank","/friends/rank"] {
        try await app.test(.GET,"v1/leaderboards/experience"+suffix,beforeRequest: { request in
          request.headers.bearerAuthorization = .init(token:owner.accessToken)
        }) { response async throws in
          XCTAssertEqual(response.status,.notFound)
          XCTAssertTrue(response.body.string.contains("disabled"))
        }
      }
      let input = request(at:Date.now)
      try await app.test(.POST,"v1/results",beforeRequest: { request in
        request.headers.bearerAuthorization = .init(token:owner.accessToken)
        try request.content.encode(input)
      }) { response async throws in
        XCTAssertEqual(response.status,.ok)
        let receipt = try response.content.decode(ResultSubmissionResponse.self)
        XCTAssertTrue(receipt.accepted); XCTAssertGreaterThan(receipt.totalExperience,0)
        XCTAssertNil(receipt.weeklyExperienceRank)
      }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }

  func testConfigurationAcceptsZeroAndFractionalDaysButRejectsInvalidValues() throws {
    for days in [0,0.5,15,100] { try configuration(days).validate() }
    for days in [-1,Double.nan,.infinity,9_007_199_254_740_991] {
      XCTAssertThrowsError(try configuration(days).validate())
    }
    for text in ["{}","null","{\"enabled\":true,\"expirationTimeInDays\":-1}",
      "{\"enabled\":\"true\",\"expirationTimeInDays\":15}"] {
      XCTAssertThrowsError(try WeeklyExperienceLeaderboardConfiguration.fromJSON(text))
    }
  }

  func testActualPinnedCompleteServiceAndLuaCacheLifecycle() throws {
    guard let root = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the read-only pinned source")
    }
    let script = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Scripts/check-source-weekly-xp-read.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
    process.arguments = ["node","--experimental-vm-modules",script.path,root,"--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus,0,String(decoding:diagnostics,as:UTF8.self))
    struct Entry: Decodable { let uid:UUID; let name:String; let score:Double; let timeTypedSeconds:Double; let lastActivityMilliseconds:Int }
    struct Operation: Decodable {
      let action:String; let uid:UUID; let xp:Double?; let seconds:Double?; let name:String?
      let days:Double; let enabled:Bool; let timestamp:Int; let rank:Int?
      let expiresAtMilliseconds:Int?; let entries:[Entry]
    }
    struct Fixture: Decodable { let label:String; let key:Int; let operations:[Operation] }
    struct Document: Decodable { let referenceCommit:String; let redisVersion:String; let cacheFixtures:[Fixture] }
    let document = try JSONDecoder().decode(Document.self,from:data)
    XCTAssertEqual(document.referenceCommit,"91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(document.redisVersion,"6.2.6")
    XCTAssertEqual(document.cacheFixtures.reduce(0,{ $0 + $1.operations.count }),12)
    for fixture in document.cacheFixtures {
      var cache = WeeklyExperienceCache()
      for operation in fixture.operations {
        let date = Date(timeIntervalSince1970:Double(operation.timestamp)/1_000)
        let partition = try WeeklyExperiencePartition.capture(at:date,timeZone:utc())
        XCTAssertEqual(partition.keyMilliseconds,fixture.key)
        if operation.action == "add", operation.enabled {
          let rank = try cache.add(userID:operation.uid,displayName:XCTUnwrap(operation.name),
            xp:XCTUnwrap(operation.xp),seconds:XCTUnwrap(operation.seconds),partition:partition,
            configuration:configuration(operation.days),now:date)
          XCTAssertEqual(rank,operation.rank)
        } else if operation.action == "purge", operation.enabled { cache.purge(userID:operation.uid) }
        let bucket = cache.buckets.first
        XCTAssertEqual(bucket?.expiresAtMilliseconds,operation.expiresAtMilliseconds,fixture.label)
        XCTAssertEqual(Set(bucket?.entries.map(\.userID) ?? []),Set(operation.entries.map(\.uid)))
        for expected in operation.entries {
          let actual = try XCTUnwrap(bucket?.entries.first { $0.userID == expected.uid })
          XCTAssertEqual(actual.score,expected.score); XCTAssertEqual(actual.displayName,expected.name)
          XCTAssertEqual(actual.timeTypedSeconds,expected.timeTypedSeconds)
          XCTAssertEqual(actual.lastActivityMilliseconds,expected.lastActivityMilliseconds)
        }
      }
    }
  }
}
