import XCTest
@testable import TypebarServerCore

final class CustomPaceArchiveSyncTests: XCTestCase {
  func testOpaqueFormatTwentyFourPayloadRetainsFractionAcrossRestartAndOwnerScope() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TypebarServerTests.pace-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("state.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4)
    let owner = try await store.register(.init(email: "owner@example.com",
      password: "owned secure password", displayName: "Owner"))
    let other = try await store.register(.init(email: "other@example.com",
      password: "owned secure password", displayName: "Other"))
    let payload = #"{"version":24,"exportedAt":"2026-10-04T00:00:00Z","settings":{"paceGuideCustomWpm":60.123456789},"results":[],"presets":[]}"#
    let id = UUID()
    let pushed = try await store.pushSync(.init(changes: [.init(id: id, type: "typebar-archive",
      version: 1, payload: payload, isDeleted: false)]), accessToken: owner.accessToken)
    XCTAssertEqual(pushed.results.first?.status, .accepted)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4)
    let pull = try await reloaded.pullSync(after: 0, accessToken: owner.accessToken)
    XCTAssertEqual(pull.changes.first?.payload, payload)
    let otherPull = try await reloaded.pullSync(after: 0, accessToken: other.accessToken)
    XCTAssertTrue(otherPull.changes.isEmpty)
  }

  func testStaleSyncWriterCannotReplaceExpandedPayloadWithLegacySpeed() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(.init(email: "owner@example.com",
      password: "owned secure password", displayName: "Owner"))
    let id = UUID()
    let expanded = #"{"version":24,"settings":{"paceGuideCustomWpm":1e100}}"#
    _ = try await store.pushSync(.init(changes: [.init(id: id, type: "typebar-archive",
      version: 2, payload: expanded, isDeleted: false)]), accessToken: owner.accessToken)
    let stale = try await store.pushSync(.init(changes: [.init(id: id, type: "typebar-archive",
      version: 1, payload: #"{"version":23,"settings":{"paceGuideCustomWpm":95}}"#,
      isDeleted: false)]), accessToken: owner.accessToken)
    XCTAssertEqual(stale.results.first?.status, .conflict)
    let pull = try await store.pullSync(after: 0, accessToken: owner.accessToken)
    XCTAssertEqual(pull.changes.first?.payload, expanded)
    XCTAssertEqual(pull.changes.first?.version, 2)
  }
}
