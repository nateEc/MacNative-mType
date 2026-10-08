import Foundation
import XCTest
@testable import Typebar

final class FriendNameTransportTests: XCTestCase {
  private let targetID = UUID()
  private func payload(name: String = "Target", version: Int = 1, claim: Bool = false) throws -> Data {
    var profile: [String: Any] = ["id": targetID.uuidString, "displayName": name,
      "joinedAt": "2026-01-02T03:04:05Z", "completedResultCount": 0, "bestWPM": 0]
    if claim { profile["accountStreakClaim"] = ["version": 1, "lastResultMilliseconds": 1_800_000_000_000] }
    return try JSONSerialization.data(withJSONObject: ["version": version, "profile": profile])
  }
  @MainActor private func session(_ body: (AccountSession, ConnectionsOwnerIdentity, SharedProfileReadClient) async throws -> Void) async throws {
    let suite = "TypebarTests.friend-name-transport.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite); FriendNameURLProtocol.fixture.reset() }
    let account = AccountSession(defaults: defaults)
    _ = account.updateEndpoint("https://owned.invalid/base")
    account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owner", totalExperience: 0)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FriendNameURLProtocol.self]
    configuration.httpAdditionalHeaders = ["Authorization": "Bearer owned-fake", "Cookie": "owned-fake"]
    try await body(account, .init(account: account), .init(configuration: configuration))
  }
  @MainActor func testActualLookupUsesAnonymousBoundedClientAndExactEncodedName() async throws {
    try await session { account, owner, client in
      FriendNameURLProtocol.fixture.set(200, try self.payload())
      let profile = try await account.resolveFriendName("tArGeT", identity: owner, client: client)
      XCTAssertEqual(profile?.id, self.targetID)
      let request = try XCTUnwrap(FriendNameURLProtocol.fixture.request)
      XCTAssertEqual(request.url?.path, "/base/v1/profiles/resolve-name")
      XCTAssertEqual(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "tArGeT")
      XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody)
      XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
      XCTAssertFalse(request.httpShouldHandleCookies)
      FriendNameURLProtocol.fixture.set(200, try self.payload(name: "Target+Name"))
      _ = try await account.resolveFriendName("Target+Name", identity: owner, client: client)
      let plusRequest = try XCTUnwrap(FriendNameURLProtocol.fixture.request)
      XCTAssertTrue(try XCTUnwrap(URLComponents(url: try XCTUnwrap(plusRequest.url), resolvingAgainstBaseURL: false)?.percentEncodedQuery).contains("%2B"),
        "Vapor form decoding must not turn a literal plus into a space")
    }
  }
  @MainActor func testActualLookupRejectsUnsupportedMismatchedPrivateMalformedAndHTTPFailure() async throws {
    try await session { account, owner, client in
      for (status, data) in [(200, try self.payload(version: 2)), (200, try self.payload(name: "Wrong")),
        (200, try self.payload(claim: true)), (200, Data("{}".utf8)), (503, Data())] {
        FriendNameURLProtocol.fixture.set(status, data)
        do { _ = try await account.resolveFriendName("Target", identity: owner, client: client); XCTFail("Must reject invalid/legacy response") }
        catch { /* Preserve unavailable, never reinterpret transport failure as unknown name. */ }
      }
      FriendNameURLProtocol.fixture.set(200, Data("{\"version\":1}".utf8))
      let unknown = try await account.resolveFriendName("Target", identity: owner, client: client)
      XCTAssertNil(unknown)
    }
  }
  @MainActor func testActualLookupRejectsStaleOwnerBeforeCreatingAnyRequest() async throws {
    try await session { account, owner, client in
      FriendNameURLProtocol.fixture.set(200, try self.payload())
      account.currentUser = nil
      do { _ = try await account.resolveFriendName("Target", identity: owner, client: client); XCTFail("Stale owner must reject") }
      catch { XCTAssertNil(FriendNameURLProtocol.fixture.request) }
    }
  }
}

private final class FriendNameURLProtocol: URLProtocol, @unchecked Sendable {
  final class Fixture: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 200
    private var data = Data()
    private var lastRequest: URLRequest?
    var request: URLRequest? { lock.withLock { lastRequest } }
    func set(_ status: Int, _ data: Data) { lock.withLock { self.status = status; self.data = data; lastRequest = nil } }
    func reset() { set(200, Data()) }
    func response(_ request: URLRequest) -> (Int, Data) { lock.withLock { lastRequest = request; return (status, data) } }
  }
  static let fixture = Fixture()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let (status, data) = Self.fixture.response(request)
    guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]) else { return }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
