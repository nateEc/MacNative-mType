import Foundation
import XCTest
@testable import TypebarServerCore

final class AccountTagPaceArchiveSyncTests: XCTestCase {
  func testNewPaceArchiveRemainsOpaqueAcrossColdReloadAndStaleSyncWriter() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-tag-pace-sync-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("state.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4)
    let owner = try await store.register(.init(email: "pace-owner@example.invalid",
      password: "owned secure password", displayName: "Owner"))
    let other = try await store.register(.init(email: "pace-other@example.invalid",
      password: "owned secure password", displayName: "Other"))
    let archive: [String: Any] = ["version": 30, "exportedAt": "2027-01-15T08:00:00Z",
      "settings": ["paceGuideMode": "accountTagPersonalBest"], "results": [], "presets": []]
    let payload = String(decoding: try JSONSerialization.data(withJSONObject: archive, options: [.sortedKeys]), as: UTF8.self)
    let id = UUID()
    let accepted = try await store.pushSync(.init(changes: [.init(id: id, type: "typebar-archive",
      version: 2, payload: payload, isDeleted: false)]), accessToken: owner.accessToken)
    XCTAssertEqual(accepted.results.first?.status, .accepted)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4)
    let stale = try await reloaded.pushSync(.init(changes: [.init(id: id, type: "typebar-archive",
      version: 1, payload: #"{"version":29,"results":[]}"#, isDeleted: false)]), accessToken: owner.accessToken)
    XCTAssertEqual(stale.results.first?.status, .conflict)
    let pulled = try await reloaded.pullSync(after: 0, accessToken: owner.accessToken)
    XCTAssertEqual(pulled.changes.first?.payload, payload)
    let isolated = try await reloaded.pullSync(after: 0, accessToken: other.accessToken)
    XCTAssertTrue(isolated.changes.isEmpty)
    let results = try await reloaded.results(.init(), credential: .accessToken(owner.accessToken))
    let tags = try await reloaded.accountTags(accessToken: owner.accessToken)
    XCTAssertEqual(results.total, 0); XCTAssertTrue(tags.tags.isEmpty)
  }
}
