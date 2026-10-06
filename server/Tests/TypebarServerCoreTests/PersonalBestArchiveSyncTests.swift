import Foundation
import XCTest
@testable import TypebarServerCore

final class PersonalBestArchiveSyncTests: XCTestCase {
  // Owned opaque transport fixture, not an account PB submission or validation.
  private func payload(empty: Bool = false) throws -> String {
    let snapshot = #"{"row":{"id":"00000000-0000-0000-0000-000000000028","mode":"time","parameter":15,"wpm":60.25,"rawWpm":70.5,"accuracy":98.25,"consistency":80.125,"difficulty":"normal","language":"english","includesPunctuation":false,"includesNumbers":false,"usesLazyLatin":false,"finishedAt":-978307083.5},"recordedAt":-978306699.875,"origin":"accepted"}"#
    let entry = try JSONSerialization.jsonObject(with: Data(snapshot.utf8))
    let ledger: [String: Any] = ["version": 1, "historyComplete": true,
      "entries": empty ? [] : [entry], "tagEntries": empty ? [] : [["tag": "focus", "snapshot": entry]]]
    let blob = try JSONSerialization.data(withJSONObject: ledger, options: [.sortedKeys])
    let archive: [String: Any] = ["version": 28, "results": [], "presets": [],
      "localPersonalBestLedgerData": blob.base64EncodedString()]
    return String(decoding: try JSONSerialization.data(withJSONObject: archive, options: [.sortedKeys]), as: UTF8.self)
  }

  func testLedgerOnlyAndKnownEmptyPayloadsSurviveReloadWithOwnerIsolation() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-pb-sync-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("state.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4)
    let owner = try await store.register(.init(email: "pb-owner@example.com",
      password: "owned secure password", displayName: "Owner"))
    let other = try await store.register(.init(email: "pb-other@example.com",
      password: "owned secure password", displayName: "Other"))
    let originals = try [payload(), payload(empty: true)]
    let ids = [UUID(), UUID()]
    for (id, value) in zip(ids, originals) {
      let push = try await store.pushSync(.init(changes: [.init(id: id, type: "typebar-archive",
        version: 1, payload: value, isDeleted: false)]), accessToken: owner.accessToken)
      XCTAssertEqual(push.results.first?.status, .accepted)
    }
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4)
    let pulled = try await reloaded.pullSync(after: 0, accessToken: owner.accessToken)
    XCTAssertEqual(pulled.changes.map(\.payload), originals.map(Optional.some))
    let isolated = try await reloaded.pullSync(after: 0, accessToken: other.accessToken)
    XCTAssertTrue(isolated.changes.isEmpty)
    let results = try await reloaded.results(.init(), credential: .accessToken(owner.accessToken))
    XCTAssertEqual(results.total, 0, "Backup transport must not accept a result or award XP")
  }

  func testStaleWriterCannotReplaceLedgerWithLegacyArchive() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(.init(email: "pb-owner@example.com",
      password: "owned secure password", displayName: "Owner"))
    let id = UUID(), original = try payload()
    _ = try await store.pushSync(.init(changes: [.init(id: id, type: "typebar-archive",
      version: 2, payload: original, isDeleted: false)]), accessToken: owner.accessToken)
    let stale = try await store.pushSync(.init(changes: [.init(id: id, type: "typebar-archive",
      version: 1, payload: #"{"version":27,"results":[]}"#, isDeleted: false)]), accessToken: owner.accessToken)
    XCTAssertEqual(stale.results.first?.status, .conflict)
    let pulled = try await store.pullSync(after: 0, accessToken: owner.accessToken)
    XCTAssertEqual(pulled.changes.first?.payload, original)
  }
}
