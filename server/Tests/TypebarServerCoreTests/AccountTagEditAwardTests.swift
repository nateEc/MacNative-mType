import Foundation
import XCTest
@testable import TypebarServerCore

final class AccountTagEditAwardTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000.875)
  private func account(_ store: AuthStore, name: String = "Edit") async throws -> AuthSessionResponse {
    try await store.register(.init(email: "\(name)@example.com", password: "a secure password", displayName: name), now: now)
  }
  private func request(speed: Double = 60.49, ids: [UUID]? = [], bailout: Bool = false) -> ResultSubmissionRequest {
    let units = Int((speed * 15 / 12).rounded())
    return .init(id: UUID(), mode: "time", language: "english", durationSeconds: bailout ? 120 : 15,
      wordLimit: nil, wpm: Int(speed.rounded()), rawWpm: Int(speed.rounded()), accuracy: 100,
      consistency: 80, errorCount: 0, eventCount: units,
      personalBestConfiguration: .init(difficulty: "normal", punctuation: false, numbers: false, lazyMode: false),
      speedPrecision: .init(wpm: speed, rawWpm: speed), accountTagIDs: ids, bailedOut: bailout ? true : nil,
      startedAt: now.addingTimeInterval(-Double(units) * 12 / speed), finishedAt: now)
  }
  private func root() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-tag-edit-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false); return url
  }
  private func object(_ file: URL) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
  }
  func testActualPinnedControllerAndDALAgreeOnEditAdmissionAndWholeBooks() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else { throw XCTSkip("Pinned reference required") }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Scripts/check-source-account-tag-edit-awards.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", script.path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    struct Admission: Decodable { let mode: String; let accuracy: Double; let stopOnLetter: Bool
      let bailedOut: Bool; let modifiers: [String]; let eligible: Bool }
    struct Best: Decodable { let wpm: Double; let raw: Double; let acc: Double; let consistency: Double; let timestamp: Int }
    struct Book: Decodable { let id: UUID; let bests: [Best] }
    struct Step: Decodable { let ids: [UUID]; let clock: Int; let clearID: UUID?; let tagPbs: [UUID]; let books: [Book] }
    struct Fixture: Decodable { let mode: String; let mode2: String; let difficulty: String; let language: String
      let punctuation: Bool; let numbers: Bool; let lazyMode: Bool; let steps: [Step] }
    struct Document: Decodable { let referenceCommit: String; let admission: [Admission]; let lifecycle: [Fixture] }
    let data = try JSONDecoder().decode(Document.self, from: bytes)
    XCTAssertEqual(data.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(data.admission.count, 2000); XCTAssertEqual(data.lifecycle.count, 192)
    let nativeIDs = Dictionary(uniqueKeysWithValues: ExperienceModifierCatalog.entries.compactMap { id, value in
      value.sourceName.map { ($0, id) }
    })
    for item in data.admission {
      let input = RankingAdmissionInput(mode: item.mode, accuracy: item.accuracy, bailedOut: item.bailedOut,
        modifiers: try item.modifiers.map { try XCTUnwrap(nativeIDs[$0]) }, stopOnLetter: item.stopOnLetter, evidence: nil)
      XCTAssertEqual(AccountTagEditAdmission.isEligible(input), item.eligible, "\(input)")
    }
    let owner = UUID(), a = try XCTUnwrap(UUID(uuidString: "11111111-1111-4111-8111-111111111111"))
    let b = try XCTUnwrap(UUID(uuidString: "22222222-2222-4222-8222-222222222222"))
    for fixture in data.lifecycle {
      func snapshot(speed: Double, raw: Double, at clock: Int) throws -> PersonalBestSnapshot {
        try PersonalBestSnapshot.make(.init(id: UUID(), mode: fixture.mode, language: fixture.language,
          durationSeconds: fixture.mode == "time" ? 15 : nil, wordLimit: fixture.mode == "words" ? 25 : nil,
          wpm: Int(speed.rounded()), rawWpm: Int(raw.rounded()), accuracy: 98, consistency: 80, errorCount: 1, eventCount: 75,
          personalBestConfiguration: .init(difficulty: fixture.difficulty, punctuation: fixture.punctuation,
            numbers: fixture.numbers, lazyMode: fixture.lazyMode), speedPrecision: .init(wpm: speed, rawWpm: raw),
          startedAt: now.addingTimeInterval(-15), finishedAt: now, mode2: fixture.mode2), userID: owner,
          acceptedAt: Date(timeIntervalSince1970: Double(clock) / 1000), origin: .accepted)
      }
      var directory = AccountTagDirectory()
      directory.tags = [a,b].map { .init(id: $0, userID: owner, name: "desk") }
      let initialClock = try XCTUnwrap(fixture.steps.first).clock - 1
      directory.accept(try snapshot(speed: 100, raw: 110, at: initialClock), tagIDs: [a])
      let source = try snapshot(speed: 80.49, raw: 95.75, at: initialClock)
      for step in fixture.steps {
        if let clear = step.clearID { directory.remove(id: clear, clearOnly: true) }
        XCTAssertEqual(Set(try directory.acceptHistoryEdit(source, at: step.clock, tagIDs: step.ids)), Set(step.tagPbs))
        for book in step.books {
          let actual = try XCTUnwrap(directory.tags.first { $0.id == book.id }).personalBests
          XCTAssertEqual(actual.count, book.bests.count)
          for (best, expected) in zip(actual, book.bests) {
            XCTAssertEqual(best.effectiveWpm, expected.wpm)
            XCTAssertEqual(best.speedPrecision?.rawWpm ?? Double(best.rawWpm), expected.raw)
            XCTAssertEqual(best.effectiveAccuracy, expected.acc); XCTAssertEqual(best.consistency, expected.consistency)
            XCTAssertEqual(best.acceptedAtMilliseconds, expected.timestamp)
          }
        }
      }
    }
  }
  func testBailoutEditAwardsWithoutChangingSubmissionPBAndSurvivesHistoryDeletion() async throws {
    let folder = try root(); defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("state.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await account(store)
    let tag = try await store.createAccountTag(.init(name: "desk"), accessToken: owner.accessToken, now: now)
    // 75 units at 60 WPM lasts exactly 15 seconds; configured limit is 120.
    let input = request(speed: 60, bailout: true)
    let receipt = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    let before = try object(file)
    let edit = try await store.updateAccountResultTagIDs(id: input.id, request: .init(tagIDs: [tag.id]), accessToken: owner.accessToken, now: now.addingTimeInterval(1))
    XCTAssertEqual(edit.tagPbs, [tag.id]); XCTAssertTrue(edit.result.bailedOut == true)
    let after = try object(file)
    for key in ["experienceAwards", "personalBestLedger"] {
      XCTAssertEqual(try JSONSerialization.data(withJSONObject: XCTUnwrap(before[key]), options: [.sortedKeys]),
        try JSONSerialization.data(withJSONObject: XCTUnwrap(after[key]), options: [.sortedKeys]))
    }
    let retry = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    XCTAssertEqual(receipt.experienceGained, retry.experienceGained)
    _ = try await store.deleteResults(.init(currentPassword: "a secure password"), accessToken: owner.accessToken, now: now)
    let cold = try AuthStore(fileURL: file, bcryptCost: 4)
    let current = try await cold.accountTags(accessToken: owner.accessToken, now: now)
    XCTAssertEqual(current.tags.first?.personalBests.first?.acceptedAtMilliseconds, 1_800_000_001_875)
  }
  func testFailedEditPersistenceRollsBackHistoryPBAndProofTogether() async throws {
    let folder = try root(); defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("state.json"), backup = folder.appendingPathComponent("saved.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await account(store)
    let tag = try await store.createAccountTag(.init(name: "desk"), accessToken: owner.accessToken, now: now)
    let input = request(); _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    let original = try Data(contentsOf: file)
    try FileManager.default.moveItem(at: file, to: backup)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    do { _ = try await store.updateAccountResultTagIDs(id: input.id, request: .init(tagIDs: [tag.id]), accessToken: owner.accessToken, now: now); XCTFail("Write failure") } catch {}
    let tags = try await store.accountTags(accessToken: owner.accessToken, now: now)
    let result = try await store.result(id: input.id, credential: .accessToken(owner.accessToken), now: now)
    XCTAssertTrue(try XCTUnwrap(tags.tags.first).personalBests.isEmpty); XCTAssertEqual(result.accountTagIDs, [])
    try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: backup, to: file)
    XCTAssertEqual(try Data(contentsOf: file), original)
    _ = try await store.updateAccountResultTagIDs(id: input.id, request: .init(tagIDs: [tag.id]), accessToken: owner.accessToken, now: now.addingTimeInterval(1))
    _ = try AuthStore(fileURL: file, bcryptCost: 4)
  }
  func testDamagedOrDowngradedEditProofCannotBecomeAColdEmptyFallback() async throws {
    let folder = try root(); defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("state.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await account(store)
    let tag = try await store.createAccountTag(.init(name: "desk"), accessToken: owner.accessToken, now: now)
    let input = request(); _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    _ = try await store.updateAccountResultTagIDs(id: input.id, request: .init(tagIDs: [tag.id]), accessToken: owner.accessToken, now: now.addingTimeInterval(2))
    let original = try object(file), directory = try XCTUnwrap(original["accountTagDirectory"] as? [String: Any])
    let proofs = try XCTUnwrap(directory["historyEditAwards"] as? [[String: Any]])
    XCTAssertEqual(proofs.count, 1); XCTAssertEqual(directory["version"] as? Int, 2)
    var invalids: [[String: Any]] = []
    var missing = directory; missing.removeValue(forKey: "historyEditAwards"); invalids.append(missing)
    for value: Any in [NSNull(), [], proofs + proofs] {
      var bad = directory; bad["historyEditAwards"] = value; invalids.append(bad)
    }
    var foreign = proofs[0]; foreign["tagID"] = UUID().uuidString
    var wrongOwner = directory; wrongOwner["historyEditAwards"] = [foreign]; invalids.append(wrongOwner)
    var source = try XCTUnwrap(proofs[0]["source"] as? [String: Any]); source["language"] = "spanish"
    var changed = proofs[0]; changed["source"] = source
    var wrongSource = directory; wrongSource["historyEditAwards"] = [changed]; invalids.append(wrongSource)
    var old = directory; old["version"] = 1; invalids.append(old)
    for invalid in invalids {
      var state = original; state["accountTagDirectory"] = invalid
      let bytes = try JSONSerialization.data(withJSONObject: state); try bytes.write(to: file)
      XCTAssertThrowsError(try AuthStore(fileURL: file, bcryptCost: 4))
      XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
  }
  func testNewSubmissionAndTagClearPruneOnlyTheirOwnEditProofs() async throws {
    let folder = try root(); defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("state.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await account(store), other = try await account(store, name: "Other")
    let first = try await store.createAccountTag(.init(name: "desk"), accessToken: owner.accessToken, now: now)
    let second = try await store.createAccountTag(.init(name: "desk"), accessToken: other.accessToken, now: now)
    for (user, tag) in [(owner,first),(other,second)] {
      let input = request(); _ = try await store.submitResult(input, accessToken: user.accessToken, now: now)
      _ = try await store.updateAccountResultTagIDs(id: input.id, request: .init(tagIDs: [tag.id]), accessToken: user.accessToken, now: now.addingTimeInterval(1))
    }
    _ = try await store.submitResult(request(speed: 90.49, ids: [first.id]), accessToken: owner.accessToken, now: now.addingTimeInterval(2))
    let directory = try XCTUnwrap(try object(file)["accountTagDirectory"] as? [String: Any])
    XCTAssertEqual((directory["historyEditAwards"] as? [[String: Any]])?.count, 1)
    try await store.deleteAccountTag(id: first.id, clearPersonalBestsOnly: true, accessToken: owner.accessToken, now: now)
    _ = try await store.resetAccount(.init(currentPassword: "a secure password"), accessToken: owner.accessToken, now: now)
    let cold = try AuthStore(fileURL: file, bcryptCost: 4)
    let kept = try await cold.accountTags(accessToken: other.accessToken, now: now)
    XCTAssertEqual(kept.tags.first?.personalBests.first?.preciseWpm, 60.49)
    try await cold.deleteAccountTag(id: second.id, accessToken: other.accessToken, now: now)
    _ = try AuthStore(fileURL: file, bcryptCost: 4)
  }
}
