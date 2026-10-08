import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class FriendNameLookupTests: XCTestCase {
  func testExactLookupBypassesSubstringLimitAndReturnsOnlyPublicProjection() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    for index in 0..<25 {
      _ = try await store.register(.init(email: "owned\(index)@example.invalid", password: "a secure password", displayName: "A_Target_\(index)"))
    }
    let target = try await store.register(.init(email: "target@example.invalid", password: "a secure password", displayName: "Target"))
    let plus = try await store.register(.init(email: "plus@example.invalid", password: "a secure password", displayName: "Target+Name"))
    let search = try await store.searchPublicProfiles(query: "Target", limit: 20)
    XCTAssertEqual(search.profiles.count, 20); XCTAssertFalse(search.profiles.contains { $0.id == target.user.id })
    let app = try await Application.make(.testing)
    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/profiles/resolve-name?name=tArGeT") { response async throws in
        XCTAssertEqual(response.status, .ok)
        guard response.status == .ok else { return }
        XCTAssertEqual(response.headers.first(name: .cacheControl), "no-store")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
        let profile = try XCTUnwrap(json["profile"] as? [String: Any])
        XCTAssertEqual(profile["id"] as? String, target.user.id.uuidString)
        for key in ["email", "accessToken", "passwordHash", "activity", "accountStreakClaim", "allTimeLbs"] { XCTAssertNil(profile[key], key) }
      }
      try await app.test(.GET, "v1/profiles/resolve-name?name=Target%2BName") { response async throws in
        XCTAssertEqual(response.status, .ok)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
        XCTAssertEqual((json["profile"] as? [String: Any])?["id"] as? String, plus.user.id.uuidString)
      }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }

  func testLookupRejectsMalformedInputAndDistinguishesUnknownWithoutSubstringFallback() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    _ = try await store.register(.init(email: "owned@example.invalid", password: "a secure password", displayName: "TargetLong"))
    let unknown = try await store.publicProfileByDisplayName("Target")
    XCTAssertEqual(unknown.version, 1); XCTAssertNil(unknown.profile)
    let short = try await store.publicProfileByDisplayName("A"); XCTAssertNil(short.profile)
    for invalid in ["", " ", "A\nB", "A\u{2028}B", String(repeating: "a", count: 33)] {
      do { _ = try await store.publicProfileByDisplayName(invalid); XCTFail("Must reject malformed lookup") }
      catch let error as AuthStoreError { XCTAssertEqual(error, .invalidProfileSearch) }
    }
  }

  func testLookupFollowsRenamesAndDoesNotWriteStoreOrExposeOwnerClaims() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-name-lookup-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("owned.json"), store = try AuthStore(fileURL: file, bcryptCost: 4)
    let owner = try await store.register(.init(email: "owned@example.invalid", password: "a secure password", displayName: "Résumé"))
    let matched = try await store.publicProfileByDisplayName("  RESUME  ")
    XCTAssertEqual(matched.profile?.id, owner.user.id)
    _ = try await store.updateProfile(.init(displayName: "Renamed"), accessToken: owner.accessToken)
    let bytes = try Data(contentsOf: file)
    let old = try await store.publicProfileByDisplayName("Résumé"), current = try await store.publicProfileByDisplayName("RENAMED")
    XCTAssertNil(old.profile); XCTAssertEqual(current.profile?.id, owner.user.id)
    XCTAssertNil(current.profile?.activity); XCTAssertNil(current.profile?.accountStreakClaim)
    XCTAssertEqual(try Data(contentsOf: file), bytes)
  }
}
