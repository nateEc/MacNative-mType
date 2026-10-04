import Foundation
import XCTest
@testable import TypebarServerCore

final class IncompletePracticeArchiveSyncTests: XCTestCase {
  // The sync service transports opaque archives. This fixture proves byte
  // preservation and owner isolation, not validation of a client result or XP.
  private let payload = #"{"version":26,"results":[{"restartCount":2,"priorAttemptEngagedDuration":3.005,"incompletePractice":{"version":1,"attempts":[{"accuracy":66.67,"seconds":1.01},{"accuracy":0,"seconds":2}]}}]}"#

  func testNewArchiveRetainsAttemptFractionsAcrossDiskReloadAndOwnerScope() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-incomplete-sync-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4)
    let owner = try await store.register(.init(email: "incomplete-owner@example.com", password: "owned secure password",
      displayName: "Owner"))
    let other = try await store.register(.init(email: "incomplete-other@example.com", password: "owned secure password",
      displayName: "Other"))
    let id = UUID()
    let push = try await store.pushSync(.init(changes: [.init(id: id, type: "typebar-archive",
      version: 1, payload: payload, isDeleted: false)]), accessToken: owner.accessToken)
    XCTAssertEqual(push.results.first?.status, .accepted)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4)
    let pull = try await reloaded.pullSync(after: 0, accessToken: owner.accessToken)
    XCTAssertEqual(pull.changes.first?.payload, payload)
    XCTAssertEqual(pull.changes.first?.id, id)
    let isolated = try await reloaded.pullSync(after: 0, accessToken: other.accessToken)
    XCTAssertTrue(isolated.changes.isEmpty)
    let results = try await reloaded.results(.init(), credential: .accessToken(owner.accessToken))
    XCTAssertEqual(results.total, 0, "An archive upload is not an accepted result or an XP award")
  }

  func testStaleArchiveCannotEraseAttemptEvidence() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(.init(email: "incomplete-owner@example.com", password: "owned secure password",
      displayName: "Owner"))
    let id = UUID()
    _ = try await store.pushSync(.init(changes: [.init(id: id, type: "typebar-archive",
      version: 2, payload: payload, isDeleted: false)]), accessToken: owner.accessToken)
    let stale = try await store.pushSync(.init(changes: [.init(id: id, type: "typebar-archive",
      version: 1, payload: #"{"version":25,"results":[]}"#, isDeleted: false)]), accessToken: owner.accessToken)
    XCTAssertEqual(stale.results.first?.status, .conflict)
    let pull = try await store.pullSync(after: 0, accessToken: owner.accessToken)
    XCTAssertEqual(pull.changes.first?.payload, payload)
    XCTAssertEqual(pull.changes.first?.version, 2)
  }
}
