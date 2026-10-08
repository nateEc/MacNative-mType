import Foundation
import AppKit
import XCTest
@testable import Typebar

final class SharedPublicProfileTests: XCTestCase {
  private let id = UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!
  private func target(_ server: String = "https://owned.invalid/base") throws -> SharedProfileTarget {
    try .init(server: server, profileID: id)
  }
  private func data(id: UUID? = nil) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["id": (id ?? self.id).uuidString, "displayName": "Owned",
      "joinedAt": "2026-01-02T03:04:05Z", "completedResultCount": 4, "bestWPM": 70,
      "activity": ["lastDay": "2026-01-02T00:00:00Z", "testsByDays": [1, 3], "dayBoundaryOffsetHours": 0],
      "allTimeLbs": ["time": ["15": ["english": ["rank": 2, "count": 3]]]]])
  }
  private func profile(id: UUID? = nil) throws -> RemotePublicProfile {
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(RemotePublicProfile.self, from: data(id: id))
  }

  func testShareCodecRoundTripsNormalizedServersWithoutIdentityOrCredentials() throws {
    for server in ["HTTPS://OWNED.invalid:443/base///", "http://127.0.0.1:9876/base", "http://[::1]:8080", "https://owned.invalid"] {
      let target = try target(server), link = SharedProfileLinkCodec.link(for: target)
      XCTAssertEqual(try SharedProfileLinkCodec.target(from: " \n" + link + "\n"), target)
      XCTAssertEqual(URLComponents(string: link)?.queryItems?.count, 3)
      XCTAssertFalse(link.contains("email")); XCTAssertFalse(link.contains("token"))
    }
    XCTAssertEqual(try target(" HTTPS://OWNED.invalid:443/base/// ").server.absoluteString, "https://owned.invalid/base")
    XCTAssertEqual(try target().requestURL.absoluteString, "https://owned.invalid/base/v1/profiles/12345678-1234-1234-1234-123456789abc")
    XCTAssertTrue(try target("http://lan.invalid:8080").usesPlainHTTP)
  }

  func testShareCodecRejectsAmbiguousOrSecretBearingInputs() throws {
    for server in ["file:///tmp/profile", "https://user:secret@owned.invalid", "https://owned.invalid?token=secret",
      "https://owned.invalid#secret", "https://owned.invalid/../base", "https://owned.invalid/%2e%2e/base",
      "https://owned.invalid/a b", "https://owned.invalid/中文", "https://owned.invalid:0", "https://owned.invalid:65536",
      "https://%6fwned.invalid", "https://owned.invalid%2f@foreign.invalid",
      "https://owned.invalid/\nbase", String(repeating: "a", count: 2049)] {
      XCTAssertThrowsError(try target(server), server)
    }
    let good = SharedProfileLinkCodec.link(for: try target())
    for link in [good + "&v=1", good + "&token=secret", good + "#secret", good.replacingOccurrences(of: "v=1", with: "v=2"),
      good.replacingOccurrences(of: "profile?", with: "profile/path?"), good.replacingOccurrences(of: "id=12345678", with: "id=bad"),
      good.replacingOccurrences(of: "typebar:", with: "https:"), "typebar://profile", "typebar://secret@profile?v=1", String(repeating: "a", count: 4097)] {
      XCTAssertThrowsError(try SharedProfileLinkCodec.target(from: link))
      XCTAssertNil(SharedProfileRoute(link: link).target)
      XCTAssertFalse(SharedProfileRoute(link: link).message?.contains("secret") ?? true)
    }
  }

  @MainActor func testCopySuccessFailureFallbackAndClearUseActualCodecWithoutClipboardAccess() throws {
    let state = ProfileShareCopyState(), target = try target()
    var writes: [String] = []
    state.copy(target: target) { writes.append($0); return false }
    XCTAssertEqual(state.fallbackLink, SharedProfileLinkCodec.link(for: target))
    XCTAssertTrue(state.message?.contains("手动复制") == true)
    state.copy(target: target) { writes.append($0); return true }
    XCTAssertEqual(writes.count, 2); XCTAssertEqual(writes[0], writes[1])
    XCTAssertNil(state.fallbackLink); XCTAssertTrue(state.message?.contains("已复制") == true)
    state.clear(); XCTAssertNil(state.message)
  }

  @MainActor func testIncomingLinksQueueDeduplicateAndIgnoreOAuthWithoutInterruptingProtectedPractice() throws {
    let inbox = SharedProfileLinkInbox(), first = try target(), second = try target("https://second.invalid")
    let firstURL = try XCTUnwrap(URL(string: SharedProfileLinkCodec.link(for: first)))
    XCTAssertFalse(inbox.receive(URL(string: "typebar://oauth?code=owned")!, allowed: true))
    XCTAssertTrue(inbox.receive(firstURL, allowed: false))
    XCTAssertNil(inbox.presented); XCTAssertEqual(inbox.pending?.target, first)
    inbox.presentNext(allowed: false); XCTAssertNil(inbox.presented)
    inbox.presentNext(allowed: true); let routeID = inbox.presented?.id
    inbox.receive(firstURL, allowed: true)
    XCTAssertEqual(inbox.presented?.id, routeID); XCTAssertNil(inbox.pending)
    inbox.receive(URL(string: SharedProfileLinkCodec.link(for: second))!, allowed: true)
    XCTAssertEqual(inbox.presented?.target, first); XCTAssertEqual(inbox.pending?.target, second)
    inbox.receive(URL(string: "typebar://profile?bad=1")!, allowed: false)
    XCTAssertNil(inbox.pending?.target); XCTAssertNotNil(inbox.pending?.message)
    inbox.presented = nil; inbox.presentNext(allowed: true)
    XCTAssertNotNil(inbox.presented?.message); XCTAssertNil(inbox.pending)
  }

  @MainActor func testConfirmedLoaderIsIdleUntilExplicitLoadAndRetryNeverFallsBackToSummary() async throws {
    let state = SharedProfileLoadState(), target = try target(), expected = try profile()
    XCTAssertFalse(state.isConfirmed); XCTAssertFalse(state.isLoading); XCTAssertNil(state.profile)
    var calls = 0
    await state.load(target: target) { calls += 1; throw SharedProfileLinkError.httpStatus(404) }
    XCTAssertEqual(calls, 1); XCTAssertTrue(state.isConfirmed); XCTAssertFalse(state.isLoading)
    XCTAssertNotNil(state.message); XCTAssertNil(state.profile)
    await state.load(target: target) { calls += 1; return expected }
    XCTAssertEqual(calls, 2); XCTAssertEqual(state.profile?.id, target.profileID); XCTAssertNil(state.message)
    await state.load(target: target) { try profile(id: UUID()) }
    XCTAssertNil(state.profile); XCTAssertNotNil(state.message)
    state.cancel(); XCTAssertFalse(state.isConfirmed); XCTAssertNil(state.message)
  }

  @MainActor func testCancelledAndLateLoadsCannotReopenOrReplaceNewSharedProfile() async throws {
    let state = SharedProfileLoadState(), target = try target(), expected = try profile()
    var continuation: CheckedContinuation<RemotePublicProfile, Never>?
    let old = Task { await state.load(target: target) { await withCheckedContinuation { continuation = $0 } } }
    while continuation == nil { await Task.yield() }
    XCTAssertTrue(state.isLoading)
    state.cancel()
    await state.load(target: target) { expected }
    continuation?.resume(returning: expected); await old.value
    XCTAssertEqual(state.profile?.id, expected.id); XCTAssertFalse(state.isLoading)
    let cancelled = Task { await state.load(target: target) { throw CancellationError() } }
    await cancelled.value
    XCTAssertFalse(state.isConfirmed); XCTAssertFalse(state.isLoading); XCTAssertNil(state.profile)
  }

  func testAnonymousTransportStripsInjectedHeadersStorageAndDecodesFullProfile() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SharedProfileProtocol.self]
    configuration.httpAdditionalHeaders = ["Authorization": "Bearer owned-fake", "Cookie": "owned-fake"]
    let client = SharedProfileReadClient(configuration: configuration)
    XCTAssertNil(client.configuration.httpAdditionalHeaders); XCTAssertNil(client.configuration.urlCredentialStorage)
    XCTAssertNil(client.configuration.httpCookieStorage); XCTAssertNil(client.configuration.urlCache)
    XCTAssertFalse(client.configuration.httpShouldSetCookies)
    SharedProfileProtocol.fixture.set(status: 200, data: try data())
    defer { SharedProfileProtocol.fixture.reset() }
    let result = try await client.load(target())
    XCTAssertEqual(result.id, id); XCTAssertEqual(result.completedResultCount, 4)
    XCTAssertEqual(result.activity?.testsByDays, [1, 3])
    XCTAssertEqual(result.allTimeLbs?.time["15"]?["english"]?.rank, 2)
    let request = try XCTUnwrap(SharedProfileProtocol.fixture.request)
    XCTAssertEqual(request.url, try target().requestURL); XCTAssertEqual(request.httpMethod, "GET")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    XCTAssertFalse(request.httpShouldHandleCookies)
    XCTAssertNotNil(configuration.httpAdditionalHeaders, "Sanitizing the copy must not mutate its caller")
  }

  func testAnonymousTransportRejectsHTTPFailuresMalformedWrongIdentityAndOversizedBodies() async throws {
    let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [SharedProfileProtocol.self]
    defer { SharedProfileProtocol.fixture.reset() }
    for status in [302, 401, 403, 404, 500] {
      SharedProfileProtocol.fixture.set(status: status, data: try data())
      do { _ = try await SharedProfileReadClient(configuration: configuration).load(target()); XCTFail("Expected HTTP failure") }
      catch { XCTAssertEqual(error as? SharedProfileLinkError, .httpStatus(status)) }
    }
    for body in [Data("{}".utf8), try data(id: UUID()), Data(repeating: 65, count: 300)] {
      SharedProfileProtocol.fixture.set(status: 200, data: body)
      do { _ = try await SharedProfileReadClient(configuration: configuration, maximumResponseBytes: 4096).load(target()); XCTFail("Expected invalid body") }
      catch { XCTAssertFalse(error is CancellationError) }
    }
    SharedProfileProtocol.fixture.set(status: 200, data: Data(repeating: 65, count: 300))
    do { _ = try await SharedProfileReadClient(configuration: configuration, maximumResponseBytes: 256).load(target()); XCTFail() }
    catch { XCTAssertEqual(error as? SharedProfileLinkError, .responseTooLarge) }
  }

  func testAnonymousImageTransportUsesImageAcceptAndSameCredentialBoundary() async throws {
    let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [SharedProfileProtocol.self]
    configuration.httpAdditionalHeaders = ["Authorization": "Bearer owned-fake", "Cookie": "owned-fake"]
    let bytes = Data([1, 2, 3]), url = URL(string: "https://cdn.discordapp.com/avatars/123/owned.png?size=128")!
    SharedProfileProtocol.fixture.set(status: 200, data: bytes)
    defer { SharedProfileProtocol.fixture.reset() }
    let result = try await SharedProfileReadClient(configuration: configuration, maximumResponseBytes: 256_000).data(from: url, accept: "image/png")
    XCTAssertEqual(result, bytes)
    let request = try XCTUnwrap(SharedProfileProtocol.fixture.request)
    XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/png")
    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
  }

  @MainActor func testPreCancelledReadsNeverStartTransportOrConfirmation() async throws {
    let state = SharedProfileLoadState(), target = try target(), expected = try profile()
    var calls = 0
    let pending = Task { @MainActor in await state.load(target: target) { calls += 1; return expected } }
    pending.cancel(); await pending.value
    XCTAssertEqual(calls, 0); XCTAssertFalse(state.isConfirmed); XCTAssertFalse(state.isLoading)
    let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [SharedProfileProtocol.self]
    SharedProfileProtocol.fixture.reset()
    defer { SharedProfileProtocol.fixture.reset() }
    let read = Task { @MainActor in try await SharedProfileReadClient(configuration: configuration).load(target) }
    read.cancel()
    do { _ = try await read.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertNil(SharedProfileProtocol.fixture.request)
  }

  func testRedirectDelegateRefusesEveryDestinationWithoutResumingATask() async throws {
    let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [SharedProfileProtocol.self]
    let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
    let task = session.dataTask(with: try target().requestURL)
    let response = try XCTUnwrap(HTTPURLResponse(url: try target().requestURL, statusCode: 302, httpVersion: nil, headerFields: nil))
    for destination in ["https://foreign.invalid", "https://owned.invalid/base", "http://owned.invalid"] {
      let refused = await withCheckedContinuation { continuation in
        SharedProfileReadDelegate().urlSession(session, task: task, willPerformHTTPRedirection: response,
          newRequest: URLRequest(url: URL(string: destination)!)) { continuation.resume(returning: $0 == nil) }
      }
      XCTAssertTrue(refused)
    }
    XCTAssertEqual(task.state, .suspended)
  }

  func testAuthenticationDelegateNeverUsesProposedPasswordOrClientCertificate() async throws {
    let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [SharedProfileProtocol.self]
    let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
    let task = session.dataTask(with: try target().requestURL)
    for method in [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest, NSURLAuthenticationMethodNTLM,
      NSURLAuthenticationMethodClientCertificate, NSURLAuthenticationMethodServerTrust] {
      let space = URLProtectionSpace(host: "owned.invalid", port: 443, protocol: "https", realm: nil, authenticationMethod: method)
      let challenge = URLAuthenticationChallenge(protectionSpace: space,
        proposedCredential: URLCredential(user: "owned-fake", password: "never-send", persistence: .none),
        previousFailureCount: 0, failureResponse: nil, error: nil, sender: SharedProfileChallengeSender())
      for taskLevel in [true, false] {
        let result = await withCheckedContinuation { continuation in
          let completion: @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void = {
            continuation.resume(returning: ($0, $1 == nil))
          }
          if taskLevel { SharedProfileReadDelegate().urlSession(session, task: task, didReceive: challenge, completionHandler: completion) }
          else { SharedProfileReadDelegate().urlSession(session, didReceive: challenge, completionHandler: completion) }
        }
        XCTAssertEqual(result.0, method == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .cancelAuthenticationChallenge)
        XCTAssertTrue(result.1)
      }
    }
    XCTAssertEqual(task.state, .suspended)
  }

  @MainActor func testWindowProbeOnlyTracksItsOwnNeverVisibleWindowAndCannotHitTest() {
    let metadata = SharedProfileWindowHost(), probe = SharedProfileWindowProbe.Probe()
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 80, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.contentView = nil; window.close() }
    XCTAssertFalse(metadata.canPresent)
    probe.host = metadata; window.contentView = probe
    XCTAssertTrue(metadata.window === window); XCTAssertTrue(metadata.canPresent)
    XCTAssertNil(probe.hitTest(.zero)); XCTAssertFalse(window.isVisible)
    window.contentView = nil; XCTAssertNil(metadata.window)
  }

  func testProfileShareHasCopyImportNativeRoutingAndReadonlyBoundary() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    func source(_ file: String) throws -> String {
      try String(contentsOf: root.appendingPathComponent("Sources/Typebar/" + file), encoding: .utf8)
    }
    let app = try source("TypebarApp.swift"), profile = try source("CloudSyncView.swift")
    XCTAssertTrue(app.contains(".onOpenURL"), "Copied native profile URLs need an actual incoming route")
    XCTAssertTrue(app.contains(".handlesExternalEvents(preferring:"), "Reuse an existing main scene rather than volunteer a new window")
    XCTAssertTrue(app.contains("SharedProfileLinkView("))
    XCTAssertTrue(profile.contains("ProfileShareCopyButton("))
    XCTAssertTrue(profile.contains("allowsAccountActions"), "A foreign shared server must never reuse connected-server friend/report mutations")
    XCTAssertTrue(try source("NavigationCommands.swift").contains("SharedProfileImportView("))
  }
}

private final class SharedProfileChallengeSender: NSObject, URLAuthenticationChallengeSender {
  func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
  func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
  func cancel(_ challenge: URLAuthenticationChallenge) {}
}

/// In-memory transport only. No socket, shared credential store, clipboard or account.
private final class SharedProfileProtocol: URLProtocol, @unchecked Sendable {
  static let fixture = Fixture()
  final class Fixture: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 200
    private var data = Data()
    private var captured: URLRequest?
    var request: URLRequest? { lock.withLock { captured } }
    func set(status: Int, data: Data) { lock.withLock { self.status = status; self.data = data; captured = nil } }
    func reset() { set(status: 200, data: Data()) }
    func receive(_ request: URLRequest) -> (Int, Data) { lock.withLock { captured = request; return (status, data) } }
  }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let (status, data) = Self.fixture.receive(request)
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Location": "https://never-contact.invalid"] )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
