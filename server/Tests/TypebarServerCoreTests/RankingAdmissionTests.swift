import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class RankingAdmissionTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private func request(modifiers: [String] = [], stop: Bool = false, perfect: Bool = true,
    units: Int = 75, id: UUID = UUID(), endingAt end: Date? = nil) throws -> ResultSubmissionRequest {
    let end = end ?? now
    let base = ResultSubmissionRequest(id: id, mode: "words", language: "english",
      durationSeconds: nil, wordLimit: 25, wpm: units * 4 / 5, rawWpm: units * 4 / 5, accuracy: perfect ? 100 : 99,
      errorCount: perfect ? 0 : 1, eventCount: units,
      experienceEvidence: .init(characterCounts: [units,0,0,0], scoringUnitBasis: .utf16,
        durationSeconds: 15, afkSeconds: 0, punctuation: false, numbers: false, modifiers: modifiers),
      practiceTiming: .init(version: 1, terminalEngagedMilliseconds: 15_000, priorAttemptEngagedMilliseconds: 0),
      inputMetrics: .init(version: 1, correctAttempts: perfect ? units : units - 1, totalAttempts: units,
        creditedUnits: units, retainedUnits: units), startedAt: end.addingTimeInterval(-15), finishedAt: end)
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
    json["rankingEvidence"] = ["version":1,"stopOnLetter":stop,"modifiers":modifiers]
    return try JSONDecoder().decode(ResultSubmissionRequest.self, from: JSONSerialization.data(withJSONObject: json))
  }
  private func account(_ store: AuthStore) async throws -> AuthSessionResponse {
    try await store.register(.init(email: "ranking@example.com", password: "a secure password", displayName: "Ranking"), now: now)
  }
  func testCrossingTheThresholdDoesNotAdmitThatSubmissionOrRetroactivelyAddWeeklyXP() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, minimumLeaderboardTypingSeconds: 15)
    let owner = try await account(store)
    let first = try await store.submitResult(request(), accessToken: owner.accessToken, now: now)
    let second = try await store.submitResult(request(), accessToken: owner.accessToken, now: now)
    XCTAssertFalse(first.leaderboardEligible); XCTAssertFalse(second.leaderboardEligible)
    let before = try await store.experienceLeaderboard(now: now)
    XCTAssertTrue(before.entries.isEmpty)
    let third = try await store.submitResult(request(), accessToken: owner.accessToken, now: now)
    XCTAssertTrue(third.leaderboardEligible)
    let after = try await store.experienceLeaderboard(now: now)
    XCTAssertEqual(after.entries.first?.totalExperience, third.experienceGained)
    XCTAssertEqual(Double(third.totalExperience), first.experienceGained + second.experienceGained + third.experienceGained)
  }
  func testBlockedFunboxAndStopOnLetterExcludePBAndSpeedButNotWeeklyXP() async throws {
    for (modifiers, stop, perfect) in [(["uppercase"], false, true), ([], true, false)] {
      let store = try AuthStore(fileURL: nil, bcryptCost: 4), owner = try await account(store)
      _ = try await store.submitResult(request(), accessToken: owner.accessToken, now: now)
      let input = try request(modifiers: modifiers, stop: stop, perfect: perfect, units: 100)
      let receipt = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
      XCTAssertFalse(receipt.leaderboardEligible)
      let daily = try await store.leaderboard(.init(mode: "words", language: "english", period: "day"), now: now)
      XCTAssertTrue(daily.entries.isEmpty)
      let profile = try await store.publicProfile(id: owner.user.id, now: now)
      XCTAssertFalse(profile.personalBests.contains { $0.id == input.id })
      let weekly = try await store.experienceLeaderboard(now: now)
      XCTAssertEqual(weekly.entries.first?.totalExperience, receipt.experienceGained)
    }
  }

  func testActualPinnedAdmissionBranchesAndEntireFunboxPBMetadata() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness sets TYPEBAR_REFERENCE_ROOT for actual-source differential")
    }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Scripts/check-source-ranking-admission.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    let node = ProcessInfo.processInfo.environment["TYPEBAR_RANKING_SOURCE_NODE"]
    process.executableURL = URL(fileURLWithPath: node ?? "/usr/bin/env")
    process.arguments = (node == nil ? ["node"] : []) + ["--experimental-vm-modules",script.path,reference,"--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: errorData, as: UTF8.self))
    struct Input: Decodable { let mode: String; let accuracy: Double; let bailedOut: Bool
      let modifiers: [String]; let stopOnLetter: Bool }
    struct Fixture: Decodable { let input: Input; let context: RankingAdmissionContext; let decision: RankingAdmissionDecision }
    struct Catalog: Decodable { let name: String; let allowsPersonalBest: Bool }
    struct Document: Decodable { let referenceCommit: String; let catalog: [Catalog]; let fixtures: [Fixture] }
    let document = try JSONDecoder().decode(Document.self, from: data)
    XCTAssertEqual(document.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(document.catalog.count, 48); XCTAssertEqual(document.fixtures.count, 12_240)
    let nativeIDs = Dictionary(uniqueKeysWithValues: ExperienceModifierCatalog.entries.compactMap { id, entry in
      entry.sourceName.map { ($0,id) }
    })
    for metadata in document.catalog {
      let id = try XCTUnwrap(nativeIDs[metadata.name])
      XCTAssertEqual(ExperienceModifierCatalog.entries[id]?.allowsPersonalBest, metadata.allowsPersonalBest, metadata.name)
    }
    for fixture in document.fixtures {
      let modifiers = try fixture.input.modifiers.map { try XCTUnwrap(nativeIDs[$0]) }
      let input = RankingAdmissionInput(mode: fixture.input.mode, accuracy: fixture.input.accuracy,
        bailedOut: fixture.input.bailedOut, modifiers: modifiers, stopOnLetter: fixture.input.stopOnLetter,
        evidence: .init(stopOnLetter: fixture.input.stopOnLetter, modifiers: modifiers))
      let decision = RankingAdmission.evaluate(input, context: fixture.context)
      XCTAssertEqual(decision, fixture.decision, "\(fixture.input) / \(fixture.context)")
      try RankingAdmission(version: 1, input: input, context: fixture.context, decision: decision).validate()
    }
  }

  func testEnvironmentIsExactAndDefaultsToProduction() throws {
    XCTAssertEqual(try RankingEnvironment.fromEnvironment(nil), .production)
    XCTAssertEqual(try RankingEnvironment.fromEnvironment("development"), .development)
    for value in ["dev", "", "Development", " production"] {
      XCTAssertThrowsError(try RankingEnvironment.fromEnvironment(value))
    }
  }

  func testFrozenReceiptSurvivesThresholdChangeReloadAndDeletedHistory() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-ranking-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await account(store)
    let input = try request(stop: true)
    let receipt = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    XCTAssertFalse(receipt.leaderboardEligible)
    let bytes = try Data(contentsOf: file)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4, rankingEnvironment: .development)
    XCTAssertEqual(try Data(contentsOf: file), bytes, "Read-only load must not rewrite admission")
    let duplicate = try await reloaded.submitResult(input, accessToken: owner.accessToken, now: now)
    XCTAssertFalse(duplicate.leaderboardEligible)
    let history = try await reloaded.result(id: input.id, credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(history.rankingEvidence, input.rankingEvidence)
    _ = try await reloaded.deleteResults(.init(currentPassword: "a secure password"), accessToken: owner.accessToken, now: now)
    let tombstone = try await reloaded.submitResult(input, accessToken: owner.accessToken, now: now)
    XCTAssertFalse(tombstone.leaderboardEligible); XCTAssertEqual(tombstone.totalExperience, receipt.totalExperience)
    let weekly = try await reloaded.experienceLeaderboard(now: now)
    XCTAssertTrue(weekly.entries.isEmpty)
  }

  func testExplicitCorruptSnapshotAndBindingsRejectWithoutChangingOriginalFile() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-ranking-corrupt-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await account(store)
    _ = try await store.submitResult(request(), accessToken: owner.accessToken, now: now)
    let base = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    for mutation in 0..<5 {
      var json = base
      var awards = try XCTUnwrap(json["experienceAwards"] as? [[String: Any]])
      var admission = try XCTUnwrap(awards[0]["rankingAdmission"] as? [String: Any])
      if mutation == 0 { awards[0]["rankingAdmission"] = NSNull() }
      else {
        if mutation == 1 { admission["version"] = 2 }
        if mutation == 2 {
          var decision = try XCTUnwrap(admission["decision"] as? [String: Any])
          decision["speedEligible"] = true; admission["decision"] = decision
        }
        if mutation == 3 {
          var input = try XCTUnwrap(admission["input"] as? [String: Any])
          input["accuracy"] = 99; admission["input"] = input
        }
        if mutation == 4 {
          var context = try XCTUnwrap(admission["context"] as? [String: Any])
          context["previousTypingSeconds"] = -1; admission["context"] = context
        }
        awards[0]["rankingAdmission"] = admission
      }
      json["experienceAwards"] = awards
      let candidate = try JSONSerialization.data(withJSONObject: json)
      // Test-owned fault fixture, never the user's database.
      try candidate.write(to: file)
      XCTAssertThrowsError(try AuthStore(fileURL: file, bcryptCost: 4), "Mutation \(mutation)")
      XCTAssertEqual(try Data(contentsOf: file), candidate)
    }
    var old = base
    var awards = try XCTUnwrap(old["experienceAwards"] as? [[String: Any]])
    awards[0].removeValue(forKey: "rankingAdmission"); old["experienceAwards"] = awards
    let legacy = try JSONSerialization.data(withJSONObject: old); try legacy.write(to: file)
    let loaded = try AuthStore(fileURL: file, bcryptCost: 4)
    XCTAssertEqual(try Data(contentsOf: file), legacy)
    let history = try await loaded.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertNil(history.results.first?.rankingEvidence)
  }

  func testExplicitReportNullUnknownDuplicateAndXPDisagreementFailBeforeMutation() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4), owner = try await account(store)
    let base = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request())) as? [String: Any])
    for report: Any in [NSNull(), ["version":2,"stopOnLetter":false,"modifiers":[]] as [String:Any],
      ["version":1,"stopOnLetter":false,"modifiers":["unknown"]],
      ["version":1,"stopOnLetter":false,"modifiers":["crtVisual","crtVisual"]]] {
      var json = base; json["rankingEvidence"] = report
      XCTAssertThrowsError(try JSONDecoder().decode(ResultSubmissionRequest.self,
        from: JSONSerialization.data(withJSONObject: json)))
    }
    var disagreement = base
    disagreement["rankingEvidence"] = ["version":1,"stopOnLetter":false,"modifiers":["uppercase"]] as [String:Any]
    let invalid = try JSONDecoder().decode(ResultSubmissionRequest.self,
      from: JSONSerialization.data(withJSONObject: disagreement))
    do { _ = try await store.submitResult(invalid, accessToken: owner.accessToken, now: now); XCTFail("Disagreement") }
    catch { XCTAssertTrue(error is ResultStoreError) }
    let history = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(history.total, 0)
  }

  func testDevelopmentWaivesTimeOnlyAndOptOutStillSuppressesBothRankings() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,minimumLeaderboardTypingSeconds:7_200,
      rankingEnvironment:.development), owner = try await account(store)
    let first = try await store.submitResult(request(),accessToken:owner.accessToken,now:now)
    XCTAssertTrue(first.leaderboardEligible); XCTAssertEqual(first.weeklyExperienceRank,1)
    _ = try await store.updateProfile(.init(leaderboardOptedOut:true),accessToken:owner.accessToken,now:now)
    let hidden = try await store.submitResult(request(),accessToken:owner.accessToken,now:now)
    XCTAssertFalse(hidden.leaderboardEligible); XCTAssertNil(hidden.weeklyExperienceRank)
    let blocked = try await store.submitResult(request(modifiers:["uppercase"]),accessToken:owner.accessToken,now:now)
    XCTAssertFalse(blocked.leaderboardEligible)
  }

  func testZeroXPDoesNotReturnAnExistingWeeklyRankAndSnapshotSurvivesConfigurationChange() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-ranking-zero-\(UUID())")
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
    defer { try? FileManager.default.removeItem(at:directory) }
    let file = directory.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development), owner = try await account(store)
    let input = try request()
    let first = try await store.submitResult(input,accessToken:owner.accessToken,now:now)
    let disabled = ExperienceCalculationConfiguration(enabled:false,gainMultiplier:1,funboxBonus:0,
      minimumDailyBonus:0,maximumDailyBonus:0,streakEnabled:false,maximumStreakDays:0,maximumStreakMultiplier:0)
    let reloaded = try AuthStore(fileURL:file,bcryptCost:4,experienceConfiguration:disabled,rankingEnvironment:.development)
    let zero = try await reloaded.submitResult(request(),accessToken:owner.accessToken,now:now)
    XCTAssertEqual(zero.experienceGained,0); XCTAssertNil(zero.weeklyExperienceRank)
    let duplicate = try await reloaded.submitResult(input,accessToken:owner.accessToken,now:now)
    XCTAssertEqual(duplicate.experienceGained,first.experienceGained); XCTAssertEqual(duplicate.weeklyExperienceRank,1)
    let board = try await reloaded.experienceLeaderboard(now:now)
    XCTAssertEqual(board.entries.first?.totalExperience,first.experienceGained)
  }

  func testCapabilityAndAuthenticatedHTTPRoundTripKeepRankingEvidence() async throws {
    let app = try await Application.make(.testing)
    let store = try AuthStore(fileURL:nil,bcryptCost:4)
    let clock = Date.now
    let owner = try await store.register(.init(email:"ranking-http@example.com",password:"a secure password",
      displayName:"Ranking HTTP"),now:clock)
    do {
      try configure(app,authStore:store)
      try await app.test(.GET,"/v1/capabilities",afterResponse: { response async throws in
        XCTAssertEqual(try response.content.decode(ServiceCapabilitiesResponse.self).capabilities["resultRankingEvidence"],.available)
      })
      let input = try request(stop:true,endingAt:clock)
      try await app.test(.POST,"/v1/results",beforeRequest: { request async throws in
        request.headers.bearerAuthorization = .init(token:owner.accessToken)
        try request.content.encode(input)
      },afterResponse: { response async throws in
        XCTAssertEqual(response.status,.ok)
        XCTAssertFalse(try response.content.decode(ResultSubmissionResponse.self).leaderboardEligible)
      })
      let history = try await store.result(id:input.id,credential:.accessToken(owner.accessToken),now:clock)
      XCTAssertEqual(history.rankingEvidence,input.rankingEvidence)
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
}
