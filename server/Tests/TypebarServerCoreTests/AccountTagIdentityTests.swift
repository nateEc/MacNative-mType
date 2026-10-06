import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class AccountTagIdentityTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000.875)
  private func account(_ store: AuthStore, name: String = "Owner") async throws -> AuthSessionResponse {
    try await store.register(.init(email: "\(name)@example.com", password: "a secure password", displayName: name), now: now)
  }
  private func result(ids: [UUID]? = nil, id: UUID = UUID(), speed: Double = 60.49,
    config: ResultPersonalBestConfiguration? = .init(difficulty: "normal", punctuation: false, numbers: false, lazyMode: false)) -> ResultSubmissionRequest {
    let units = Int((speed * 15 / 12).rounded())
    return .init(id: id, mode: "time", language: "english", durationSeconds: 15, wordLimit: nil,
      wpm: Int(speed.rounded()), rawWpm: Int(speed.rounded()), accuracy: 100, consistency: 80,
      errorCount: 0, eventCount: units, personalBestConfiguration: config,
      speedPrecision: .init(wpm: speed, rawWpm: speed), accountTagIDs: ids,
      startedAt: now.addingTimeInterval(-Double(units) * 12 / speed), finishedAt: now)
  }
  private func tag(_ store: AuthStore, _ owner: AuthSessionResponse, name: String = "desk") async throws -> AccountTagResponse {
    try await store.createAccountTag(.init(name: name), accessToken: owner.accessToken, now: now)
  }
  func testFifteenStableTagsAllowSameNamesButRejectInvalidNames() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4), owner = try await account(store)
    var ids = Set<UUID>()
    for _ in 0..<15 { ids.insert(try await tag(store, owner).id) }
    XCTAssertEqual(ids.count, 15)
    do { _ = try await tag(store, owner); XCTFail("sixteenth tag") } catch {}
    let empty = try AuthStore(fileURL: nil, bcryptCost: 4), user = try await account(empty)
    for name in ["", "_x", "x_", "a__b", "a-_b", "desk chair", "中文", "café", String(repeating: "a", count: 17)] {
      do { _ = try await tag(empty, user, name: name); XCTFail(name) } catch {}
    }
    for name in ["Desk-1", "desk_chair", String(repeating: "a", count: 16)] { _ = try await tag(empty, user, name: name) }
  }
  func testRenameKeepsIdentityHistoryAndWholeTagBest() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, rankingEnvironment: .development), owner = try await account(store)
    let first = try await tag(store, owner), sameName = try await tag(store, owner)
    let initial = result(ids: [first.id])
    _ = try await store.submitResult(initial, accessToken: owner.accessToken, now: now)
    let renamed = try await store.editAccountTag(id: first.id, request: .init(name: "new_desk"), accessToken: owner.accessToken, now: now)
    XCTAssertEqual(renamed.id, first.id); XCTAssertEqual(renamed.personalBests.first?.id, initial.id)
    XCTAssertEqual(renamed.personalBests.first?.acceptedAtMilliseconds, 1_800_000_000_875)
    let history = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(history.results.first?.accountTagIDs, [first.id])
    _ = try await store.submitResult(result(ids: [sameName.id], speed: 40.49), accessToken: owner.accessToken, now: now)
    let directory = try await store.accountTags(accessToken: owner.accessToken, now: now)
    XCTAssertEqual(directory.tags.first(where: { $0.id == sameName.id })?.personalBests.first?.preciseWpm, 40.49)
    XCTAssertEqual(directory.tags.first(where: { $0.id == first.id })?.personalBests.first?.preciseWpm, 60.49)
  }
  func testHistoryDeletionAndPublicClearKeepTagBooksButTagClearDoesNotReviveOnRetry() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, rankingEnvironment: .development), owner = try await account(store)
    let identity = try await tag(store, owner), input = result(ids: [identity.id])
    let receipt = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    _ = try await store.deleteResults(.init(currentPassword: "a secure password"), accessToken: owner.accessToken, now: now)
    _ = try await store.resetPersonalBests(.init(currentPassword: "a secure password"), accessToken: owner.accessToken, now: now)
    let kept = try await store.accountTags(accessToken: owner.accessToken, now: now)
    XCTAssertEqual(kept.tags.first?.personalBests.first?.id, input.id)
    try await store.deleteAccountTag(id: identity.id, clearPersonalBestsOnly: true, accessToken: owner.accessToken, now: now)
    let retry = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    XCTAssertEqual(retry.experienceGained, receipt.experienceGained)
    XCTAssertEqual(retry.totalExperience, receipt.totalExperience)
    XCTAssertNil(retry.dailyLeaderboardRank, "Public clear changes current rank, not the XP receipt")
    let empty = try await store.accountTags(accessToken: owner.accessToken, now: now)
    XCTAssertTrue(try XCTUnwrap(empty.tags.first).personalBests.isEmpty)
    try await store.deleteAccountTag(id: identity.id, accessToken: owner.accessToken, now: now)
    _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
  }
  func testForeignUnknownAndRepeatedIDsFailWithoutAcceptingResult() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, rankingEnvironment: .development)
    let owner = try await account(store), other = try await account(store, name: "Other")
    let own = try await tag(store, owner), foreign = try await tag(store, other)
    for ids in [[foreign.id], [UUID()], [own.id, own.id]] {
      do { _ = try await store.submitResult(result(ids: ids), accessToken: owner.accessToken, now: now); XCTFail("invalid IDs") } catch {}
    }
    do { _ = try await store.editAccountTag(id: foreign.id, request: .init(name: "stolen"), accessToken: owner.accessToken, now: now); XCTFail("owner isolation") } catch {}
    let history = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(history.total, 0)
  }
  func testEditingHistoryAwardsTagPBAtEditTimeAndDeletionLeavesServerHistory() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, rankingEnvironment: .development), owner = try await account(store)
    let identity = try await tag(store, owner), input = result()
    _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    let edited = try await store.updateAccountResultTagIDs(id: input.id, request: .init(tagIDs: [identity.id]), accessToken: owner.accessToken, now: now.addingTimeInterval(2))
    XCTAssertEqual(edited.accountTagIDs, [identity.id])
    let changed = try await store.accountTags(accessToken: owner.accessToken, now: now)
    XCTAssertEqual(changed.tags.first?.personalBests.first?.id, input.id)
    XCTAssertEqual(changed.tags.first?.personalBests.first?.preciseWpm, 60.49)
    XCTAssertEqual(changed.tags.first?.personalBests.first?.acceptedAtMilliseconds, 1_800_000_002_875)
    try await store.deleteAccountTag(id: identity.id, accessToken: owner.accessToken, now: now)
    let history = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(history.total, 1); XCTAssertEqual(history.results.first?.accountTagIDs, [identity.id])
  }
  func testExplicitHistoryEditAfterTagClearCanAwardAgainButPOSTRetryCannot() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, rankingEnvironment: .development), owner = try await account(store)
    let identity = try await tag(store, owner), input = result(ids: [identity.id])
    let initial = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    try await store.deleteAccountTag(id: identity.id, clearPersonalBestsOnly: true, accessToken: owner.accessToken, now: now)
    _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    let cleared = try await store.accountTags(accessToken: owner.accessToken, now: now)
    XCTAssertTrue(try XCTUnwrap(cleared.tags.first).personalBests.isEmpty)
    _ = try await store.updateAccountResultTagIDs(id: input.id, request: .init(tagIDs: [identity.id]), accessToken: owner.accessToken, now: now.addingTimeInterval(1))
    let restored = try await store.accountTags(accessToken: owner.accessToken, now: now)
    XCTAssertEqual(restored.tags.first?.personalBests.first?.id, input.id)
    let retry = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    XCTAssertEqual(retry.experienceGained, initial.experienceGained)
    XCTAssertEqual(retry.totalExperience, initial.totalExperience)
  }
  func testDiskReloadValidationAndSaveFailureRollback() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-tags-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("state.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4, rankingEnvironment: .development), owner = try await account(store)
    let identity = try await tag(store, owner), input = result(ids: [identity.id])
    _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    let bytes = try Data(contentsOf: file)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4, rankingEnvironment: .development)
    let current = try await reloaded.accountTags(accessToken: owner.accessToken, now: now)
    XCTAssertEqual(current.tags.first?.personalBests.first?.acceptedAtMilliseconds, 1_800_000_000_875)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    for invalid: Any in [NSNull(), ["version": 2, "tags": []], ["version": 1, "tags": [[:]]]] {
      object["accountTagDirectory"] = invalid
      try JSONSerialization.data(withJSONObject: object).write(to: file)
      XCTAssertThrowsError(try AuthStore(fileURL: file, bcryptCost: 4))
    }
    try bytes.write(to: file)
    let backup = root.appendingPathComponent("saved.json")
    try FileManager.default.moveItem(at: file, to: backup)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    do { _ = try await store.editAccountTag(id: identity.id, request: .init(name: "not_committed"), accessToken: owner.accessToken, now: now); XCTFail("save failure") } catch {}
    let restored = try await store.accountTags(accessToken: owner.accessToken, now: now)
    XCTAssertEqual(restored.tags.first?.name, "desk")
    try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: backup, to: file)
    XCTAssertEqual(try Data(contentsOf: file), bytes)
  }
  func testEditedPBColdReloadRetainsExactSourceAndDoesNotRewriteAcceptanceReceipts() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-tag-edit-reload-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("state.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4, rankingEnvironment: .development), owner = try await account(store)
    let identity = try await tag(store, owner), input = result(ids: [])
    _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    let backup = try Data(contentsOf: file)
    let before = try XCTUnwrap(JSONSerialization.jsonObject(with: backup) as? [String: Any])
    _ = try await store.updateAccountResultTagIDs(id: input.id, request: .init(tagIDs: [identity.id]), accessToken: owner.accessToken, now: now.addingTimeInterval(2))
    let after = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    for key in ["experienceAwards", "personalBestLedger", "accountPractice", "weeklyExperienceCache", "dailyLeaderboardCache", "rewardInbox"] {
      XCTAssertEqual(try JSONSerialization.data(withJSONObject: XCTUnwrap(before[key]), options: [.sortedKeys]),
        try JSONSerialization.data(withJSONObject: XCTUnwrap(after[key]), options: [.sortedKeys]), key)
    }
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4, rankingEnvironment: .development)
    let repeated = try await reloaded.updateAccountResultTagIDs(id: input.id, request: .init(tagIDs: [identity.id]), accessToken: owner.accessToken, now: now.addingTimeInterval(3))
    XCTAssertTrue(repeated.tagPbs.isEmpty)
    _ = try await reloaded.deleteResults(.init(currentPassword: "a secure password"), accessToken: owner.accessToken, now: now)
    let cold = try AuthStore(fileURL: file, bcryptCost: 4, rankingEnvironment: .development)
    let directory = try await cold.accountTags(accessToken: owner.accessToken, now: now)
    XCTAssertEqual(directory.tags.first?.personalBests.first?.acceptedAtMilliseconds, 1_800_000_002_875)
    XCTAssertEqual(directory.tags.first?.personalBests.first?.preciseWpm, 60.49)
    let oldFile = root.appendingPathComponent("before.json"); try backup.write(to: oldFile)
    let old = try AuthStore(fileURL: oldFile, bcryptCost: 4)
    let oldDirectory = try await old.accountTags(accessToken: owner.accessToken, now: now)
    XCTAssertTrue(try XCTUnwrap(oldDirectory.tags.first).personalBests.isEmpty)
  }
  func testLegacyDirectoryAbsencePreservesTextWithoutInventingIDs() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-tags-legacy-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("state.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4, rankingEnvironment: .development), owner = try await account(store)
    let input = result()
    _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    _ = try await store.updateResultTags(id: input.id, request: .init(tags: ["desk"]), accessToken: owner.accessToken, now: now)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    object.removeValue(forKey: "accountTagDirectory")
    object.removeValue(forKey: "accountTagDirectoryManaged")
    try JSONSerialization.data(withJSONObject: object).write(to: file)
    let migrated = try AuthStore(fileURL: file, bcryptCost: 4, rankingEnvironment: .development)
    let directory = try await migrated.accountTags(accessToken: owner.accessToken, now: now)
    let history = try await migrated.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertTrue(directory.tags.isEmpty)
    XCTAssertEqual(history.results.first?.tags, ["desk"])
    XCTAssertNil(history.results.first?.accountTagIDs)
    object["accountTagDirectoryManaged"] = true
    try JSONSerialization.data(withJSONObject: object).write(to: file)
    XCTAssertThrowsError(try AuthStore(fileURL: file, bcryptCost: 4))
    let identity = try await migrated.createAccountTag(.init(name: "desk"), accessToken: owner.accessToken, now: now)
    _ = try await migrated.updateAccountResultTagIDs(id: input.id, request: .init(tagIDs: [identity.id]), accessToken: owner.accessToken, now: now)
    object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    object.removeValue(forKey: "accountTagDirectory")
    object.removeValue(forKey: "accountTagDirectoryManaged")
    try JSONSerialization.data(withJSONObject: object).write(to: file)
    XCTAssertThrowsError(try AuthStore(fileURL: file, bcryptCost: 4), "Edited history must also detect a stripped directory")
  }
  func testStrictGreaterWholeRowAndGroupingDoNotRequirePersonalPBImprovement() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, rankingEnvironment: .development), owner = try await account(store)
    let identity = try await tag(store, owner), input = result(ids: [identity.id])
    _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    _ = try await store.submitResult(result(ids: [identity.id]), accessToken: owner.accessToken, now: now.addingTimeInterval(1))
    _ = try await store.submitResult(result(ids: [identity.id], speed: 40.49,
      config: .init(difficulty: "expert", punctuation: false, numbers: false, lazyMode: false)), accessToken: owner.accessToken, now: now)
    let response = try await store.accountTags(accessToken: owner.accessToken, now: now)
    let bests = try XCTUnwrap(response.tags.first).personalBests
    XCTAssertEqual(bests.count, 2)
    XCTAssertEqual(bests.first(where: { $0.personalBestConfiguration?.difficulty == "normal" })?.id, input.id, "A tie must keep the whole first snapshot")
    XCTAssertEqual(bests.first(where: { $0.personalBestConfiguration?.difficulty == "expert" })?.preciseWpm, 40.49)
  }
  func testHTTPHistoryTagIDsRoundTripAndReadKeyCannotMutateDirectory() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, rankingEnvironment: .development)
    let owner = try await store.register(.init(email: "wire@example.com", password: "a secure password", displayName: "Wire"))
    let identity = try await store.createAccountTag(.init(name: "desk"), accessToken: owner.accessToken)
    let finished = Date()
    let input = ResultSubmissionRequest(id: UUID(), mode: "time", language: "english",
      durationSeconds: 15, wordLimit: nil, wpm: 60, rawWpm: 60, accuracy: 100,
      consistency: 80, errorCount: 0, eventCount: 75,
      startedAt: finished.addingTimeInterval(-15), finishedAt: finished)
    _ = try await store.submitResult(input, accessToken: owner.accessToken)
    let key = try await store.createDeveloperAccessKey(.init(name: "tags-reader"), accessToken: owner.accessToken)
    let app = try await Application.make(.testing)
    do {
      try configure(app, authStore: store)
      try await app.test(.PATCH, "v1/results/\(input.id)/account-tags", beforeRequest: { request async throws in
        request.headers.add(name: "Authorization", value: "Bearer \(owner.accessToken)")
        try request.content.encode(AccountResultTagIDsRequest(tagIDs: [identity.id]))
      }, afterResponse: { response async throws in
        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(try response.content.decode(AccountResultResponse.self).accountTagIDs, [identity.id])
        XCTAssertEqual(try response.content.decode(AccountResultTagEditResponse.self).tagPbs, [identity.id])
      })
      try await app.test(.GET, "v1/results/\(input.id)", beforeRequest: { request async in
        request.headers.add(name: "X-Typebar-Access-Key", value: key.accessKey)
      }, afterResponse: { response async throws in
        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(try response.content.decode(AccountResultResponse.self).accountTagIDs, [identity.id])
      })
      try await app.test(.GET, "v1/tags", beforeRequest: { request async in
        request.headers.add(name: "X-Typebar-Access-Key", value: key.accessKey)
      }, afterResponse: { response async throws in
        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(try response.content.decode(AccountTagListResponse.self).tags.first?.id, identity.id)
      })
      try await app.test(.POST, "v1/tags", beforeRequest: { request async throws in
        request.headers.add(name: "X-Typebar-Access-Key", value: key.accessKey)
        try request.content.encode(AccountTagNameRequest(name: "forbidden"))
      }, afterResponse: { response async in XCTAssertEqual(response.status, .unauthorized) })
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
  func testHTTPAdvertisesAndAuthenticatesStableDirectory() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(.init(email: "tags@example.com", password: "a secure password", displayName: "Tags"))
    let app = try await Application.make(.testing)
    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/capabilities") { response async throws in
        let capabilities = try response.content.decode(ServiceCapabilitiesResponse.self).capabilities
        XCTAssertEqual(capabilities["accountTags"], .available)
        XCTAssertEqual(capabilities["accountTagEditPersonalBests"], .available)
      }
      try await app.test(.GET, "v1/tags") { response async in XCTAssertEqual(response.status, .unauthorized) }
      try await app.test(.POST, "v1/tags", beforeRequest: { request async throws in
        request.headers.add(name: "Authorization", value: "Bearer \(owner.accessToken)")
        try request.content.encode(["name": "desk"])
      }, afterResponse: { response async throws in
        XCTAssertEqual(response.status, .ok)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
        XCTAssertNotNil((object["id"] as? String).flatMap(UUID.init(uuidString:)))
        XCTAssertEqual(object["name"] as? String, "desk")
      })
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
}
