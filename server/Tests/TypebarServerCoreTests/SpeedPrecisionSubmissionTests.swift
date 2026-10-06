import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class SpeedPrecisionSubmissionTests: XCTestCase {
  private let now = Date(timeIntervalSince1970:1_800_000_000)
  private func request(speed: Double, id: UUID = UUID(), finishedOffset: Double = 0) throws -> ResultSubmissionRequest {
    let end = now.addingTimeInterval(finishedOffset)
    let input = ResultSubmissionRequest(id:id,mode:"words",language:"english",durationSeconds:nil,
      wordLimit:25,wpm:Int(speed.rounded()),rawWpm:Int(speed.rounded()),accuracy:100,
      errorCount:0,eventCount:75,startedAt:end.addingTimeInterval(-900 / speed),finishedAt:end)
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(input)) as? [String:Any])
    json["speedPrecision"] = ["version":1,"wpm":speed,"rawWpm":speed]
    json["startedAtReferenceTime"] = input.startedAt.timeIntervalSinceReferenceDate
    json["finishedAtReferenceTime"] = input.finishedAt.timeIntervalSinceReferenceDate
    return try JSONDecoder().decode(ResultSubmissionRequest.self,from:JSONSerialization.data(withJSONObject:json))
  }
  func testPublicBestAndLeaderboardPreferHigherFractionDespiteEarlierFinish() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await store.register(.init(email:"speed@example.com",password:"a secure password",displayName:"Speed"),now:now)
    let first = try request(speed:60.49), second = try request(speed:60.41,finishedOffset:1)
    _ = try await store.submitResult(first,accessToken:owner.accessToken,now:now)
    _ = try await store.submitResult(second,accessToken:owner.accessToken,now:now)
    let page = try await store.leaderboard(.init(mode:"words",period:"all"),now:now)
    XCTAssertEqual(page.entries.first?.id,first.id)
    let history = try await store.results(.init(),credential:.accessToken(owner.accessToken),now:now)
    let entry = try XCTUnwrap(history.results.first { $0.id == first.id })
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(entry)) as? [String:Any])
    XCTAssertNotNil(json["speedPrecision"])
    let profile = try await store.publicProfile(id:owner.user.id,now:now)
    XCTAssertEqual(profile.preciseBestWPM,60.49)
    XCTAssertEqual(profile.personalBests.first?.preciseWpm,60.49)
    let week = try await store.leaderboard(.init(mode:"words",period:"week"),now:now)
    XCTAssertEqual(week.entries.first?.id,first.id)
  }
  func testExplicitNullAndBadPrecisionAreRejected() throws {
    let input = try request(speed:60.41)
    let base = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(input)) as? [String:Any])
    for report: Any in [NSNull(),["version":2,"wpm":60.41,"rawWpm":60.41],
      ["version":1,"wpm":60.41],["version":1,"wpm":61.41,"rawWpm":62]] {
      var json = base; json["speedPrecision"] = report
      XCTAssertThrowsError(try JSONDecoder().decode(ResultSubmissionRequest.self,from:JSONSerialization.data(withJSONObject:json)))
    }
  }

  private func directory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-speed-precision-\(UUID())")
    try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:false); return dir
  }
  private func store(file: URL? = nil, daily: Bool = false) throws -> AuthStore {
    try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development,
      dailyLeaderboardConfiguration:daily ? .typebarDefault : nil)
  }
  private func account(_ store: AuthStore, name: String = "Speed", date: Date? = nil) async throws -> AuthSessionResponse {
    try await store.register(.init(email:"\(name.lowercased())@example.com",password:"a secure password",displayName:name),now:date ?? now)
  }
  private let dailyQuery = LeaderboardQuery(mode:"words",language:"english",period:"day",wordLimit:25)

  func testDailyScoreTailAndFrozenReceiptUseFractionsAcrossDeletionAndReload() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), first = try store(file:file,daily:true)
    let owner = try await account(first), other = try await account(first,name:"Other")
    let low = try request(speed:60.41), high = try request(speed:60.49,finishedOffset:1)
    _ = try await first.submitResult(low,accessToken:other.accessToken,now:now)
    let receipt = try await first.submitResult(high,accessToken:owner.accessToken,now:now.addingTimeInterval(1))
    XCTAssertEqual(receipt.dailyLeaderboardRank,1)
    var board = try await first.leaderboard(dailyQuery,now:now.addingTimeInterval(1))
    XCTAssertEqual(board.entries.map(\.id),[high.id,low.id]); XCTAssertEqual(board.minWpm,60.41)
    XCTAssertEqual(board.entries.map(\.preciseWpm),[60.49,60.41])
    _ = try await first.deleteResults(.init(currentPassword:"a secure password"),accessToken:owner.accessToken,now:now)
    let bytes = try Data(contentsOf:file), loaded = try store(file:file,daily:true)
    let retry = try await loaded.submitResult(try request(speed:60.41,id:high.id),accessToken:owner.accessToken,now:now)
    XCTAssertEqual(retry,receipt); XCTAssertEqual(try Data(contentsOf:file),bytes)
    board = try await loaded.leaderboard(dailyQuery,now:now.addingTimeInterval(1))
    XCTAssertEqual(board.entries.first?.preciseWpm,60.49)
    let history = try await loaded.results(.init(),credential:.accessToken(owner.accessToken),now:now)
    XCTAssertEqual(history.total,0)
  }

  func testLegacyWinnerDoesNotAcquireInventedFractionalEvidence() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), first = try store(file:file)
    let owner = try await account(first)
    _ = try await first.submitResult(request(speed:60.49),accessToken:owner.accessToken,now:now)
    let legacy = ResultSubmissionRequest(id:UUID(),mode:"words",language:"english",durationSeconds:nil,wordLimit:25,
      wpm:80,rawWpm:80,accuracy:100,errorCount:0,eventCount:75,startedAt:now.addingTimeInterval(-11.25),finishedAt:now)
    _ = try await first.submitResult(legacy,accessToken:owner.accessToken,now:now)
    let bytes = try Data(contentsOf:file), loaded = try store(file:file)
    let profile = try await loaded.publicProfile(id:owner.user.id,now:now)
    XCTAssertEqual(profile.bestWPM,80); XCTAssertNil(profile.preciseBestWPM)
    XCTAssertNil(profile.personalBests.first?.preciseWpm)
    let saved = try await loaded.result(id:legacy.id,credential:.accessToken(owner.accessToken),now:now)
    XCTAssertNil(saved.speedPrecision); XCTAssertEqual(try Data(contentsOf:file),bytes)
  }

  func testPersistenceFailureRollsBackAllSpeedCopiesAndConcurrentRetryCapturesOnce() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), backup = dir.appendingPathComponent("backup.json")
    let first = try store(file:file,daily:true), owner = try await account(first), input = try request(speed:60.49)
    try FileManager.default.moveItem(at:file,to:backup); try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
    do { _ = try await first.submitResult(input,accessToken:owner.accessToken,now:now); XCTFail("Atomic rename must fail") } catch { }
    let empty = try await first.results(.init(),credential:.accessToken(owner.accessToken),now:now)
    XCTAssertEqual(empty.total,0)
    let board = try await first.leaderboard(dailyQuery,now:now); XCTAssertTrue(board.entries.isEmpty)
    try FileManager.default.removeItem(at:file); try FileManager.default.moveItem(at:backup,to:file)
    let instant = now
    async let a = first.submitResult(input,accessToken:owner.accessToken,now:instant)
    async let b = first.submitResult(input,accessToken:owner.accessToken,now:instant)
    let receipts = try await [a,b]; XCTAssertEqual(receipts[0],receipts[1])
    let loaded = try store(file:file,daily:true), page = try await loaded.results(.init(),credential:.accessToken(owner.accessToken),now:now)
    XCTAssertEqual(page.total,1); XCTAssertEqual(page.results.first?.speedPrecision,input.speedPrecision)
    let state = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
    XCTAssertEqual((state["experienceAwards"] as? [[String:Any]])?.count,1)
  }

  func testCorruptStoredRewardAndDailySnapshotRejectWithoutWriting() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), first = try store(file:file,daily:true), owner = try await account(first)
    _ = try await first.submitResult(request(speed:60.49),accessToken:owner.accessToken,now:now)
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
    for collection in ["results","experienceAwards"] {
      for value: Any? in [nil,NSNull(),["version":2],["version":1,"wpm":60.41,"rawWpm":60.41]] {
        var state = original, entries = try XCTUnwrap(state[collection] as? [[String:Any]])
        entries[0]["speedPrecision"] = value; state[collection] = entries
        let bytes = try JSONSerialization.data(withJSONObject:state); try bytes.write(to:file)
        XCTAssertThrowsError(try store(file:file,daily:true)); XCTAssertEqual(try Data(contentsOf:file),bytes)
      }
    }
    for value: Any? in [nil,NSNull(),60.41,60.491] {
      var state = original, cache = try XCTUnwrap(state["dailyLeaderboardCache"] as? [String:Any])
      var buckets = try XCTUnwrap(cache["buckets"] as? [[String:Any]])
      var entries = try XCTUnwrap(buckets[0]["entries"] as? [[String:Any]])
      entries[0]["preciseWpm"] = value; buckets[0]["entries"] = entries; cache["buckets"] = buckets; state["dailyLeaderboardCache"] = cache
      let bytes = try JSONSerialization.data(withJSONObject:state); try bytes.write(to:file)
      XCTAssertThrowsError(try store(file:file,daily:true)); XCTAssertEqual(try Data(contentsOf:file),bytes)
    }
    // Matching copies alone are insufficient: the stored counters and clock
    // still describe 60.49, not a different rate with the same integer view.
    var changed = original
    for collection in ["results","experienceAwards"] {
      var entries = try XCTUnwrap(changed[collection] as? [[String:Any]])
      entries[0]["speedPrecision"] = ["version":1,"wpm":60.41,"rawWpm":60.41]; changed[collection] = entries
    }
    let bytes = try JSONSerialization.data(withJSONObject:changed); try bytes.write(to:file)
    XCTAssertThrowsError(try store(file:file,daily:true)); XCTAssertEqual(try Data(contentsOf:file),bytes)
  }

  func testXPInputKeepsSpeedBindingAfterHistoryDeletionAndMalformedCountsReject() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), first = try store(file:file), owner = try await account(first)
    let seconds = 15.125, speed = ResultSpeedPrecision.round(900/15.13)
    let input = ResultSubmissionRequest(id:UUID(),mode:"words",language:"english",durationSeconds:nil,wordLimit:25,
      wpm:Int(speed.rounded()),rawWpm:Int(speed.rounded()),accuracy:100,errorCount:0,eventCount:75,
      experienceEvidence:.init(characterCounts:[75,0,0,0],scoringUnitBasis:.utf16,durationSeconds:15.13,
        afkSeconds:0.005,punctuation:false,numbers:false,modifiers:[]),speedPrecision:.init(wpm:speed,rawWpm:speed),
      practiceTiming:.init(version:1,terminalEngagedMilliseconds:15_125,priorAttemptEngagedMilliseconds:0),
      inputMetrics:.init(version:1,correctAttempts:75,totalAttempts:75,creditedUnits:75,retainedUnits:75),
      elapsedTime:.init(seconds:seconds),startedAt:now.addingTimeInterval(-seconds),finishedAt:now)
    _ = try await first.submitResult(input,accessToken:owner.accessToken,now:now)
    _ = try await first.deleteResults(.init(currentPassword:"a secure password"),accessToken:owner.accessToken,now:now)
    let saved = try Data(contentsOf:file); _ = try store(file:file); XCTAssertEqual(try Data(contentsOf:file),saved)
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with:saved) as? [String:Any])
    for mutation in 0..<2 {
      var changed = original, awards = try XCTUnwrap(changed["experienceAwards"] as? [[String:Any]])
      if mutation == 0 { awards[0]["speedPrecision"] = ["version":1,"wpm":59.49,"rawWpm":59.49] }
      else {
        var xp = try XCTUnwrap(awards[0]["input"] as? [String:Any]); xp["characterCounts"] = []
        awards[0]["input"] = xp
      }
      changed["experienceAwards"] = awards
      let bytes = try JSONSerialization.data(withJSONObject:changed); try bytes.write(to:file)
      XCTAssertThrowsError(try store(file:file)); XCTAssertEqual(try Data(contentsOf:file),bytes)
    }
  }

  func testMatchingIntegerCannotHideDifferentCounterRateOrInvalidProgrammaticSpeed() async throws {
    let first = try store(), owner = try await account(first)
    for report in [ResultSpeedPrecision(wpm:60.41,rawWpm:60.41), .init(wpm:60.49,rawWpm:60.41),
      .init(wpm:.nan,rawWpm:60.49),.init(wpm:420.01,rawWpm:420.01),.init(wpm:60.491,rawWpm:60.491)] {
      let input = ResultSubmissionRequest(id:UUID(),mode:"words",language:"english",durationSeconds:nil,wordLimit:25,
        wpm:60,rawWpm:60,accuracy:100,errorCount:0,eventCount:75,speedPrecision:report,
        startedAt:now.addingTimeInterval(-900/60.49),finishedAt:now)
      do { _ = try await first.submitResult(input,accessToken:owner.accessToken,now:now); XCTFail("Invalid precise rate must not mutate state") }
      catch let error as ResultStoreError { XCTAssertEqual(error,.invalidResult) }
    }
    let page = try await first.results(.init(),credential:.accessToken(owner.accessToken),now:now); XCTAssertEqual(page.total,0)
  }

  func testUTF16AndKoreanJamoUseRetainedUnitsAndIndependentDuration() async throws {
    let first = try store(), owner = try await account(first)
    for basis: ResultScoringUnitBasis in [.utf16,.koreanJamo] {
      let units = basis == .utf16 ? 1 : 5, speed = ResultSpeedPrecision.round(Double(units)*12/15.13)
      let input = ResultSubmissionRequest(id:UUID(),mode:"time",language:"english",durationSeconds:15,wordLimit:nil,
        wpm:Int(speed.rounded()),rawWpm:Int(speed.rounded()),accuracy:100,errorCount:0,eventCount:1,
        speedPrecision:.init(wpm:speed,rawWpm:speed),
        inputMetrics:.init(version:2,correctAttempts:1,totalAttempts:1,creditedUnits:units,retainedUnits:units,
          retainedInputUnits:1,scoringUnitBasis:basis),
        elapsedTime:.init(version:1,seconds:15.125),
        startedAt:now.addingTimeInterval(-15.125),finishedAt:now)
      _ = try await first.submitResult(input,accessToken:owner.accessToken,now:now)
      let saved = try await first.result(id:input.id,credential:.accessToken(owner.accessToken),now:now)
      XCTAssertEqual(saved.speedPrecision?.wpm,speed)
    }
  }

  func testNewSchemaAcceptsSourceUpperBoundAndPreservesLegacyBounds() async throws {
    let first = try store(), owner = try await account(first)
    for speed in [419.99,420.0] {
      let receipt = try await first.submitResult(request(speed:speed),accessToken:owner.accessToken,now:now)
      XCTAssertTrue(receipt.accepted)
    }
    let old = ResultSubmissionRequest(id:UUID(),mode:"words",language:"english",durationSeconds:nil,wordLimit:25,
      wpm:420,rawWpm:420,accuracy:100,errorCount:0,eventCount:75,startedAt:now.addingTimeInterval(-900/420),finishedAt:now)
    do { _ = try await first.submitResult(old,accessToken:owner.accessToken,now:now); XCTFail("Legacy schema must not silently widen") }
    catch let error as ResultStoreError { XCTAssertEqual(error,.invalidResult) }
  }

  func testActualHTTPNegotiationSubsecondDatesHistoryAndIsolation() async throws {
    let live = Date.now, first = try store(), owner = try await account(first,date:live), other = try await account(first,name:"Other",date:live)
    let input = ResultSubmissionRequest(id:UUID(),mode:"words",language:"english",durationSeconds:nil,wordLimit:25,
      wpm:60,rawWpm:60,accuracy:100,errorCount:0,eventCount:75,speedPrecision:.init(wpm:60.49,rawWpm:60.49),
      startedAt:live.addingTimeInterval(-900/60.49),finishedAt:live)
    let app = try await Application.make(.testing)
    do {
      try configure(app,authStore:first)
      try await app.test(.GET,"v1/capabilities") { response async throws in
        XCTAssertEqual(try response.content.decode(ServiceCapabilitiesResponse.self).capabilities["resultSpeedPrecision"],.available)
      }
      try await app.test(.POST,"v1/results",beforeRequest:{ outgoing async throws in
        outgoing.headers.bearerAuthorization = .init(token:owner.accessToken); try outgoing.content.encode(input)
      },afterResponse:{ response async in XCTAssertEqual(response.status,.ok) })
      for path in ["v1/results","v1/results/\(input.id)"] {
        try await app.test(.GET,path,beforeRequest:{ outgoing async in outgoing.headers.bearerAuthorization = .init(token:owner.accessToken) },afterResponse:{ response async throws in
          XCTAssertEqual(response.status,.ok)
          let saved = path == "v1/results" ? try response.content.decode(ResultListResponse.self).results.first : try response.content.decode(AccountResultResponse.self)
          XCTAssertEqual(saved?.speedPrecision,input.speedPrecision); XCTAssertEqual(saved?.startedAt,input.startedAt); XCTAssertEqual(saved?.finishedAt,input.finishedAt)
        })
      }
      try await app.test(.GET,"v1/results/\(input.id)",beforeRequest:{ outgoing async in outgoing.headers.bearerAuthorization = .init(token:other.accessToken) },afterResponse:{ response async in XCTAssertEqual(response.status,.notFound) })
      let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
      let base = try XCTUnwrap(JSONSerialization.jsonObject(with:encoder.encode(input)) as? [String:Any])
      for key in ["startedAtReferenceTime","finishedAtReferenceTime"] {
        var broken = base; broken.removeValue(forKey:key); let body = try JSONSerialization.data(withJSONObject:broken)
        try await app.test(.POST,"v1/results",beforeRequest:{ outgoing async in
          outgoing.headers.bearerAuthorization = .init(token:owner.accessToken); outgoing.headers.contentType = .json; outgoing.body = ByteBuffer(data:body)
        },afterResponse:{ response async in XCTAssertEqual(response.status,.badRequest) })
      }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }

  func testDailyRewardMailAndAnnouncementKeepTheWinningFraction() async throws {
    let config = try DailyLeaderboardConfiguration.fromJSON("""
      {"enabled":true,"expirationTimeInDays":2,"maxResults":100,
       "validModeRules":[{"language":"english","mode":"words","mode2":"25"}],
       "scheduleRewardsModeRules":[{"language":"english","mode":"words","mode2":"25"}],
       "topResultsToAnnounce":1,"xpRewardBrackets":[{"minRank":1,"maxRank":1,"minReward":100,"maxReward":100}]}
      """)
    let first = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development,dailyLeaderboardConfiguration:config)
    let owner = try await account(first)
    _ = try await first.submitResult(request(speed:60.49),accessToken:owner.accessToken,now:now)
    let jobs = await first.dailyLeaderboardRewardJobs()
    let due = Date(timeIntervalSince1970:Double(try XCTUnwrap(jobs.first).nextAttempt)/1_000)
    _ = try await first.processDueDailyLeaderboardRewards(now:due)
    let inbox = try await first.rewardInbox(accessToken:owner.accessToken,now:due)
    XCTAssertTrue(try XCTUnwrap(inbox.inbox.first).body.contains("60.49 WPM"))
    let announcements = await first.publicAnnouncements()
    XCTAssertTrue(try XCTUnwrap(announcements.announcements.first).message.contains("60.49 WPM"))
  }

  func testPublicDistributionAndNativeBadgeThresholdDoNotRoundUpTheScore() async throws {
    let first = try store(), owner = try await account(first)
    _ = try await first.updateProfile(.init(showAllBadges:true),accessToken:owner.accessToken,now:now)
    let input = ResultSubmissionRequest(id:UUID(),mode:"time",language:"english",durationSeconds:60,wordLimit:nil,
      wpm:80,rawWpm:80,accuracy:100,errorCount:0,eventCount:400,speedPrecision:.init(wpm:79.99,rawWpm:79.99),
      startedAt:now.addingTimeInterval(-4800/79.99),finishedAt:now)
    _ = try await first.submitResult(input,accessToken:owner.accessToken,now:now)
    let profile = try await first.publicProfile(id:owner.user.id,now:now)
    XCTAssertFalse(profile.earnedBadges.contains { $0.id == "swift-line" })
    let distribution = await first.publicEnglishMinuteSpeedDistribution()
    XCTAssertEqual(distribution.buckets.map(\.lowerBound),[70]); XCTAssertEqual(distribution.buckets.first?.count,1)
  }

  func testDistinctRawRateKeepsCustomDurationAndRejectsSameIntegerCounterMismatch() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), first = try store(file:file), owner = try await account(first)
    let wpm = ResultSpeedPrecision.round(62*12/15.125), raw = ResultSpeedPrecision.round(75*12/15.125)
    for valid in [false,true] {
      let input = ResultSubmissionRequest(id:UUID(),mode:"custom",language:"english",durationSeconds:nil,wordLimit:nil,
        wpm:Int(wpm.rounded()),rawWpm:Int(raw.rounded()),accuracy:83,errorCount:13,eventCount:75,
        speedPrecision:.init(wpm:wpm,rawWpm:valid ? raw : raw+0.01),
        inputMetrics:.init(version:2,correctAttempts:62,totalAttempts:75,creditedUnits:62,retainedUnits:75,
          retainedInputUnits:75,scoringUnitBasis:.utf16),elapsedTime:.init(seconds:15.125),
        startedAt:now.addingTimeInterval(-15.125),finishedAt:now)
      XCTAssertTrue(try XCTUnwrap(input.speedPrecision).matches(wpm:input.wpm,rawWpm:input.rawWpm))
      if !valid {
        do { _ = try await first.submitResult(input,accessToken:owner.accessToken,now:now); XCTFail("Raw must keep its own counter rate") }
        catch let error as ResultStoreError { XCTAssertEqual(error,.invalidResult) }
      } else {
        _ = try await first.submitResult(input,accessToken:owner.accessToken,now:now)
        let loaded = try store(file:file), saved = try await loaded.result(id:input.id,credential:.accessToken(owner.accessToken),now:now)
        XCTAssertEqual(saved.speedPrecision?.wpm,49.19); XCTAssertEqual(saved.speedPrecision?.rawWpm,59.5)
        XCTAssertEqual(saved.preciseAccuracy,82.67); XCTAssertEqual(saved.elapsedTime?.seconds,15.125)
      }
    }
    let page = try await first.results(.init(),credential:.accessToken(owner.accessToken),now:now); XCTAssertEqual(page.total,1)
  }
}
