import Foundation
import Security
import XCTest
@testable import Typebar

final class QAAccountTokenIsolationTests: XCTestCase {
  private let endpoint = "https://owned-token-fixture.invalid/api"
  private let otherEndpoint = "https://other-token-fixture.invalid/api"
  private let qaInfo: [String: Any] = [QAStoreMode.inMemoryInfoKey: true]

  private final class KeychainFixture {
    var values: [String: Data] = [:]
    var reads = 0, adds = 0, deletes = 0
    var addStatus = errSecSuccess
    var queries: [NSDictionary] = []
    private func account(_ query: CFDictionary) -> String {
      let value = query as NSDictionary
      queries.append(value)
      return value[kSecAttrAccount] as! String
    }
    var access: AccountTokenStore.KeychainAccess {
      .init(read: { query in
        self.reads += 1
        guard let data = self.values[self.account(query)] else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, data as CFData)
      }, add: { query in
        self.adds += 1
        let name = self.account(query)
        guard self.addStatus == errSecSuccess else { return self.addStatus }
        self.values[name] = (query as NSDictionary)[kSecValueData] as? Data
        return errSecSuccess
      }, delete: { query in
        self.deletes += 1; self.values.removeValue(forKey: self.account(query))
        return errSecSuccess
      })
    }
    var operationCount: Int { reads + adds + deletes }
  }

  func testExplicitQABundleCannotReadOrMigrateFormalKeychainTokens() throws {
    let fixture = KeychainFixture()
    let scoped = AccountTokenStore.accountName(for: endpoint)
    fixture.values[scoped] = Data("formal-owned-fixture".utf8)
    fixture.values["remote-access-token"] = Data("legacy-owned-fixture".utf8)
    let before = fixture.values
    let store = AccountTokenStore(info: qaInfo, keychain: fixture.access)
    store.setEndpoint(endpoint)
    XCTAssertNil(store.load())
    XCTAssertNil(store.load(for: endpoint, migratingLegacyFor: endpoint))
    XCTAssertEqual(fixture.operationCount, 0, "QA must not query Security even for a missing in-memory token")
    XCTAssertEqual(fixture.values, before, "Startup must not delete a formal legacy credential")
    try store.save("qa-owned-fixture")
    XCTAssertEqual(store.load(), "qa-owned-fixture")
    store.clear()
    XCTAssertNil(store.load())
    XCTAssertEqual(fixture.operationCount, 0)
    XCTAssertEqual(fixture.values, before)
  }

  func testQATokensAreInstanceLocalAndDoNotSurviveAnotherStore() throws {
    let fixture = KeychainFixture()
    let first = AccountTokenStore(info: qaInfo, keychain: fixture.access)
    try first.save("first-owned-fixture", for: endpoint)
    let second = AccountTokenStore(info: qaInfo, keychain: fixture.access)
    XCTAssertNil(second.load(for: endpoint))
    try second.save("second-owned-fixture", for: endpoint)
    XCTAssertEqual(first.load(for: endpoint), "first-owned-fixture")
    second.clear(for: endpoint)
    XCTAssertEqual(first.load(for: endpoint), "first-owned-fixture")
    XCTAssertNil(second.load(for: endpoint))
    XCTAssertEqual(fixture.operationCount, 0)
  }

  func testQAEndpointAliasesShareOnlyTheirOwnMemoryScope() throws {
    let fixture = KeychainFixture()
    let store = AccountTokenStore(info: qaInfo, keychain: fixture.access)
    try store.save("first-owned-fixture", for: endpoint)
    try store.save("other-owned-fixture", for: otherEndpoint)
    let alias = "HTTPS://OWNED-TOKEN-FIXTURE.INVALID:443/api/"
    XCTAssertEqual(store.load(for: alias), "first-owned-fixture")
    store.setEndpoint(otherEndpoint)
    XCTAssertEqual(store.load(), "other-owned-fixture")
    store.clear(for: alias)
    XCTAssertNil(store.load(for: endpoint))
    XCTAssertEqual(store.load(), "other-owned-fixture")
    XCTAssertEqual(fixture.operationCount, 0)
  }

  func testOrdinaryMissingFalseAndStringFlagsRetainFormalKeychainQueries() throws {
    for info: [String: Any] in [[:], [QAStoreMode.inMemoryInfoKey: false], [QAStoreMode.inMemoryInfoKey: "YES"]] {
      let fixture = KeychainFixture()
      let store = AccountTokenStore(info: info, keychain: fixture.access)
      store.setEndpoint(endpoint)
      try store.save("ordinary-owned-fixture")
      XCTAssertEqual(store.load(), "ordinary-owned-fixture")
      XCTAssertGreaterThan(fixture.operationCount, 0)
      XCTAssertTrue(fixture.queries.allSatisfy { $0[kSecAttrService] as? String == "app.typebar.desktop" })
      let add = try XCTUnwrap(fixture.queries.first { $0[kSecValueData] != nil })
      XCTAssertEqual(add[kSecClass] as? String, kSecClassGenericPassword as String)
      XCTAssertEqual(add[kSecAttrAccessible] as? String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
      store.clear()
      XCTAssertNil(store.load())
    }
  }

  func testOrdinaryLegacyMigrationRetainsEndpointRestrictionAndCopyBeforeRemoval() {
    let fixture = KeychainFixture()
    let legacy = "remote-access-token", token = Data("legacy-owned-fixture".utf8)
    fixture.values[legacy] = token
    let store = AccountTokenStore(info: [:], keychain: fixture.access)
    XCTAssertNil(store.load(for: otherEndpoint, migratingLegacyFor: endpoint))
    XCTAssertEqual(fixture.values[legacy], token)
    XCTAssertEqual(store.load(for: endpoint, migratingLegacyFor: endpoint), "legacy-owned-fixture")
    XCTAssertNil(fixture.values[legacy])
    XCTAssertEqual(fixture.values[AccountTokenStore.accountName(for: endpoint)], token)
  }

  func testOrdinaryMigrationFailurePreservesLegacyForRetryAndSaveStillThrows() {
    let fixture = KeychainFixture()
    let legacy = "remote-access-token", token = Data("legacy-owned-fixture".utf8)
    fixture.values[legacy] = token; fixture.addStatus = errSecInteractionNotAllowed
    let store = AccountTokenStore(info: [:], keychain: fixture.access)
    XCTAssertEqual(store.load(for: endpoint, migratingLegacyFor: endpoint), "legacy-owned-fixture")
    XCTAssertEqual(fixture.values[legacy], token)
    XCTAssertNil(fixture.values[AccountTokenStore.accountName(for: endpoint)])
    XCTAssertThrowsError(try store.save("new-owned-fixture", for: otherEndpoint)) { error in
      XCTAssertEqual((error as NSError).domain, NSOSStatusErrorDomain)
      XCTAssertEqual((error as NSError).code, Int(errSecInteractionNotAllowed))
    }
    fixture.addStatus = errSecSuccess
    XCTAssertEqual(store.load(for: endpoint, migratingLegacyFor: endpoint), "legacy-owned-fixture")
    XCTAssertNil(fixture.values[legacy])
  }
}
