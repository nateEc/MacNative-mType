import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class AccountFilterPresetTests: XCTestCase {
  private let snapshot = Data(#"{"personalBestOnly":false,"dateRange":"lastWeek","punctuation":"all","numbers":"all","timeLimits":["15"],"wordLimits":["25"],"modifierFilter":{"includesNoModifiers":true,"modifiers":[]},"modes":["time"],"quoteLengths":["long"]}"#.utf8)
  private func register(_ store: AuthStore, name: String) async throws -> AuthSessionResponse {
    try await store.register(.init(email: "\(name)@example.invalid", password: "a secure password", displayName: name))
  }
  func testDeploymentLimitRejectsMalformedValues() throws {
    XCTAssertEqual(try AccountFilterPresetConfiguration.maximum(from: nil), 20)
    for value in ["0", "1", "20", "100"] { XCTAssertEqual(try AccountFilterPresetConfiguration.maximum(from: value), Int(value)) }
    for value in ["", "-1", "101", "1.0", " 20", "20x", "9999999999999999999999999999"] {
      XCTAssertThrowsError(try AccountFilterPresetConfiguration.maximum(from: value))
    }
  }
  func testHTTPBoundsLargeSnapshotsAndForeignDeletion() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4), owner = try await register(store, name: "Owner"), other = try await register(store, name: "Other")
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot) as? [String: Any])
    object["tagFilter"] = ["isUnrestricted": false, "includesNoTags": true,
      "tags": (0..<400).map { "owned_\($0)_" + String(repeating: "x", count: 48) }]
    let large = AccountFilterPresetRequest(name: "Large", filterData: try JSONSerialization.data(withJSONObject: object))
    XCTAssertGreaterThan(try JSONEncoder().encode(large).count, 16_384)
    let app = try await Application.make(.testing)
    do {
      try configure(app, authStore: store)
      var id: UUID?
      try await app.test(.POST, "v1/result-filter-presets", beforeRequest: { request async throws in
        request.headers.bearerAuthorization = .init(token: owner.accessToken); try request.content.encode(large)
      }, afterResponse: { response async throws in
        XCTAssertEqual(response.status, .ok)
        if response.status == .ok { let preset = try response.content.decode(AccountFilterPresetResponse.self); id = preset.id; XCTAssertEqual(preset.document, large) }
      })
      if let id {
        for (token, status) in [(Optional<String>.none, HTTPResponseStatus.unauthorized), (other.accessToken, .notFound)] {
          try await app.test(.DELETE, "v1/result-filter-presets/\(id)", beforeRequest: { request async in
            if let token { request.headers.bearerAuthorization = .init(token: token) }
          }, afterResponse: { response async in XCTAssertEqual(response.status, status) })
        }
      }
      let oversized = AccountFilterPresetRequest(name: "Large", filterData: Data(repeating: 65, count: 65_537))
      try await app.test(.POST, "v1/result-filter-presets", beforeRequest: { request async throws in
        request.headers.bearerAuthorization = .init(token: owner.accessToken); try request.content.encode(oversized)
      }, afterResponse: { response async in XCTAssertEqual(response.status, .unprocessableEntity) })
      let invalidJSON = AccountFilterPresetRequest(name: "Bad", filterData: Data("not json".utf8))
      try await app.test(.POST, "v1/result-filter-presets", beforeRequest: { request async throws in
        request.headers.bearerAuthorization = .init(token: owner.accessToken); try request.content.encode(invalidJSON)
      }, afterResponse: { response async in XCTAssertEqual(response.status, .unprocessableEntity) })
      let unchanged = try await store.accountFilterPresets(accessToken: owner.accessToken); XCTAssertEqual(unchanged.presets.count, 1)
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
  func testColdReadLimitsDuplicateNamesOwnershipAndDeletion() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-presets-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("store.json"), initial = try AuthStore(fileURL: file, bcryptCost: 4)
    let owner = try await register(initial, name: "Owner"), other = try await register(initial, name: "Other")
    let input = AccountFilterPresetRequest(name: "Study_set", filterData: snapshot)
    var ids: [UUID] = []
    for _ in 0..<20 { ids.append(try await initial.createAccountFilterPreset(input, accessToken: owner.accessToken).id) }
    XCTAssertEqual(Set(ids).count, 20)
    do { _ = try await initial.createAccountFilterPreset(input, accessToken: owner.accessToken); XCTFail("limit") }
    catch let error as Abort { XCTAssertEqual(error.status, .conflict) }
    do { try await initial.deleteAccountFilterPreset(id: ids[0], accessToken: other.accessToken); XCTFail("foreign delete") }
    catch let error as Abort { XCTAssertEqual(error.status, .notFound) }
    let empty = try await initial.accountFilterPresets(accessToken: other.accessToken); XCTAssertTrue(empty.presets.isEmpty)
    let bytes = try Data(contentsOf: file), loaded = try AuthStore(fileURL: file, bcryptCost: 4)
    XCTAssertEqual(try Data(contentsOf: file), bytes)
    let cold = try await loaded.accountFilterPresets(accessToken: owner.accessToken)
    XCTAssertEqual(cold.presets.map(\.id), ids); XCTAssertTrue(cold.presets.allSatisfy { $0.document == input })
    try await loaded.deleteAccountFilterPreset(id: ids[0], accessToken: owner.accessToken)
    do { try await loaded.deleteAccountFilterPreset(id: ids[0], accessToken: owner.accessToken); XCTFail("missing") }
    catch let error as Abort { XCTAssertEqual(error.status, .notFound) }
    _ = try await loaded.createAccountFilterPreset(input, accessToken: owner.accessToken)
    let final = try await AuthStore(fileURL: file, bcryptCost: 4).accountFilterPresets(accessToken: owner.accessToken)
    XCTAssertEqual(final.presets.count, 20); XCTAssertFalse(final.presets.contains { $0.id == ids[0] })
  }
  func testKnownTagIDsMustBelongToOwnerButDeletedTagsDoNotDestroyStoredChoices() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4), owner = try await register(store, name: "Owner"), other = try await register(store, name: "Other")
    let tag = try await store.createAccountTag(.init(name: "Study"), accessToken: owner.accessToken)
    let input = AccountFilterPresetRequest(name: "Study", filterData: snapshot,
      accountTags: .init(knownIDs: [tag.id], selectedIDs: [tag.id], includesNoTags: false))
    do { _ = try await store.createAccountFilterPreset(input, accessToken: other.accessToken); XCTFail("foreign tag") } catch {}
    let preset = try await store.createAccountFilterPreset(input, accessToken: owner.accessToken)
    try await store.deleteAccountTag(id: tag.id, accessToken: owner.accessToken)
    let loaded = try await store.accountFilterPresets(accessToken: owner.accessToken)
    XCTAssertEqual(loaded.presets.first, preset, "Consumer reconciliation, not destructive storage rewriting")
  }
  func testMalformedDocumentsAndBadDiskNeverBecomeEmptyPresets() async throws {
    let request = AccountFilterPresetRequest(name: "Study", filterData: snapshot)
    for name in ["", ".start", "has space", "中文", String(repeating: "a", count: 17)] {
      XCTAssertThrowsError(try AccountFilterPresetRequest(name: name, filterData: snapshot).validate())
    }
    for bytes in [Data("null".utf8), Data("{}".utf8), Data(repeating: 65, count: 65_537)] {
      XCTAssertThrowsError(try AccountFilterPresetRequest(name: "Study", filterData: bytes).validate())
    }
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    for (key, value) in [("accountTags", NSNull() as Any), ("version", 2)] {
      var changed = object; changed[key] = value
      XCTAssertThrowsError(try JSONDecoder().decode(AccountFilterPresetRequest.self, from: JSONSerialization.data(withJSONObject: changed)))
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-presets-corrupt-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("store.json"), initial = try AuthStore(fileURL: file, bcryptCost: 4)
    let owner = try await register(initial, name: "Owner")
    let foreign = try await register(initial, name: "Other")
    let foreignTag = try await initial.createAccountTag(.init(name: "Foreign"), accessToken: foreign.accessToken)
    _ = try await initial.createAccountFilterPreset(request, accessToken: owner.accessToken)
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    for mutation in 0..<5 {
      var changed = original
      if mutation == 0 { changed["accountFilterPresets"] = NSNull() }
      if mutation == 1 { changed.removeValue(forKey: "accountFilterPresets") }
      if mutation == 2 { let entries = try XCTUnwrap(changed["accountFilterPresets"] as? [Any]); changed["accountFilterPresets"] = entries + entries }
      if mutation == 3 {
        var entries = try XCTUnwrap(changed["accountFilterPresets"] as? [[String: Any]]); entries[0]["userID"] = UUID().uuidString; changed["accountFilterPresets"] = entries
      }
      if mutation == 4 {
        var entries = try XCTUnwrap(changed["accountFilterPresets"] as? [[String: Any]])
        var preset = try XCTUnwrap(entries[0]["preset"] as? [String: Any])
        preset["accountTags"] = ["knownIDs": [foreignTag.id.uuidString], "selectedIDs": [foreignTag.id.uuidString], "includesNoTags": false]
        entries[0]["preset"] = preset; changed["accountFilterPresets"] = entries
      }
      let bytes = try JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys]); try bytes.write(to: file)
      XCTAssertThrowsError(try AuthStore(fileURL: file, bcryptCost: 4)); XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    var legacy = original; legacy.removeValue(forKey: "accountFilterPresets"); legacy.removeValue(forKey: "accountFilterPresetsManaged")
    let bytes = try JSONSerialization.data(withJSONObject: legacy); try bytes.write(to: file)
    let loaded = try AuthStore(fileURL: file, bcryptCost: 4), empty = try await loaded.accountFilterPresets(accessToken: owner.accessToken)
    XCTAssertTrue(empty.presets.isEmpty); XCTAssertEqual(try Data(contentsOf: file), bytes)
  }
  func testResetAndAccountDeletionPurgeOnlyTheirPresets() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4), owner = try await register(store, name: "Owner"), other = try await register(store, name: "Other")
    let input = AccountFilterPresetRequest(name: "Study", filterData: snapshot)
    _ = try await store.createAccountFilterPreset(input, accessToken: owner.accessToken)
    let survivor = try await store.createAccountFilterPreset(input, accessToken: other.accessToken)
    _ = try await store.resetAccount(.init(currentPassword: "a secure password"), accessToken: owner.accessToken)
    let empty = try await store.accountFilterPresets(accessToken: owner.accessToken); XCTAssertTrue(empty.presets.isEmpty)
    let remaining = try await store.accountFilterPresets(accessToken: other.accessToken); XCTAssertEqual(remaining.presets, [survivor])
    try await store.deleteAccount(.init(currentPassword: "a secure password"), accessToken: other.accessToken)
    let final = try await store.accountFilterPresets(accessToken: owner.accessToken); XCTAssertTrue(final.presets.isEmpty)
  }
  func testConcurrentCreatesCannotExceedOwnerLimit() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4), owner = try await register(store, name: "Owner")
    let input = AccountFilterPresetRequest(name: "Study", filterData: snapshot)
    for _ in 0..<18 { _ = try await store.createAccountFilterPreset(input, accessToken: owner.accessToken) }
    let accepted = await withTaskGroup(of: Bool.self) { group in
      for _ in 0..<10 {
        group.addTask {
          do { _ = try await store.createAccountFilterPreset(input, accessToken: owner.accessToken); return true }
          catch { return false }
        }
      }
      var total = 0; for await success in group { if success { total += 1 } }; return total
    }
    XCTAssertEqual(accepted, 2)
    let final = try await store.accountFilterPresets(accessToken: owner.accessToken); XCTAssertEqual(final.presets.count, 20)
  }
  func testLoweringLimitToZeroPreservesReadAndDeleteWithoutAllowingCreates() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-presets-limit-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4, maximumAccountFilterPresets: 1), owner = try await register(store, name: "Owner")
    let input = AccountFilterPresetRequest(name: "Study", filterData: snapshot)
    let saved = try await store.createAccountFilterPreset(input, accessToken: owner.accessToken)
    let readonly = try AuthStore(fileURL: file, bcryptCost: 4, maximumAccountFilterPresets: 0)
    let list = try await readonly.accountFilterPresets(accessToken: owner.accessToken)
    XCTAssertEqual(list.maximumPresets, 0); XCTAssertEqual(list.presets, [saved])
    do { _ = try await readonly.createAccountFilterPreset(input, accessToken: owner.accessToken); XCTFail("disabled create") }
    catch let error as Abort { XCTAssertEqual(error.status, .conflict) }
    try await readonly.deleteAccountFilterPreset(id: saved.id, accessToken: owner.accessToken)
    XCTAssertThrowsError(try AuthStore(fileURL: nil, maximumAccountFilterPresets: -1))
    XCTAssertThrowsError(try AuthStore(fileURL: nil, maximumAccountFilterPresets: 101))
  }
  func testFailedDiskCreateAndDeleteRestoreCommittedState() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-presets-failure-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("store.json"), backup = directory.appendingPathComponent("saved.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await register(store, name: "Owner")
    let input = AccountFilterPresetRequest(name: "Study", filterData: snapshot)
    let saved = try await store.createAccountFilterPreset(input, accessToken: owner.accessToken), bytes = try Data(contentsOf: file)
    try FileManager.default.moveItem(at: file, to: backup)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    do { _ = try await store.createAccountFilterPreset(input, accessToken: owner.accessToken); XCTFail("write must fail") } catch {}
    do { try await store.deleteAccountFilterPreset(id: saved.id, accessToken: owner.accessToken); XCTFail("delete must fail") } catch {}
    let unchanged = try await store.accountFilterPresets(accessToken: owner.accessToken); XCTAssertEqual(unchanged.presets, [saved])
    try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: backup, to: file)
    XCTAssertEqual(try Data(contentsOf: file), bytes)
    let loaded = try AuthStore(fileURL: file, bcryptCost: 4), cold = try await loaded.accountFilterPresets(accessToken: owner.accessToken)
    XCTAssertEqual(cold.presets, [saved])
  }
  func testHTTPPresetLifecycleRequiresAuthenticationAndPreservesSnapshot() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(.init(email: "preset@example.invalid", password: "a secure password", displayName: "Owner"))
    let app = try await Application.make(.testing)
    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/capabilities") { response async throws in
        XCTAssertEqual(try response.content.decode(ServiceCapabilitiesResponse.self).capabilities["accountFilterPresets"], .available)
      }
      try await app.test(.GET, "v1/result-filter-presets") { response async in
        XCTAssertEqual(response.status, .unauthorized)
      }
      let snapshot = Data(#"{"personalBestOnly":false,"dateRange":"lastWeek","punctuation":"all","numbers":"all","timeLimits":["15"],"wordLimits":["25"],"modifierFilter":{"includesNoModifiers":true,"modifiers":[]},"modes":["time"],"quoteLengths":["long"]}"#.utf8)
      var createdID: String?
      try await app.test(.POST, "v1/result-filter-presets", beforeRequest: { request async throws in
        request.headers.bearerAuthorization = .init(token: owner.accessToken)
        request.headers.contentType = .json
        request.body = .init(data: try JSONSerialization.data(withJSONObject: ["version": 1, "name": "Study_set", "filterData": snapshot.base64EncodedString()]))
      }, afterResponse: { response async throws in
        XCTAssertEqual(response.status, .ok)
        guard response.status == .ok else { return }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(buffer: response.body)) as? [String: Any])
        createdID = object["id"] as? String
        XCTAssertEqual(object["filterData"] as? String, snapshot.base64EncodedString())
      })
      try await app.test(.GET, "v1/result-filter-presets", beforeRequest: { request async in
        request.headers.bearerAuthorization = .init(token: owner.accessToken)
      }, afterResponse: { response async throws in
        XCTAssertEqual(response.status, .ok)
        guard response.status == .ok else { return }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(buffer: response.body)) as? [String: Any])
        XCTAssertEqual((object["presets"] as? [Any])?.count, 1)
      })
      if let createdID {
        try await app.test(.DELETE, "v1/result-filter-presets/\(createdID)", beforeRequest: { request async in
          request.headers.bearerAuthorization = .init(token: owner.accessToken)
        }, afterResponse: { response async in XCTAssertEqual(response.status, .ok) })
      }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
}
