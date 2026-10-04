import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class WeeklyExperienceReadTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let password = "a secure password"
  private func configuration(_ bonus: Double) -> ExperienceCalculationConfiguration {
    .init(enabled:true,gainMultiplier:1,funboxBonus:0,minimumDailyBonus:bonus,
      maximumDailyBonus:bonus,streakEnabled:false,maximumStreakDays:0,maximumStreakMultiplier:0)
  }
  private func account(_ store: AuthStore, _ name: String) async throws -> AuthSessionResponse {
    try await store.register(.init(email:"\(name.lowercased())@example.com",password:password,displayName:name),now:now)
  }
  private func request(units: Int = 75, at end: Date) -> ResultSubmissionRequest {
    let duration = Double(units) / 5
    return .init(id:UUID(),mode:"words",language:"english",durationSeconds:nil,wordLimit:25,
      wpm:60,rawWpm:60,accuracy:100,errorCount:0,eventCount:units,
      experienceEvidence:.init(characterCounts:[units,0,0,0],scoringUnitBasis:.utf16,
        durationSeconds:duration,afkSeconds:2.25,punctuation:true,numbers:true,modifiers:[]),
      practiceTiming:.init(version:1,terminalEngagedMilliseconds:Int((duration - 2.25) * 1_000),priorAttemptEngagedMilliseconds:0),
      inputMetrics:.init(version:1,correctAttempts:units,totalAttempts:units,creditedUnits:units,retainedUnits:units),
      startedAt:end.addingTimeInterval(-duration),finishedAt:end)
  }
  private func score(_ store: AuthStore, _ session: AuthSessionResponse, units: Int = 75) async throws -> ResultSubmissionResponse {
    _ = try await store.submitResult(request(units:units,at:now.addingTimeInterval(-86_400)),
      accessToken:session.accessToken,now:now.addingTimeInterval(-86_400))
    return try await store.submitResult(request(units:units,at:now),accessToken:session.accessToken,now:now)
  }
  private func json<T: Encodable>(_ value: T) throws -> [String:Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as? [String:Any])
  }

  func testBackdatedClientFinishDoesNotMoveNewRewardIntoPreviousWeek() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await account(store,"Backdated")
    let end = now.addingTimeInterval(-8 * 86_400)
    let submission = ResultSubmissionRequest(id:UUID(),mode:"words",language:"english",
      durationSeconds:nil,wordLimit:25,wpm:60,rawWpm:60,accuracy:100,errorCount:0,eventCount:75,
      startedAt:end.addingTimeInterval(-15),finishedAt:end)
    let receipt = try await store.submitResult(submission,accessToken:owner.accessToken,now:now)
    XCTAssertGreaterThan(receipt.experienceGained,0)
    let current = try await store.experienceLeaderboard(now:now)
    let previous = try await store.experienceLeaderboard(period:"lastWeek",now:now)
    XCTAssertEqual(current.entries.map(\.userID),[owner.user.id])
    XCTAssertTrue(previous.entries.isEmpty)
  }

  func testPublicListAndRankTruncateOnlyAfterAddingFractionalAwardsAndDoNotRewriteLedger() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-weekly-read-\(UUID())")
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
    defer { try? FileManager.default.removeItem(at:directory) }
    let file = directory.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL:file,bcryptCost:4,experienceConfiguration:configuration(0.75))
    let owner = try await account(store,"Owner"), receipt = try await score(store,owner)
    XCTAssertEqual(receipt.experienceGained,52.75)
    let page = try await store.experienceLeaderboard(now:now)
    let rank = try await store.experienceLeaderboardRank(accessToken:owner.accessToken,now:now)
    XCTAssertEqual(page.entries.first?.totalExperience,52)
    XCTAssertEqual(rank.entry?.totalExperience,52)
    let original = try Data(contentsOf:file)
    let loaded = try AuthStore(fileURL:file,bcryptCost:4,experienceConfiguration:configuration(0.75))
    _ = try await loaded.experienceLeaderboard(now:now)
    XCTAssertEqual(try Data(contentsOf:file),original)
    let next = try await loaded.submitResult(request(at:now.addingTimeInterval(30)),
      accessToken:owner.accessToken,now:now.addingTimeInterval(30))
    XCTAssertEqual(next.experienceGained,52)
    let combined = try await loaded.experienceLeaderboard(now:now.addingTimeInterval(30))
    XCTAssertEqual(combined.entries.first?.totalExperience,104)
  }

  func testFriendsKeepGlobalRankAndIndependentFriendsRankAcrossPagesAndPersonalQuery() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,experienceConfiguration:configuration(0.75))
    let owner = try await account(store,"Owner"), friend = try await account(store,"Friend")
    let outsider = try await account(store,"Outsider")
    _ = try await score(store,owner); _ = try await score(store,friend,units:100)
    _ = try await score(store,outsider,units:125)
    _ = try await store.sendConnection(.init(recipientID:friend.user.id),accessToken:owner.accessToken,now:now)
    _ = try await store.acceptConnection(requesterID:owner.user.id,accessToken:friend.accessToken,now:now)
    let first = try await store.friendExperienceLeaderboard(offset:0,limit:1,accessToken:owner.accessToken,now:now)
    let second = try await store.friendExperienceLeaderboard(offset:1,limit:1,accessToken:owner.accessToken,now:now)
    let rank = try await store.friendExperienceLeaderboardRank(accessToken:owner.accessToken,now:now)
    XCTAssertEqual(first.total,2); XCTAssertEqual(first.entries.first?.rank,2)
    XCTAssertEqual(second.entries.first?.rank,3); XCTAssertEqual(rank.entry?.rank,3)
    XCTAssertEqual(try json(XCTUnwrap(first.entries.first))["friendsRank"] as? Int,1)
    XCTAssertEqual(try json(XCTUnwrap(second.entries.first))["friendsRank"] as? Int,2)
    XCTAssertEqual(try json(XCTUnwrap(rank.entry))["friendsRank"] as? Int,2)
    let empty = try await store.experienceLeaderboard(eligibleUserIDs:[],now:now)
    XCTAssertTrue(empty.entries.isEmpty); XCTAssertEqual(empty.total,0)
  }

  func testEqualPublicIntegersStillSortByRawScoreAndGlobalTiesUseUserIdentityNotDisplayName() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,experienceConfiguration:configuration(0.75))
    let first = try await account(store,"InitialA"), second = try await account(store,"InitialB")
    let sessions = [first,second].sorted { $0.user.id.uuidString > $1.user.id.uuidString }
    // Force the alphabetical comparator to disagree with identity ordering.
    _ = try await store.updateProfile(.init(displayName:"Zulu"),accessToken:sessions[0].accessToken,now:now)
    _ = try await store.updateProfile(.init(displayName:"Alpha"),accessToken:sessions[1].accessToken,now:now)
    for owner in sessions { _ = try await score(store,owner) }
    let board = try await store.experienceLeaderboard(now:now)
    XCTAssertEqual(board.entries.map(\.userID),sessions.map { $0.user.id })
    XCTAssertEqual(board.entries.map(\.totalExperience),[52,52])
  }

  func testDifferentFractionsWithTheSamePublicScoreKeepTheirOrderingAndReceipts() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-weekly-sort-\(UUID())")
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
    defer { try? FileManager.default.removeItem(at:directory) }
    let file = directory.appendingPathComponent("store.json")
    let first = try AuthStore(fileURL:file,bcryptCost:4,experienceConfiguration:configuration(0.25))
    let low = try await account(first,"Alpha")
    let lowReceipt = try await score(first,low)
    // Sequential writer cutover, not two writers concurrently updating one file.
    let next = try AuthStore(fileURL:file,bcryptCost:4,experienceConfiguration:configuration(0.75))
    let high = try await account(next,"Zulu")
    let highReceipt = try await score(next,high)
    XCTAssertEqual(lowReceipt.experienceGained,52.25); XCTAssertEqual(highReceipt.experienceGained,52.75)
    let board = try await next.experienceLeaderboard(now:now)
    XCTAssertEqual(board.entries.map(\.totalExperience),[52,52])
    XCTAssertEqual(board.entries.map(\.userID),[high.user.id,low.user.id])
    XCTAssertEqual(highReceipt.weeklyExperienceRank,1)
    _ = try await next.deleteResults(.init(currentPassword:password),accessToken:high.accessToken,now:now)
    let afterDelete = try await next.experienceLeaderboard(now:now)
    XCTAssertEqual(afterDelete.entries,board.entries,"The public projection must not erase reward tombstones")
  }

  func testActualPinnedWeeklyServiceAndLuaNumericProjections() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the read-only pinned source")
    }
    let script = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Scripts/check-source-weekly-xp-read.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
    process.arguments = ["node","--experimental-vm-modules",script.path,reference,"--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus,0,String(decoding:diagnostics,as:UTF8.self))
    struct Fixture: Decodable { let score:Double; let globalScore:Double; let friendsScore:Double; let rankScore:Double }
    struct PartitionFixture: Decodable { let zone:String; let timestamp:Int; let currentKey:Int }
    struct Document: Decodable {
      let referenceCommit:String; let redisVersion:String; let fixtures:[Fixture]
      let partitionFixtures:[PartitionFixture]
    }
    let document = try JSONDecoder().decode(Document.self,from:data)
    XCTAssertEqual(document.referenceCommit,"91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(document.redisVersion,"6.2.6"); XCTAssertEqual(document.fixtures.count,19)
    for fixture in document.fixtures {
      XCTAssertEqual(WeeklyExperiencePublicScore.project(fixture.score),fixture.globalScore,"global \(fixture.score)")
      XCTAssertEqual(WeeklyExperiencePublicScore.project(fixture.score,friendsList:true),fixture.friendsScore,"friends \(fixture.score)")
      XCTAssertEqual(WeeklyExperiencePublicScore.project(fixture.score),fixture.rankScore,"rank \(fixture.score)")
    }
    XCTAssertEqual(document.partitionFixtures.count,12)
    for fixture in document.partitionFixtures {
      let value = try WeeklyExperiencePartition.capture(at:Date(timeIntervalSince1970:Double(fixture.timestamp)/1_000),
        timeZone:XCTUnwrap(TimeZone(identifier:fixture.zone)))
      XCTAssertEqual(value.keyMilliseconds,fixture.currentKey)
    }
  }

  func testTinyPositiveAwardKeepsSourceFriendsListAndRankProjectionDistinct() async throws {
    let tiny = ExperienceCalculationConfiguration(enabled:true,gainMultiplier:0,funboxBonus:0,
      minimumDailyBonus:0.000001,maximumDailyBonus:0.000001,streakEnabled:false,
      maximumStreakDays:0,maximumStreakMultiplier:0)
    let store = try AuthStore(fileURL:nil,bcryptCost:4,experienceConfiguration:tiny)
    let owner = try await account(store,"Tiny"), receipt = try await score(store,owner)
    XCTAssertEqual(receipt.experienceGained,0.000001); XCTAssertEqual(receipt.totalExperience,0)
    let global = try await store.experienceLeaderboard(now:now)
    let friends = try await store.friendExperienceLeaderboard(accessToken:owner.accessToken,now:now)
    let personal = try await store.friendExperienceLeaderboardRank(accessToken:owner.accessToken,now:now)
    XCTAssertEqual(global.entries.first?.totalExperience,9)
    XCTAssertEqual(friends.entries.first?.totalExperience,1)
    XCTAssertEqual(personal.entry?.totalExperience,9)
    XCTAssertEqual(personal.entry?.friendsRank,1)
  }

  func testPublicAndAuthenticatedHTTPExposeTheSameGlobalIdentityAndFriendsOrdinal() async throws {
    let date = Date.now
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development)
    var sessions: [AuthSessionResponse] = []
    for (index,units) in [75,60,125].enumerated() {
      let session = try await store.register(.init(email:"wire\(index)@example.com",password:password,
        displayName:"Wire\(index)"),now:date)
      _ = try await store.submitResult(request(units:units,at:date),accessToken:session.accessToken,now:date)
      sessions.append(session)
    }
    let owner = sessions[0], friend = sessions[1]
    _ = try await store.sendConnection(.init(recipientID:friend.user.id),accessToken:owner.accessToken,now:date)
    _ = try await store.acceptConnection(requesterID:owner.user.id,accessToken:friend.accessToken,now:date)
    let app = try await Application.make(.testing)
    do {
      try configure(app,authStore:store)
      try await app.test(.GET,"v1/leaderboards/experience/friends?limit=1",beforeRequest: { request in
        request.headers.bearerAuthorization = .init(token:owner.accessToken)
      }) { response async throws in
        XCTAssertEqual(response.status,.ok)
        let page = try response.content.decode(ExperienceLeaderboardResponse.self)
        XCTAssertEqual(page.total,2); XCTAssertEqual(page.entries.first?.rank,2)
        XCTAssertEqual(page.entries.first?.friendsRank,1); XCTAssertEqual(page.entries.first?.totalExperience,52)
      }
      for route in ["v1/leaderboards/experience/rank","v1/leaderboards/experience/friends/rank"] {
        try await app.test(.GET,route,beforeRequest: { request in
          request.headers.bearerAuthorization = .init(token:owner.accessToken)
        }) { response async throws in
          XCTAssertEqual(response.status,.ok)
          let value = try response.content.decode(ExperienceLeaderboardRankResponse.self)
          XCTAssertEqual(value.entry?.rank,2); XCTAssertEqual(value.entry?.totalExperience,52)
          XCTAssertEqual(value.entry?.friendsRank,route.contains("friends") ? 1 : nil)
        }
      }
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown(); throw error
    }
  }
}
