import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class ExperienceEvidenceSubmissionTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 50_000)
  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
  private func payload() throws -> [String: Any] {
    let request = ResultSubmissionRequest(id: UUID(), mode: "words", language: "english",
      durationSeconds: nil, wordLimit: 25, wpm: 60, rawWpm: 60, accuracy: 100,
      errorCount: 0, eventCount: 75, practiceTiming: .init(version: 1,
        terminalEngagedMilliseconds: 12_750, priorAttemptEngagedMilliseconds: 0),
      inputMetrics: .init(version: 1, correctAttempts: 75, totalAttempts: 75,
        creditedUnits: 75, retainedUnits: 75),
      startedAt: now.addingTimeInterval(-15), finishedAt: now)
    var json = try object(request)
    json["experienceEvidence"] = ["version": 1, "characterCounts": [75, 0, 0, 0],
      "scoringUnitBasis": "utf16", "durationSeconds": 15.0, "afkSeconds": 2.25,
      "punctuation": true, "numbers": true, "modifiers": ["mirrorVisual"]]
    return json
  }
  private func decode(_ json: [String: Any]) throws -> ResultSubmissionRequest {
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity",
      negativeInfinity: "-Infinity", nan: "NaN")
    return try decoder.decode(ResultSubmissionRequest.self, from: JSONSerialization.data(withJSONObject: json))
  }
  func testUnknownExplicitExperienceVersionCannotBeIgnored() throws {
    var json = try payload(); json["experienceEvidence"] = ["version": 2]
    XCTAssertThrowsError(try decode(json))
  }
  func testAcceptedHistoryRetainsAnonymousTerminalEvidenceWithoutChangingXP() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(.init(email: "xp-evidence@example.com",
      password: "a secure password", displayName: "XP Evidence"), now: now)
    let json = try payload(), request = try decode(json)
    let receipt = try await store.submitResult(request, accessToken: owner.accessToken, now: now)
    XCTAssertEqual(receipt.experienceGained, 18)
    let page = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    let saved = try XCTUnwrap(page.results.first)
    XCTAssertEqual(try object(saved)["experienceEvidence"] as? NSDictionary,
      json["experienceEvidence"] as? NSDictionary)
  }

  func testExplicitShapeVersionCountsTimingAndIdentityAreStrict() throws {
    let base = try payload(), evidence = try XCTUnwrap(base["experienceEvidence"] as? [String: Any])
    var bad: [Any] = [NSNull(), [:]]
    for key in evidence.keys { var value = evidence; value.removeValue(forKey: key); bad.append(value) }
    for (key, marker): (String, Any) in [("characterCounts", [0,0,0]), ("characterCounts", [0,-1,0,0]),
      ("characterCounts", [Int.max,0,0,0]), ("scoringUnitBasis", "unknown"),
      ("afkSeconds", "NaN"), ("durationSeconds", "Infinity"), ("afkSeconds", 16),
      ("punctuation", "true"), ("modifiers", ["unknown"]), ("modifiers", ["lazyLatin"]),
      ("modifiers", ["mirrorVisual", "mirrorVisual"])] {
      var value = evidence; value[key] = marker; bad.append(value)
    }
    for value in bad {
      var json = base; json["experienceEvidence"] = value
      XCTAssertThrowsError(try decode(json))
    }
    for marker: Any? in [nil, NSNull()] {
      var json = base; json["restartCount"] = marker
      XCTAssertThrowsError(try decode(json))
    }
  }

  func testSemanticConflictsAreRejectedBeforeHistoryAndTotalsChange() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(.init(email: "xp-evidence-binding@example.com",
      password: "a secure password", displayName: "Binding"), now: now)
    for mutation in 0..<8 {
      var json = try payload()
      var evidence = try XCTUnwrap(json["experienceEvidence"] as? [String: Any])
      switch mutation {
      case 0: evidence["characterCounts"] = [74,0,0,0]
      case 1: evidence["characterCounts"] = [75,1,0,0]
      case 2: evidence["scoringUnitBasis"] = "koreanJamo"
      case 3: evidence["afkSeconds"] = 2
      case 4: evidence["durationSeconds"] = 14
      case 5: evidence["modifiers"] = ["polyglot"]
      case 6: json.removeValue(forKey: "inputMetrics")
      default: json.removeValue(forKey: "practiceTiming")
      }
      json["experienceEvidence"] = evidence
      do {
        _ = try await store.submitResult(decode(json), accessToken: owner.accessToken, now: now)
        XCTFail("Conflicting report must not change account state")
      } catch let error as ResultStoreError { XCTAssertEqual(error, .invalidResult) }
    }
    let page = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(page.total, 0)
    let stats = await store.publicPracticeStats(); XCTAssertEqual(stats.startedTestCount, 0)
  }

  func testAdapterUsesPreciseCountersAuthoritativeDifficultyAndEachPriorAttempt() throws {
    var json = try payload()
    json["restartCount"] = 1
    json["incompletePractice"] = ["version": 1, "attempts": [["accuracy": 100, "seconds": 1.5]]]
    json["practiceTiming"] = ["version": 1, "terminalEngagedMilliseconds": 12_750,
      "priorAttemptEngagedMilliseconds": 1_500]
    let input = try ExperienceEvidenceAdapter.input(for: decode(json))
    XCTAssertEqual(input.characterCounts, [75,0,0,0]); XCTAssertEqual(input.afkSeconds, 2.25)
    XCTAssertEqual(input.funboxDifficultyLevels, [3])
    XCTAssertEqual(input.incompleteAttempts, [.init(accuracy: 100, seconds: 1.5)])
    let award = try SourceStyleExperienceCalculator.calculate(input, configuration: .init(enabled: true,
      gainMultiplier: 1, funboxBonus: 0.1, minimumDailyBonus: 0, maximumDailyBonus: 0,
      streakEnabled: false, maximumStreakDays: 0, maximumStreakMultiplier: 0), context:
        .init(previousResultMilliseconds: nil, nowMilliseconds: 50_000_000, currentTotalXP: 0, streakDays: 0))
    XCTAssertEqual(award.xp, 62)
    XCTAssertEqual(award.breakdown?["incomplete"], 2)
    for mode in ["time", "words", "quote", "custom", "zen"] {
      var variant = json; variant["mode"] = mode
      let value = try ExperienceEvidenceAdapter.input(for: decode(variant))
      XCTAssertEqual(value.mode, mode)
      XCTAssertEqual(value.punctuation, true); XCTAssertEqual(value.numbers, true)
    }
    json["experienceEvidence"] = nil
    XCTAssertThrowsError(try ExperienceEvidenceAdapter.input(for: decode(json)))
  }

  func testPartialPrefixSpaceDiagnosticDoesNotEraseCreditedUnits() throws {
    // Source classifier: input "ab ", target "ab cd", active-prefix credit.
    // correctWord=3, allCorrect=2, extra=1. correctWord and extra overlap.
    let evidence = ResultExperienceEvidence(characterCounts: [3,0,1,0], scoringUnitBasis: .utf16,
      durationSeconds: 15, afkSeconds: 0, punctuation: false, numbers: false, modifiers: [])
    XCTAssertTrue(evidence.isBound(to: .init(version: 1, correctAttempts: 3, totalAttempts: 3,
      creditedUnits: 3, retainedUnits: 3), duration: 15, practiceTiming:
        .init(version: 1, terminalEngagedMilliseconds: 15_000, priorAttemptEngagedMilliseconds: 0),
      language: "english", restartCount: 0))
  }

  func testCompleteCatalogMatchesEveryActualPinnedFunboxDifficulty() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned source for the full identity differential")
    }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Scripts/check-source-experience-calculation.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    let node = ProcessInfo.processInfo.environment["TYPEBAR_XP_SOURCE_NODE"]
    process.executableURL = URL(fileURLWithPath: node ?? "/usr/bin/env")
    process.arguments = (node == nil ? ["node"] : []) + ["--experimental-vm-modules", script.path, reference, "--emit-catalog"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    struct Entry: Decodable { let name: String; let difficulty: Double }
    struct Document: Decodable { let referenceCommit: String; let catalog: [Entry] }
    let document = try JSONDecoder().decode(Document.self, from: data)
    XCTAssertEqual(document.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41")
    let mapped = ExperienceModifierCatalog.entries.values.compactMap(\.sourceName)
    XCTAssertEqual(Set(mapped), Set(document.catalog.map(\.name)))
    XCTAssertEqual(mapped.count, 48); XCTAssertEqual(Set(mapped).count, 48)
    for entry in document.catalog {
      XCTAssertEqual(ExperienceModifierCatalog.entries.values.first { $0.sourceName == entry.name }?.difficulty,
        entry.difficulty, entry.name)
    }
    XCTAssertEqual(ExperienceModifierCatalog.entries.count, 51)
    XCTAssertEqual(Set(ExperienceModifierCatalog.entries.filter { $0.value.sourceName == nil }.keys),
      ["symbolStream", "correctBeforeAdvance", "clearCurrentWordOnError"])
  }

  func testDiskReloadFirstSnapshotAndGenuineLegacyArePreserved() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-xp-evidence-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }
    let store = try AuthStore(fileURL: file, bcryptCost: 4)
    let owner = try await store.register(.init(email: "xp-evidence-disk@example.com",
      password: "a secure password", displayName: "Disk"), now: now)
    let json = try payload(), request = try decode(json)
    _ = try await store.submitResult(request, accessToken: owner.accessToken, now: now)
    var duplicate = json, report = try XCTUnwrap(json["experienceEvidence"] as? [String: Any])
    report["modifiers"] = ["noQuit"]; duplicate["experienceEvidence"] = report
    _ = try await store.submitResult(decode(duplicate), accessToken: owner.accessToken, now: now)
    var old = try payload(); old.removeValue(forKey: "experienceEvidence")
    _ = try await store.submitResult(decode(old), accessToken: owner.accessToken, now: now)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4)
    let page = try await reloaded.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(page.total, 2)
    XCTAssertEqual(page.results.first { $0.id == request.id }?.experienceEvidence, request.experienceEvidence)
    XCTAssertNil(page.results.first { $0.id != request.id }?.experienceEvidence)
    XCTAssertNil(page.results.first { $0.id != request.id }?.restartCount)
    let repeated = try await reloaded.submitResult(request, accessToken: owner.accessToken, now: now)
    XCTAssertEqual(repeated.totalExperience, 36); XCTAssertEqual(repeated.experienceGained, 18)
  }

  func testBadStoredMetadataRefusesReloadAndPreservesOriginalBytes() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-xp-evidence-corrupt-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }
    let store = try AuthStore(fileURL: file, bcryptCost: 4)
    let owner = try await store.register(.init(email: "xp-evidence-corrupt@example.com",
      password: "a secure password", displayName: "Corrupt"), now: now)
    _ = try await store.submitResult(decode(payload()), accessToken: owner.accessToken, now: now)
    let original = try Data(contentsOf: file)
    for mutation in 0..<7 {
      var json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
      var rows = try XCTUnwrap(json["results"] as? [[String: Any]])
      switch mutation {
      case 0: rows[0]["experienceEvidence"] = NSNull()
      case 1: rows[0]["experienceEvidence"] = ["version": 2]
      case 2: rows[0].removeValue(forKey: "inputMetrics")
      case 3: rows[0].removeValue(forKey: "practiceTiming")
      case 4: rows[0].removeValue(forKey: "restartCount")
      default:
        var evidence = try XCTUnwrap(rows[0]["experienceEvidence"] as? [String: Any])
        evidence[mutation == 5 ? "afkSeconds" : "characterCounts"] = mutation == 5 ? 2.0 : [74,0,0,0] as Any
        rows[0]["experienceEvidence"] = evidence
      }
      json["results"] = rows
      let bad = try JSONSerialization.data(withJSONObject: json); try bad.write(to: file, options: .atomic)
      XCTAssertThrowsError(try AuthStore(fileURL: file, bcryptCost: 4))
      XCTAssertEqual(try Data(contentsOf: file), bad)
    }
    try original.write(to: file, options: .atomic)
    _ = try AuthStore(fileURL: file, bcryptCost: 4)
  }

  func testPersistenceFailureRollsBackEvidenceAndRetrySavesOnlyOnce() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-xp-evidence-failure-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("store.json"), backup = directory.appendingPathComponent("backup.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4)
    let owner = try await store.register(.init(email: "xp-evidence-failure@example.com",
      password: "a secure password", displayName: "Failure"), now: now)
    let request = try decode(payload())
    try FileManager.default.moveItem(at: file, to: backup)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    do {
      _ = try await store.submitResult(request, accessToken: owner.accessToken, now: now)
      XCTFail("Actual store rename must fail")
    } catch { }
    let empty = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(empty.total, 0)
    let stats = await store.publicPracticeStats(); XCTAssertEqual(stats.startedTestCount, 0)
    try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: backup, to: file)
    _ = try await store.submitResult(request, accessToken: owner.accessToken, now: now)
    let page = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(page.total, 1); XCTAssertEqual(page.results.first?.experienceEvidence, request.experienceEvidence)
  }

  func testPrivateOwnerIsolationAndConcurrentDuplicatesKeepOneSnapshot() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(.init(email: "xp-evidence-owner@example.com",
      password: "a secure password", displayName: "Owner"), now: now)
    let request = try decode(payload()), instant = now
    async let first = store.submitResult(request, accessToken: owner.accessToken, now: instant)
    async let second = store.submitResult(request, accessToken: owner.accessToken, now: instant)
    let responses = try await [first, second]
    XCTAssertEqual(responses[0].totalExperience, 18); XCTAssertEqual(responses[1].totalExperience, 18)
    let other = try await store.register(.init(email: "xp-evidence-other@example.com",
      password: "a secure password", displayName: "Other"), now: now)
    let hidden = try await store.results(.init(), credential: .accessToken(other.accessToken), now: now)
    XCTAssertTrue(hidden.results.isEmpty)
    do {
      _ = try await store.result(id: request.id, credential: .accessToken(other.accessToken), now: now)
      XCTFail("Private terminal counts are not readable by another account")
    } catch let error as AuthStoreError { XCTAssertEqual(error, .resultNotFound) }
    let page = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(page.total, 1)
  }

  func testActualRoutesAdvertiseCapabilityAuthenticateAndKeepPrivateEvidence() async throws {
    let app = try await Application.make(.testing), live = Date.now
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(.init(email: "xp-evidence-http@example.com",
      password: "a secure password", displayName: "HTTP"), now: live)
    var json = try payload(); json["startedAt"] = live.addingTimeInterval(-15).timeIntervalSinceReferenceDate
    json["finishedAt"] = live.timeIntervalSinceReferenceDate
    let request = try decode(json)
    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/capabilities") { response async throws in
        XCTAssertEqual(try response.content.decode(ServiceCapabilitiesResponse.self)
          .capabilities["resultExperienceEvidence"], .available)
      }
      try await app.test(.POST, "v1/results", beforeRequest: { outgoing async throws in
        try outgoing.content.encode(request)
      }, afterResponse: { response async throws in XCTAssertEqual(response.status, .unauthorized) })
      try await app.test(.POST, "v1/results", beforeRequest: { outgoing async throws in
        outgoing.headers.bearerAuthorization = .init(token: owner.accessToken); try outgoing.content.encode(request)
      }, afterResponse: { response async throws in XCTAssertEqual(response.status, .ok) })
      try await app.test(.GET, "v1/results", beforeRequest: { outgoing async throws in
        outgoing.headers.bearerAuthorization = .init(token: owner.accessToken)
      }, afterResponse: { response async throws in
        let page = try response.content.decode(ResultListResponse.self)
        XCTAssertEqual(page.results.first?.experienceEvidence, request.experienceEvidence)
      })
      var invalid = json, report = try XCTUnwrap(json["experienceEvidence"] as? [String: Any])
      report["afkSeconds"] = 2; invalid["experienceEvidence"] = report
      let bad = try decode(invalid)
      try await app.test(.POST, "v1/results", beforeRequest: { outgoing async throws in
        outgoing.headers.bearerAuthorization = .init(token: owner.accessToken); try outgoing.content.encode(bad)
      }, afterResponse: { response async throws in XCTAssertEqual(response.status, .badRequest) })
      try await app.asyncShutdown()
    } catch { try await app.asyncShutdown(); throw error }
  }
}
