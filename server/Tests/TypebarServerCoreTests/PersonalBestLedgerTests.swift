import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class PersonalBestLedgerTests: XCTestCase {
  private let now = Date(timeIntervalSince1970:1_800_000_000)
  private let normal = ResultPersonalBestConfiguration(difficulty:"normal",punctuation:false,numbers:false,lazyMode:false)
  private func request(speed: Double = 60.49, mode: String = "time", parameter: Int = 15,
    config: ResultPersonalBestConfiguration?, consistency: Double = 80, finish: Date? = nil) -> ResultSubmissionRequest {
    let duration = mode == "time" ? Double(parameter) : 15, end = finish ?? now
    let units = max(1,Int((speed*duration/12).rounded()))
    return .init(id:UUID(),mode:mode,language:"english",durationSeconds:mode == "time" ? parameter : nil,
      wordLimit:mode == "words" ? parameter : nil,wpm:Int(speed.rounded()),rawWpm:Int(speed.rounded()),
      accuracy:100,consistency:consistency,errorCount:0,eventCount:units,personalBestConfiguration:config,
      speedPrecision:.init(wpm:speed,rawWpm:speed),startedAt:end.addingTimeInterval(-Double(units)*12/speed),finishedAt:end)
  }
  private func account(_ store: AuthStore, name: String = "Owner") async throws -> AuthSessionResponse {
    try await store.register(.init(email:"\(name.lowercased())@example.com",password:"a secure password",displayName:name),now:now)
  }
  private func snapshots(_ profile: PublicProfileResponse) throws -> [[String:Any]] {
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(profile)) as? [String:Any])
    return json["personalBestSnapshots"] as? [[String:Any]] ?? []
  }

  func testTieKeepsFirstAcceptedSnapshotRatherThanMostRecentFinish() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development), owner = try await account(store)
    let first = request(config:normal), later = request(config:normal,consistency:100,finish:now.addingTimeInterval(1))
    _ = try await store.submitResult(first,accessToken:owner.accessToken,now:now.addingTimeInterval(0.875))
    _ = try await store.submitResult(later,accessToken:owner.accessToken,now:now.addingTimeInterval(1))
    let profile = try await store.publicProfile(id:owner.user.id,now:now)
    XCTAssertEqual(profile.personalBests.first?.id,first.id); XCTAssertEqual(profile.personalBests.first?.consistency,80)
    let full = try snapshots(profile)
    XCTAssertEqual(full.count,1)
    XCTAssertEqual((full.first?["acceptedAtMilliseconds"] as? NSNumber)?.int64Value,1_800_000_000_875)
  }

  func testHistoryDeletionRetainsPublicBestAllTimeBoardAndDistribution() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development,
      dailyLeaderboardConfiguration:.typebarDefault), owner = try await account(store)
    let input = request(parameter:60,config:normal)
    let receipt = try await store.submitResult(input,accessToken:owner.accessToken,now:now)
    _ = try await store.deleteResults(.init(currentPassword:"a secure password"),accessToken:owner.accessToken,now:now)
    let profile = try await store.publicProfile(id:owner.user.id,now:now)
    XCTAssertEqual(profile.personalBests.first?.id,input.id); XCTAssertEqual(profile.preciseBestWPM,60.49)
    let board = try await store.leaderboard(.init(mode:"time",period:"all",durationSeconds:60),now:now)
    XCTAssertEqual(board.entries.first?.id,input.id)
    let distribution = await store.publicEnglishMinuteSpeedDistribution(); XCTAssertEqual(distribution.buckets.first?.count,1)
    let history = try await store.results(.init(),credential:.accessToken(owner.accessToken),now:now); XCTAssertEqual(history.total,0)
    let retry = try await store.submitResult(input,accessToken:owner.accessToken,now:now); XCTAssertEqual(retry,receipt)
  }

  func testLazyRequiresNonLazyNewPersonalBestTriggerButCanWinTheBoardSnapshot() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development), owner = try await account(store)
    let lazy = request(speed:90.49,config:.init(difficulty:"normal",punctuation:false,numbers:false,lazyMode:true))
    _ = try await store.submitResult(lazy,accessToken:owner.accessToken,now:now)
    let empty = try await store.leaderboard(.init(mode:"time",period:"all",durationSeconds:15),now:now)
    XCTAssertTrue(empty.entries.isEmpty,"Lazy creation alone must not create leaderboard PB")
    _ = try await store.submitResult(request(config:normal),accessToken:owner.accessToken,now:now.addingTimeInterval(1))
    let board = try await store.leaderboard(.init(mode:"time",period:"all",durationSeconds:15),now:now)
    XCTAssertEqual(board.entries.first?.id,lazy.id); XCTAssertEqual(board.entries.first?.preciseWpm,90.49)
  }

  func testFullGroupingAndUnknownLegacyNeverCollapseIntoExplicitDefaults() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development), owner = try await account(store)
    let configurations: [ResultPersonalBestConfiguration?] = [normal,
      .init(difficulty:"expert",punctuation:false,numbers:false,lazyMode:false),
      .init(difficulty:"normal",punctuation:true,numbers:false,lazyMode:false),
      .init(difficulty:"normal",punctuation:false,numbers:true,lazyMode:false),
      .init(difficulty:"normal",punctuation:false,numbers:false,lazyMode:true),nil]
    for config in configurations { _ = try await store.submitResult(request(config:config),accessToken:owner.accessToken,now:now) }
    for mode in ["custom","zen"] {
      for parameter in [10,25] { _ = try await store.submitResult(request(mode:mode,parameter:parameter,config:normal),accessToken:owner.accessToken,now:now) }
    }
    let profile = try await store.publicProfile(id:owner.user.id,now:now), full = try snapshots(profile)
    XCTAssertEqual(full.count,8)
    XCTAssertEqual(full.filter { $0["mode"] as? String == "custom" }.count,1)
    XCTAssertEqual(full.filter { $0["mode"] as? String == "zen" }.count,1)
    XCTAssertEqual(full.filter { $0["personalBestConfiguration"] == nil }.count,1)
  }

  func testPublicClearRemovesBothBooksAndDailyButKeepsHistoryExperienceAndOtherOwner() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development,dailyLeaderboardConfiguration:.typebarDefault)
    let owner = try await account(store), other = try await account(store,name:"Other")
    for user in [owner,other] { _ = try await store.submitResult(request(config:normal),accessToken:user.accessToken,now:now) }
    let before = try await store.authenticatedUser(for:owner.accessToken,now:now)
    let weeklyBefore = try await store.experienceLeaderboard(period:"week",now:now)
    _ = try await store.resetPersonalBests(.init(currentPassword:"a secure password"),accessToken:owner.accessToken,now:now)
    for period in ["all","day"] {
      let board = try await store.leaderboard(.init(mode:"time",period:period,durationSeconds:15),now:now)
      XCTAssertEqual(board.entries.map(\.userID),[other.user.id])
    }
    let history = try await store.results(.init(),credential:.accessToken(owner.accessToken),now:now); XCTAssertEqual(history.total,1)
    let after = try await store.authenticatedUser(for:owner.accessToken,now:now); XCTAssertEqual(after.totalExperience,before.totalExperience)
    let weeklyAfter = try await store.experienceLeaderboard(period:"week",now:now); XCTAssertEqual(weeklyAfter,weeklyBefore)
    // Date equality with the clear is not a reason to hide the next new PB.
    let next = request(speed:45.49,config:normal)
    _ = try await store.submitResult(next,accessToken:owner.accessToken,now:now)
    let profile = try await store.publicProfile(id:owner.user.id,now:now); XCTAssertEqual(profile.personalBests.first?.id,next.id)
  }

  private func directory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-pb-ledger-\(UUID())")
    try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:false); return dir
  }
  private func diskStore(_ file: URL) throws -> AuthStore {
    try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development,dailyLeaderboardConfiguration:.typebarDefault)
  }
  private func json(_ file: URL) throws -> [String:Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
  }

  func testDeletionReloadAndClearCannotResurrectTombstoneSnapshots() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), first = try diskStore(file), owner = try await account(first)
    let input = request(config:normal), receipt = try await first.submitResult(input,accessToken:owner.accessToken,now:now.addingTimeInterval(0.875))
    _ = try await first.deleteResults(.init(currentPassword:"a secure password"),accessToken:owner.accessToken,now:now)
    let original = try Data(contentsOf:file), loaded = try diskStore(file)
    let profile = try await loaded.publicProfile(id:owner.user.id,now:now)
    XCTAssertEqual(profile.personalBestSnapshots?.first?.id,input.id)
    XCTAssertEqual(profile.personalBestSnapshots?.first?.acceptedAtMilliseconds,1_800_000_000_875)
    XCTAssertEqual(try Data(contentsOf:file),original,"Loading must not rewrite state")
    _ = try await loaded.resetPersonalBests(.init(currentPassword:"a secure password"),accessToken:owner.accessToken,now:now.addingTimeInterval(1))
    let cleared = try Data(contentsOf:file), reloaded = try diskStore(file)
    let retry = try await reloaded.submitResult(input,accessToken:owner.accessToken,now:now.addingTimeInterval(2))
    XCTAssertEqual(retry,receipt); XCTAssertEqual(try Data(contentsOf:file),cleared)
    let empty = try await reloaded.publicProfile(id:owner.user.id,now:now); XCTAssertEqual(empty.personalBestSnapshots,[])
    let board = try await reloaded.leaderboard(.init(mode:"time",period:"all",durationSeconds:15),now:now); XCTAssertTrue(board.entries.isEmpty)
  }

  func testMigrationFreezesOnlyVisibleHistoryAndMarksMissingControlsUnknown() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), first = try diskStore(file), owner = try await account(first)
    let unknown = request(config:nil), known = request(speed:55.49,config:normal)
    for input in [unknown,known] { _ = try await first.submitResult(input,accessToken:owner.accessToken,now:now) }
    var state = try json(file); state.removeValue(forKey:"personalBestLedger"); state.removeValue(forKey:"personalBestLedgerManaged")
    var awards = try XCTUnwrap(state["experienceAwards"] as? [[String:Any]])
    for index in awards.indices { awards[index].removeValue(forKey:"personalBestReceipt") }
    state["experienceAwards"] = awards
    let bytes = try JSONSerialization.data(withJSONObject:state); try bytes.write(to:file)
    let migrated = try diskStore(file), profile = try await migrated.publicProfile(id:owner.user.id,now:now)
    XCTAssertEqual(try Data(contentsOf:file),bytes); XCTAssertEqual(profile.personalBestHistoryComplete,false)
    XCTAssertEqual(profile.personalBestSnapshots?.count,2)
    XCTAssertEqual(profile.personalBestSnapshots?.filter { $0.personalBestConfiguration == nil }.count,1)
    XCTAssertTrue(profile.personalBestSnapshots!.allSatisfy { $0.personalBestOrigin == "legacyHistory" && $0.acceptedAtMilliseconds == nil })
    _ = try await migrated.deleteResults(.init(currentPassword:"a secure password"),accessToken:owner.accessToken,now:now)
    let frozen = try diskStore(file), retained = try await frozen.publicProfile(id:owner.user.id,now:now)
    XCTAssertEqual(retained.personalBestSnapshots,profile.personalBestSnapshots)
  }

  func testLostCorruptDuplicateAndWrongOwnerLedgerRejectWithoutWriting() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), first = try diskStore(file), owner = try await account(first)
    _ = try await first.submitResult(request(config:normal),accessToken:owner.accessToken,now:now)
    let original = try json(file)
    var cases: [[String:Any]] = []
    for value: Any? in [nil,NSNull(),["version":2]] {
      var state = original; state["personalBestLedger"] = value; cases.append(state)
    }
    var markerRemoved = original; markerRemoved.removeValue(forKey:"personalBestLedger"); markerRemoved.removeValue(forKey:"personalBestLedgerManaged"); cases.append(markerRemoved)
    for collection in ["entries","leaderboardEntries"] {
      for change in ["duplicate","owner","speed","configuration","clock"] {
        var state = original, ledger = try XCTUnwrap(state["personalBestLedger"] as? [String:Any])
        var entries = try XCTUnwrap(ledger[collection] as? [[String:Any]])
        switch change {
        case "duplicate": entries.append(entries[0])
        case "owner": entries[0]["userID"] = UUID().uuidString
        case "speed": entries[0]["speedPrecision"] = ["version":1,"wpm":60.41,"rawWpm":60.41]
        case "configuration": entries[0]["personalBestConfiguration"] = NSNull()
        default: entries[0]["acceptedAtMilliseconds"] = -1
        }
        ledger[collection] = entries; state["personalBestLedger"] = ledger; cases.append(state)
      }
    }
    for state in cases {
      let bytes = try JSONSerialization.data(withJSONObject:state); try bytes.write(to:file)
      XCTAssertThrowsError(try diskStore(file)); XCTAssertEqual(try Data(contentsOf:file),bytes)
    }
  }

  func testFailedAtomicSaveRollsBackSnapshotAndConcurrentDuplicateAcceptsOnce() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), backup = dir.appendingPathComponent("backup.json")
    let store = try diskStore(file), owner = try await account(store), input = request(config:normal)
    try FileManager.default.moveItem(at:file,to:backup); try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
    do { _ = try await store.submitResult(input,accessToken:owner.accessToken,now:now); XCTFail("Rename must fail") } catch {}
    let empty = try await store.publicProfile(id:owner.user.id,now:now); XCTAssertEqual(empty.personalBestSnapshots,[])
    try FileManager.default.removeItem(at:file); try FileManager.default.moveItem(at:backup,to:file)
    let clock = now
    async let a = store.submitResult(input,accessToken:owner.accessToken,now:clock)
    async let b = store.submitResult(input,accessToken:owner.accessToken,now:clock)
    let receipts = try await [a,b]; XCTAssertEqual(receipts[0],receipts[1])
    let loaded = try diskStore(file), profile = try await loaded.publicProfile(id:owner.user.id,now:now)
    XCTAssertEqual(profile.personalBestSnapshots?.count,1)
    _ = try await loaded.resetAccount(.init(currentPassword:"a secure password"),accessToken:owner.accessToken,now:now)
    let reset = try diskStore(file), resetProfile = try await reset.publicProfile(id:owner.user.id,now:now)
    XCTAssertEqual(resetProfile.personalBestSnapshots,[])
  }
  func testMatchingCorruptSnapshotCopiesStillBindToExactSavedCompletionDate() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), store = try diskStore(file), owner = try await account(store)
    _ = try await store.submitResult(request(config:normal),accessToken:owner.accessToken,now:now)
    var state = try json(file), ledger = try XCTUnwrap(state["personalBestLedger"] as? [String:Any])
    for key in ["entries","leaderboardEntries"] {
      var entries = try XCTUnwrap(ledger[key] as? [[String:Any]])
      entries[0]["completedAtReferenceTime"] = try XCTUnwrap(entries[0]["completedAtReferenceTime"] as? Double) + 0.5
      ledger[key] = entries
    }
    state["personalBestLedger"] = ledger
    var awards = try XCTUnwrap(state["experienceAwards"] as? [[String:Any]])
    var receipt = try XCTUnwrap(awards[0]["personalBestReceipt"] as? [String:Any])
    receipt["candidate"] = (ledger["entries"] as? [[String:Any]])?.first
    awards[0]["personalBestReceipt"] = receipt; state["experienceAwards"] = awards
    let bytes = try JSONSerialization.data(withJSONObject:state); try bytes.write(to:file)
    XCTAssertThrowsError(try diskStore(file)); XCTAssertEqual(try Data(contentsOf:file),bytes)
  }

  func testOptOutClearsOnlyLeaderboardBookAndCannotReappearOnOptIn() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development), owner = try await account(store)
    _ = try await store.submitResult(request(config:normal),accessToken:owner.accessToken,now:now)
    _ = try await store.updateProfile(.init(leaderboardOptedOut:true),accessToken:owner.accessToken,now:now)
    let profile = try await store.publicProfile(id:owner.user.id,now:now); XCTAssertEqual(profile.personalBestSnapshots?.count,1)
    _ = try await store.updateProfile(.init(leaderboardOptedOut:false),accessToken:owner.accessToken,now:now)
    let empty = try await store.leaderboard(.init(mode:"time",period:"all",durationSeconds:15),now:now); XCTAssertTrue(empty.entries.isEmpty)
    _ = try await store.submitResult(request(speed:60.59,config:normal),accessToken:owner.accessToken,now:now)
    let restored = try await store.leaderboard(.init(mode:"time",period:"all",durationSeconds:15),now:now); XCTAssertEqual(restored.entries.first?.preciseWpm,60.59)
  }

  func testLegacyDerivedDayClearUsesIdentityNotAnAmbiguousDateBoundary() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), store = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await account(store)
    let old = request(config:normal), next = request(speed:45.49,config:normal)
    _ = try await store.submitResult(old,accessToken:owner.accessToken,now:now)
    _ = try await store.resetPersonalBests(.init(currentPassword:"a secure password"),accessToken:owner.accessToken,now:now)
    let empty = try await store.leaderboard(.init(mode:"time",period:"day",durationSeconds:15),now:now); XCTAssertTrue(empty.entries.isEmpty)
    _ = try await store.submitResult(next,accessToken:owner.accessToken,now:now)
    let loaded = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let board = try await loaded.leaderboard(.init(mode:"time",period:"day",durationSeconds:15),now:now)
    XCTAssertEqual(board.entries.map(\.id),[next.id])
  }

  func testXPAdmissionDayAndClientCompletionRemainSeparateAfterDeletedHistoryReload() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), store = try diskStore(file), owner = try await account(store)
    let end = now.addingTimeInterval(-86_400)
    let input = ResultSubmissionRequest(id:UUID(),mode:"words",language:"english",durationSeconds:nil,wordLimit:25,
      wpm:60,rawWpm:60,accuracy:100,errorCount:0,eventCount:75,
      experienceEvidence:.init(characterCounts:[75,0,0,0],scoringUnitBasis:.utf16,durationSeconds:15,
        afkSeconds:0,punctuation:false,numbers:false,modifiers:[]),personalBestConfiguration:normal,
      practiceTiming:.init(version:1,terminalEngagedMilliseconds:15_000,priorAttemptEngagedMilliseconds:0),
      inputMetrics:.init(version:1,correctAttempts:75,totalAttempts:75,creditedUnits:75,retainedUnits:75),
      startedAt:end.addingTimeInterval(-15),finishedAt:end)
    _ = try await store.submitResult(input,accessToken:owner.accessToken,now:now.addingTimeInterval(0.875))
    _ = try await store.deleteResults(.init(currentPassword:"a secure password"),accessToken:owner.accessToken,now:now)
    let loaded = try diskStore(file), profile = try await loaded.publicProfile(id:owner.user.id,now:now)
    XCTAssertEqual(profile.personalBestSnapshots?.first?.finishedAt,end)
    XCTAssertEqual(profile.personalBestSnapshots?.first?.acceptedAtMilliseconds,1_800_000_000_875)
  }

  func testActualHTTPNegotiatesPublicSnapshotsAndAuthenticatedClear() async throws {
    let live = Date.now, store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await store.register(.init(email:"httppb@example.com",password:"a secure password",displayName:"HTTP PB"),now:live)
    let input = request(config:normal,finish:live)
    _ = try await store.submitResult(input,accessToken:owner.accessToken,now:live)
    let app = try await Application.make(.testing)
    do {
      try configure(app,authStore:store)
      try await app.test(.GET,"v1/capabilities") { response async throws in
        XCTAssertEqual(try response.content.decode(ServiceCapabilitiesResponse.self).capabilities["accountPersonalBestLedger"],.available)
      }
      try await app.test(.GET,"v1/profiles/\(owner.user.id)") { response async throws in
        XCTAssertEqual(response.status,.ok)
        let json = try JSONSerialization.jsonObject(with:Data(response.body.readableBytesView)) as? [String:Any]
        XCTAssertEqual(json?["personalBestLedgerVersion"] as? Int,1)
        XCTAssertEqual((json?["personalBestSnapshots"] as? [[String:Any]])?.count,1)
        for privateKey in ["email","accessToken","eventCount","tags","experienceEvidence"] { XCTAssertNil(json?[privateKey]) }
      }
      try await app.test(.DELETE,"v1/personal-bests") { response async in XCTAssertEqual(response.status,.unauthorized) }
      try await app.test(.DELETE,"v1/personal-bests",beforeRequest: { request async throws in
        request.headers.add(name:"Authorization",value:"Bearer \(owner.accessToken)")
        try request.content.encode(ResetPersonalBestsRequest(currentPassword:"a secure password"))
      },afterResponse: { response async in XCTAssertEqual(response.status,.ok) })
      let empty = try await store.publicProfile(id:owner.user.id,now:live); XCTAssertEqual(empty.personalBestSnapshots,[])
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }

  func testDifferentialAgainstActualPinnedPersonalAndLeaderboardDALBooks() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Read-only source comparison requires TYPEBAR_REFERENCE_ROOT; readiness gate sets it")
    }
    let script = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Scripts/check-source-personal-best.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
    process.arguments = ["node","--experimental-vm-modules",script.path,reference,"--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(), errorData = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus,0,String(decoding:errorData,as:UTF8.self))
    struct Value: Codable, Equatable {
      let mode: String; let mode2: String; let language: String; let difficulty: String
      let punctuation: Bool; let numbers: Bool; let lazyMode: Bool
      let wpm: Double; let raw: Double; let acc: Double; let consistency: Double; let timestamp: Int
      var key: String { "\(mode)/\(mode2)/\(language)/\(difficulty)/\(punctuation)/\(numbers)/\(lazyMode)" }
    }
    struct Input: Decodable {
      let mode: String; let mode2: String; let language: String; let difficulty: String
      let punctuation: Bool; let numbers: Bool; let lazyMode: Bool
      let wpm: Double; let rawWpm: Double; let acc: Int; let consistency: Double
    }
    struct Step: Decodable { let action: String; let input: Input?; let clock: Int; let isPb: Bool?; let personal: [Value]; let leaderboard: [Value] }
    struct Document: Decodable { let referenceCommit: String; let trace: [Step] }
    let document = try JSONDecoder().decode(Document.self,from:data)
    XCTAssertEqual(document.referenceCommit,"91bd24bb8513785c7364cbea29296ff7adafac41"); XCTAssertEqual(document.trace.count,42)
    let userID = UUID(); var ledger = PersonalBestLedger()
    func projection(_ snapshots: [PersonalBestSnapshot]) throws -> [Value] {
      try snapshots.map { s in
        let config = try XCTUnwrap(s.personalBestConfiguration)
        return Value(mode:s.mode,mode2:s.mode2,language:s.language,difficulty:config.difficulty,
          punctuation:config.punctuation,numbers:config.numbers,lazyMode:config.lazyMode,
          wpm:s.effectiveWpm,raw:s.speedPrecision?.rawWpm ?? Double(s.rawWpm),acc:s.effectiveAccuracy,
          consistency:s.consistency,timestamp:try XCTUnwrap(s.acceptedAtMilliseconds))
      }.sorted { $0.key < $1.key }
    }
    for step in document.trace {
      switch step.action {
      case "submit":
        let input = try XCTUnwrap(step.input), end = Date(timeIntervalSince1970:Double(step.clock)/1_000)
        let request = ResultSubmissionRequest(id:UUID(),mode:input.mode,language:input.language,
          durationSeconds:input.mode == "time" ? Int(input.mode2) : nil,wordLimit:input.mode == "words" ? Int(input.mode2) : nil,
          wpm:Int(input.wpm.rounded()),rawWpm:Int(input.rawWpm.rounded()),accuracy:input.acc,consistency:input.consistency,
          errorCount:0,eventCount:75,personalBestConfiguration:.init(difficulty:input.difficulty,
            punctuation:input.punctuation,numbers:input.numbers,lazyMode:input.lazyMode),
          speedPrecision:.init(wpm:input.wpm,rawWpm:input.rawWpm),startedAt:end.addingTimeInterval(-15),finishedAt:end)
        XCTAssertEqual(ledger.accept(try .make(request,userID:userID,acceptedAt:end,origin:.accepted)),step.isPb)
      case "resetPersonal": ledger.clear(userID:userID,personalOnly:true)
      case "clear": ledger.clear(userID:userID)
      case "deleteHistory": break
      default: XCTFail("Unexpected source trace action")
      }
      XCTAssertEqual(try projection(ledger.entries),step.personal.sorted { $0.key < $1.key },"\(step.action) at \(step.clock)")
      XCTAssertEqual(try projection(ledger.leaderboardEntries),step.leaderboard.sorted { $0.key < $1.key },"\(step.action) at \(step.clock)")
    }
  }
}
