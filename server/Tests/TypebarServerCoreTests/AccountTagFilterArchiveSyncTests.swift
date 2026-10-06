import Foundation
import XCTest
@testable import TypebarServerCore

final class AccountTagFilterArchiveSyncTests: XCTestCase {
  func testScopedFilterArchiveStaysOpaqueThroughColdReloadAndStaleWriter() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-tag-filter-sync-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("state.json"), store = try AuthStore(fileURL: file, bcryptCost: 4)
    let owner = try await store.register(.init(email: "filter-owner@example.invalid",
      password: "owned secure password", displayName: "Owner"))
    let other = try await store.register(.init(email: "filter-other@example.invalid",
      password: "owned secure password", displayName: "Other"))
    let id = UUID(), tagID = UUID()
    let archive: [String: Any] = ["version": 31, "results": [], "presets": [], "settings": [:],
      "resultFilterPresets": [["id": UUID().uuidString, "name": "Owned filter", "filter": ["accountTagFilter":
        ["version": 1, "scope": ["serverID": "aHR0cHM6Ly9vd25lZC5pbnZhbGlk", "userID": owner.user.id.uuidString],
          "knownIDs": [tagID.uuidString], "selectedIDs": [tagID.uuidString], "includesNoTags": false]]]]]
    let payload = String(decoding: try JSONSerialization.data(withJSONObject: archive, options: [.sortedKeys]), as: UTF8.self)
    let accepted = try await store.pushSync(.init(changes: [.init(id: id, type: "typebar-archive",
      version: 2, payload: payload, isDeleted: false)]), accessToken: owner.accessToken)
    XCTAssertEqual(accepted.results.first?.status,.accepted)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4)
    let stale = try await reloaded.pushSync(.init(changes: [.init(id: id, type: "typebar-archive",
      version: 1, payload: #"{"version":30,"resultFilterPresets":[]}"#, isDeleted: false)]), accessToken: owner.accessToken)
    XCTAssertEqual(stale.results.first?.status,.conflict)
    let pulled = try await reloaded.pullSync(after: 0, accessToken: owner.accessToken)
    XCTAssertEqual(pulled.changes.first?.payload,payload)
    let isolated = try await reloaded.pullSync(after: 0, accessToken: other.accessToken)
    XCTAssertTrue(isolated.changes.isEmpty)
    let results = try await reloaded.results(.init(), credential: .accessToken(owner.accessToken))
    let directory = try await reloaded.accountTags(accessToken: owner.accessToken)
    XCTAssertEqual(results.total,0); XCTAssertTrue(directory.tags.isEmpty)
  }
}
