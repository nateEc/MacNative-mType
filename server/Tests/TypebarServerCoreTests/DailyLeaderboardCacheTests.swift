import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class DailyLeaderboardCacheTests: XCTestCase {
  private let now = Date(timeIntervalSince1970:1_800_000_000)
  private let password = "a secure password"
  private let query = LeaderboardQuery(mode:"words",language:"english",period:"day",wordLimit:25)
  private func request(at end: Date, wpm: Int = 60) -> ResultSubmissionRequest {
    .init(id:UUID(),mode:"words",language:"english",durationSeconds:nil,wordLimit:25,
      wpm:wpm,rawWpm:wpm,accuracy:100,errorCount:0,eventCount:75,
      startedAt:end.addingTimeInterval(-900 / Double(wpm)),finishedAt:end)
  }
  private func store(file: URL? = nil, config: DailyLeaderboardConfiguration = .typebarDefault) throws -> AuthStore {
    try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development,dailyLeaderboardConfiguration:config)
  }
  private func account(_ store: AuthStore, name: String = "Daily") async throws -> AuthSessionResponse {
    try await store.register(.init(email:"\(name.lowercased())@example.com",password:password,displayName:name),now:now)
  }
  func testEqualSpeedAndAccuracyKeepEarlierResultSnapshotNotMostRecentHistory() async throws {
    let store = try store(), owner = try await account(store)
    let earlier = request(at:now), later = request(at:now.addingTimeInterval(2))
    let first = try await store.submitResult(earlier,accessToken:owner.accessToken,now:now)
    let second = try await store.submitResult(later,accessToken:owner.accessToken,now:now.addingTimeInterval(2))
    let board = try await store.leaderboard(query,now:now.addingTimeInterval(2))
    XCTAssertEqual(board.entries.first?.id,earlier.id)
    XCTAssertEqual(first.dailyLeaderboardRank,1)
    XCTAssertNil(second.dailyLeaderboardRank,"Unchanged GT write does not report a new rank")
  }
  func testAcceptedDayAndFrozenNameSurviveHistoryDeletion() async throws {
    let store = try store(), owner = try await account(store)
    let input = request(at:now.addingTimeInterval(-86_400))
    let receipt = try await store.submitResult(input,accessToken:owner.accessToken,now:now)
    XCTAssertEqual(receipt.dailyLeaderboardRank,1)
    _ = try await store.updateProfile(.init(displayName:"Changed"),accessToken:owner.accessToken,now:now)
    _ = try await store.deleteResults(.init(currentPassword:password),accessToken:owner.accessToken,now:now)
    let board = try await store.leaderboard(query,now:now)
    XCTAssertEqual(board.entries.map(\.id),[input.id])
    XCTAssertEqual(board.entries.first?.displayName,"Daily")
    XCTAssertEqual(board.entries.first?.finishedAt,now,"Cached timestamp is server-authoritative; client history is separate")
  }
  private func directory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-daily-cache-\(UUID())")
    try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:false); return dir
  }
  private func configuration(enabled: Bool = true, days: Double = 2, capacity: Int = 1_000) -> DailyLeaderboardConfiguration {
    .init(enabled:enabled,expirationTimeInDays:days,maxResults:capacity,validModeRules:DailyLeaderboardConfiguration.typebarDefault.validModeRules)
  }
  func testRetryRetainsReceiptAcrossRestartAndHistoryDeletionWithoutResurrection() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), first = try store(file:file)
    let owner = try await account(first), input = request(at:now)
    let receipt = try await first.submitResult(input,accessToken:owner.accessToken,now:now)
    _ = try await first.deleteResults(.init(currentPassword:password),accessToken:owner.accessToken,now:now)
    let bytes = try Data(contentsOf:file), loaded = try store(file:file)
    let retry = try await loaded.submitResult(input,accessToken:owner.accessToken,now:now.addingTimeInterval(3))
    XCTAssertEqual(retry.dailyLeaderboardRank,receipt.dailyLeaderboardRank)
    XCTAssertEqual(try Data(contentsOf:file),bytes)
    let expired = try await loaded.leaderboard(query,now:now.addingTimeInterval(3 * 86_400))
    XCTAssertTrue(expired.entries.isEmpty)
    _ = try await loaded.submitResult(input,accessToken:owner.accessToken,now:now.addingTimeInterval(3 * 86_400))
    let stillEmpty = try await loaded.leaderboard(query,now:now.addingTimeInterval(3 * 86_400))
    XCTAssertTrue(stillEmpty.entries.isEmpty)
  }
  func testDisabledAndInvalidModeNeverBackfillOnEnableOrRetry() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json")
    let disabled = try store(file:file,config:configuration(enabled:false)), owner = try await account(disabled)
    let input = request(at:now)
    let receipt = try await disabled.submitResult(input,accessToken:owner.accessToken,now:now)
    XCTAssertNil(receipt.dailyLeaderboardRank)
    let enabled = try store(file:file)
    _ = try await enabled.submitResult(input,accessToken:owner.accessToken,now:now)
    let empty = try await enabled.leaderboard(query,now:now); XCTAssertTrue(empty.entries.isEmpty)
    let restricted = try store(file:file,config:.init(enabled:true,expirationTimeInDays:2,maxResults:20,
      validModeRules:[.init(language:"english",mode:"time",mode2:"60")]))
    let second = request(at:now.addingTimeInterval(1))
    _ = try await restricted.submitResult(second,accessToken:owner.accessToken,now:now.addingTimeInterval(1))
    let again = try store(file:file)
    _ = try await again.submitResult(second,accessToken:owner.accessToken,now:now.addingTimeInterval(2))
    let stillEmpty = try await again.leaderboard(query,now:now); XCTAssertTrue(stillEmpty.entries.isEmpty)
  }
  func testEvictedAndImmediatelyExpiredAttemptsReportNoRankButKeepAccountReward() async throws {
    for config in [configuration(days:0),configuration(capacity:0)] {
      let store = try store(config:config), owner = try await account(store)
      let receipt = try await store.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
      XCTAssertNil(receipt.dailyLeaderboardRank); XCTAssertGreaterThan(receipt.totalExperience,0)
      let empty = try await store.leaderboard(query,now:now); XCTAssertTrue(empty.entries.isEmpty)
    }
    let store = try store(config:configuration(capacity:1)), first = try await account(store,name:"First")
    let second = try await account(store,name:"Second")
    _ = try await store.submitResult(request(at:now,wpm:80),accessToken:first.accessToken,now:now)
    let low = try await store.submitResult(request(at:now,wpm:70),accessToken:second.accessToken,now:now)
    XCTAssertNil(low.dailyLeaderboardRank)
    let high = try await store.submitResult(request(at:now,wpm:90),accessToken:second.accessToken,now:now)
    XCTAssertEqual(high.dailyLeaderboardRank,1)
    let page = try await store.leaderboard(query,now:now); XCTAssertEqual(page.entries.map(\.userID),[second.user.id])
  }
  func testCachedAdmissionIsNotRequalifiedAgainstNewThresholdAndReadsDoNotWrite() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), first = try store(file:file)
    let owner = try await account(first)
    _ = try await first.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    let bytes = try Data(contentsOf:file)
    let next = try AuthStore(fileURL:file,bcryptCost:4,minimumLeaderboardTypingSeconds:7_200,
      dailyLeaderboardConfiguration:.typebarDefault)
    let rank = try await next.leaderboardRank(query,accessToken:owner.accessToken,now:now)
    XCTAssertNotNil(rank.entry); XCTAssertEqual(rank.eligibility?.isEligible,false)
    XCTAssertEqual(try Data(contentsOf:file),bytes)
  }
  func testOptOutSuspensionAndResetPurgeWithoutHistoryResurrection() async throws {
    let store = try store(), owner = try await account(store)
    _ = try await store.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    _ = try await store.updateProfile(.init(leaderboardOptedOut:true),accessToken:owner.accessToken,now:now)
    _ = try await store.updateProfile(.init(leaderboardOptedOut:false),accessToken:owner.accessToken,now:now)
    var board = try await store.leaderboard(query,now:now); XCTAssertTrue(board.entries.isEmpty)
    _ = try await store.submitResult(request(at:now.addingTimeInterval(1)),accessToken:owner.accessToken,now:now.addingTimeInterval(1))
    _ = try await store.setAccountSuspended(userID:owner.user.id,suspended:true,now:now.addingTimeInterval(2))
    _ = try await store.setAccountSuspended(userID:owner.user.id,suspended:false,now:now.addingTimeInterval(3))
    board = try await store.leaderboard(query,now:now.addingTimeInterval(3)); XCTAssertTrue(board.entries.isEmpty)
    _ = try await store.submitResult(request(at:now.addingTimeInterval(4)),accessToken:owner.accessToken,now:now.addingTimeInterval(4))
    _ = try await store.resetAccount(.init(currentPassword:password),accessToken:owner.accessToken,now:now.addingTimeInterval(5))
    board = try await store.leaderboard(query,now:now.addingTimeInterval(5)); XCTAssertTrue(board.entries.isEmpty)
  }
  func testCommitFailureRollsBackDailyCacheAndFrozenReceipt() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), backup = dir.appendingPathComponent("backup.json")
    let store = try store(file:file), owner = try await account(store), input = request(at:now)
    try FileManager.default.moveItem(at:file,to:backup)
    try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
    do { _ = try await store.submitResult(input,accessToken:owner.accessToken,now:now); XCTFail("Real rename must fail") }
    catch { }
    let empty = try await store.leaderboard(query,now:now); XCTAssertTrue(empty.entries.isEmpty)
    try FileManager.default.removeItem(at:file); try FileManager.default.moveItem(at:backup,to:file)
    _ = try await store.submitResult(input,accessToken:owner.accessToken,now:now)
    let next = try self.store(file:file), board = try await next.leaderboard(query,now:now)
    XCTAssertEqual(board.entries.map(\.id),[input.id])
  }
  func testManagedMissingCacheAndCorruptEntryRejectWithoutWriting() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), first = try store(file:file), owner = try await account(first)
    _ = try await first.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
    for mutation in 0..<5 {
      var object = original
      if mutation == 0 { object.removeValue(forKey:"dailyLeaderboardCache") }
      else if mutation == 1 { object["dailyLeaderboardCache"] = NSNull() }
      else {
        var cache = try XCTUnwrap(object["dailyLeaderboardCache"] as? [String:Any])
        var buckets = try XCTUnwrap(cache["buckets"] as? [[String:Any]])
        if mutation == 2 { cache["version"] = 99 }
        else if mutation == 3 { buckets.append(buckets[0]) }
        else {
          var entries = try XCTUnwrap(buckets[0]["entries"] as? [[String:Any]])
          entries[0]["displayName"] = "Tampered"; buckets[0]["entries"] = entries
        }
        cache["buckets"] = buckets; object["dailyLeaderboardCache"] = cache
      }
      let bytes = try JSONSerialization.data(withJSONObject:object); try bytes.write(to:file,options:.atomic)
      XCTAssertThrowsError(try store(file:file)); XCTAssertEqual(try Data(contentsOf:file),bytes)
    }
  }
  func testLegacyHistoryIsNotBackfilledAndManagedResultsCannotReenterLegacyDailyQueries() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), legacy = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await account(legacy)
    _ = try await legacy.submitResult(request(at:now,wpm:80),accessToken:owner.accessToken,now:now)
    let upgraded = try store(file:file)
    let empty = try await upgraded.leaderboard(query,now:now); XCTAssertTrue(empty.entries.isEmpty)
    _ = try await upgraded.submitResult(request(at:now.addingTimeInterval(1),wpm:100),accessToken:owner.accessToken,now:now.addingTimeInterval(1))
    let rollback = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let old = try await rollback.leaderboard(query,now:now.addingTimeInterval(1))
    XCTAssertEqual(old.entries.map(\.wpm),[80],"Managed cache results do not become inferred historical rows")
    let all = try await rollback.leaderboard(.init(period:"all"),now:now.addingTimeInterval(1))
    XCTAssertEqual(all.entries.map(\.wpm),[100],"All-time history behavior remains available")
  }
  func testHTTPDisabledDailyListsAndRanksReturn404AndAllTimeRemainsAvailable() async throws {
    let store = try store(config:configuration(enabled:false))
    let owner = try await store.register(.init(email:"http-daily@example.com",password:password,displayName:"HTTP Daily"))
    let app = try await Application.make(.testing)
    do {
      try configure(app,authStore:store)
      for suffix in ["","/friends","/rank","/friends/rank"] {
        try await app.test(.GET,"v1/leaderboards"+suffix+"?period=day",beforeRequest: { request in
          request.headers.bearerAuthorization = .init(token:owner.accessToken)
        }) { response async throws in XCTAssertEqual(response.status,.notFound) }
      }
      try await app.test(.GET,"v1/leaderboards?period=all") { response async throws in XCTAssertEqual(response.status,.ok) }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
  func testConfigurationBoundaryAndUTCKeyAreIndependentOfLocalCalendar() throws {
    for days in [0,0.5,2] { try configuration(days:days,capacity:0).validate() }
    for days in [-1,Double.nan,.infinity,9_007_199_254_740_991] { XCTAssertThrowsError(try configuration(days:days).validate()) }
    for capacity in [-1,1_000_001] { XCTAssertThrowsError(try configuration(capacity:capacity).validate()) }
    for input in ["{}","null","{\"enabled\":true}"] { XCTAssertThrowsError(try DailyLeaderboardConfiguration.fromJSON(input)) }
    let key = try DailyLeaderboardCache.key(at:now)
    XCTAssertEqual(key,1_799_971_200_000)
    XCTAssertEqual(try DailyLeaderboardCache.key(at:Date(timeIntervalSince1970:Double(key)/1_000-0.001)),key-86_400_000)
    XCTAssertEqual(try DailyLeaderboardCache.key(at:Date(timeIntervalSince1970:Double(key)/1_000)),key)
  }
  func testCompleteNativeExperienceReportUsesServerSecondAndPreciseAccuracy() async throws {
    let store = try store(), owner = try await account(store)
    let clientFinish = now.addingTimeInterval(-60), accepted = now.addingTimeInterval(0.875)
    let input = ResultSubmissionRequest(id:UUID(),mode:"words",language:"english",durationSeconds:nil,
      wordLimit:25,wpm:60,rawWpm:60,accuracy:100,errorCount:0,eventCount:75,
      experienceEvidence:.init(characterCounts:[75,0,0,0],scoringUnitBasis:.utf16,durationSeconds:15,
        afkSeconds:0,punctuation:false,numbers:false,modifiers:[]),
      practiceTiming:.init(version:1,terminalEngagedMilliseconds:15_000,priorAttemptEngagedMilliseconds:0),
      inputMetrics:.init(version:1,correctAttempts:75,totalAttempts:75,creditedUnits:75,retainedUnits:75),
      startedAt:clientFinish.addingTimeInterval(-15),finishedAt:clientFinish)
    let receipt = try await store.submitResult(input,accessToken:owner.accessToken,now:accepted)
    XCTAssertEqual(receipt.dailyLeaderboardRank,1)
    let board = try await store.leaderboard(query,now:accepted)
    XCTAssertEqual(board.entries.first?.finishedAt,now)
    XCTAssertEqual(board.entries.first?.preciseAccuracy,100)
    let history = try await store.results(.init(),credential:.accessToken(owner.accessToken),now:accepted)
    XCTAssertEqual(history.results.first?.finishedAt,clientFinish)
  }
  func testYesterdayCacheAndGlobalRankDoNotDependOnHistoryOrFriendsPagination() async throws {
    let store = try store(), owner = try await account(store,name:"Owner"), outsider = try await account(store,name:"Outsider")
    _ = try await store.submitResult(request(at:now,wpm:80),accessToken:outsider.accessToken,now:now)
    _ = try await store.submitResult(request(at:now,wpm:60),accessToken:owner.accessToken,now:now)
    let rank = try await store.friendLeaderboardRank(query,accessToken:owner.accessToken,now:now)
    XCTAssertEqual(rank.entry?.rank,2,"Cached friend entry retains its global rank")
    XCTAssertEqual(rank.entry?.friendsRank,1)
    let page = try await store.friendLeaderboard(.init(mode:"words",language:"english",period:"day",wordLimit:25,limit:1),
      accessToken:owner.accessToken,now:now)
    XCTAssertEqual(page.total,1); XCTAssertEqual(page.entries.first?.rank,2)
    XCTAssertEqual(page.entries.first?.friendsRank,1)
    let tomorrow = now.addingTimeInterval(86_400)
    let today = try await store.leaderboard(query,now:tomorrow); XCTAssertTrue(today.entries.isEmpty)
    let yesterday = try await store.leaderboard(.init(mode:"words",language:"english",period:"yesterday",wordLimit:25),now:tomorrow)
    XCTAssertEqual(yesterday.entries.map(\.wpm),[80,60])
  }
  func testDisplayNameRemediationHidesCachedPublicRow() async throws {
    let store = try store(), owner = try await account(store), input = request(at:now)
    _ = try await store.submitResult(input,accessToken:owner.accessToken,now:now)
    _ = try await store.setDisplayNameChangeRequired(userID:owner.user.id,required:true)
    let board = try await store.leaderboard(query,now:now)
    XCTAssertTrue(board.entries.isEmpty)
    let rank = try await store.leaderboardRank(query,accessToken:owner.accessToken,now:now)
    XCTAssertNil(rank.entry)
  }
  func testCompletePinnedDailyServiceLuaAndScoreDifferential() throws {
    guard let root = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned read-only source and isolated Redis")
    }
    let script = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Scripts/check-source-daily-cache.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
    process.arguments = ["node","--experimental-vm-modules",script.path,root,"--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus,0,String(decoding:diagnostics,as:UTF8.self))
    struct Score: Decodable { let wpm:Double; let acc:Double; let timestamp:Double; let score:Double }
    struct Rule: Decodable { let pattern:String; let text:String; let matches:Bool }
    struct Entry: Decodable { let uid:UUID; let name:String; let wpm:Int; let timestamp:Int; let score:Double }
    struct Operation: Decodable {
      let action:String; let uid:UUID; let name:String?; let wpm:Int?; let days:Double?; let capacity:Int?
      let enabled:Bool; let timestamp:Int; let acceptedMilliseconds:Int; let rank:Int?
      let entries:[Entry]; let expiresAtMilliseconds:Int?
    }
    struct Fixture: Decodable { let label:String; let key:Int; let operations:[Operation] }
    struct Document: Decodable {
      let referenceCommit:String; let redisVersion:String; let scoreFixtures:[Score]; let ruleFixtures:[Rule]; let fixtures:[Fixture]
    }
    let document = try JSONDecoder().decode(Document.self,from:bytes)
    XCTAssertEqual(document.referenceCommit,"91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(document.redisVersion,"6.2.6"); XCTAssertEqual(document.scoreFixtures.count,120)
    XCTAssertEqual(document.ruleFixtures.count,36)
    XCTAssertEqual(document.fixtures.reduce(0) { $0 + $1.operations.count },16)
    for fixture in document.scoreFixtures {
      XCTAssertEqual(DailyLeaderboardCache.Entry.score(wpm:fixture.wpm,accuracy:fixture.acc,timestamp:fixture.timestamp),fixture.score)
    }
    for fixture in document.ruleFixtures {
      let rule = DailyLeaderboardModeRule(language:fixture.pattern,mode:"words",mode2:"25")
      XCTAssertEqual(rule.matches(language:fixture.text,mode:"words",mode2:"25"),fixture.matches)
    }
    for fixture in document.fixtures {
      var cache = DailyLeaderboardCache()
      for op in fixture.operations {
        let date = Date(timeIntervalSince1970:Double(op.acceptedMilliseconds)/1_000)
        XCTAssertEqual(try DailyLeaderboardCache.key(at:date),fixture.key)
        if op.action == "add" {
          let config = configuration(enabled:op.enabled,days:op.days ?? 2,capacity:op.capacity ?? 3)
          let entry = DailyLeaderboardCache.Entry(userID:op.uid,resultID:UUID(),displayName:try XCTUnwrap(op.name),
            language:"english",mode:"words",mode2:"25",wpm:try XCTUnwrap(op.wpm),accuracy:100,preciseAccuracy:nil,
            consistency:0,finishedAt:Date(timeIntervalSince1970:Double(op.timestamp)/1_000),
            profileSnapshot:.init(version:1,selectedBadge:nil,discordAvatar:nil))
          XCTAssertEqual(try cache.add(entry,configuration:config,now:date),op.rank,fixture.label)
        } else if op.enabled { cache.purge(userID:op.uid) }
        let bucket = cache.buckets.first
        XCTAssertEqual(bucket?.expiresAtMilliseconds,op.expiresAtMilliseconds,fixture.label)
        XCTAssertEqual(DailyLeaderboardCache.ordered(bucket?.entries ?? []).map(\.userID),op.entries.map(\.uid))
        for expected in op.entries {
          let actual = try XCTUnwrap(bucket?.entries.first { $0.userID == expected.uid })
          XCTAssertEqual(actual.score,expected.score); XCTAssertEqual(actual.displayName,expected.name)
          XCTAssertEqual(actual.finishedAt.timeIntervalSince1970*1_000,Double(expected.timestamp))
        }
      }
    }
  }
}
