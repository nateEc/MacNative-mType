import Foundation
import XCTest
@testable import Typebar

@MainActor
final class CustomBackgroundDownloadTests: XCTestCase {
  private let url = URL(string: "https://background-test.invalid/owned.png")!
  private func session() -> URLSession {
    let configuration = CustomBackgroundDownload.configuration()
    configuration.protocolClasses = [BackgroundBytesProtocol.self]
    return URLSession(configuration: configuration)
  }
  func testExactLimitAndUnknownLengthPreserveEveryByte() async throws {
    let session = session(); defer { session.invalidateAndCancel() }
    let bytes = Data([1, 2, 3, 4, 5, 6, 7, 8])
    BackgroundBytesProtocol.fixture.set(status: 200, data: bytes)
    let actual = try await CustomBackgroundDownload.data(from: url, maximumBytes: bytes.count, session: session)
    XCTAssertEqual(actual, bytes)
    XCTAssertNil(BackgroundBytesProtocol.fixture.request?.value(forHTTPHeaderField: "Authorization"))
    XCTAssertNil(BackgroundBytesProtocol.fixture.request?.value(forHTTPHeaderField: "Cookie"))
  }
  func testDeclaredAndActualOverLimitAndHTTPFailureRejectBeforePublication() async throws {
    let session = session(); defer { session.invalidateAndCancel() }
    for (status, length, data, expected) in [
      (200, "9", Data(), CustomBackgroundDownload.Failure.resourceLimit),
      (200, nil, Data(repeating: 7, count: 9), .resourceLimit),
      (404, nil, Data([1]), .httpStatus(404))] {
      BackgroundBytesProtocol.fixture.set(status: status, data: data, length: length)
      do {
        _ = try await CustomBackgroundDownload.data(from: url, maximumBytes: 8, session: session)
        XCTFail("Expected bounded HTTP rejection")
      } catch { XCTAssertEqual(error as? CustomBackgroundDownload.Failure, expected) }
    }
  }
  func testCancellationStopsActualURLSessionWithAndWithoutResponseHeaders() async throws {
    for headers in [false, true] {
      let session = session(); defer { session.invalidateAndCancel() }
      let started = expectation(description: "Protocol started"), stopped = expectation(description: "Protocol cancelled")
      BackgroundBytesProtocol.fixture.set(status: 200, data: Data(), hold: true, headers: headers,
        started: { started.fulfill() }, stopped: { stopped.fulfill() })
      let task = Task { try await CustomBackgroundDownload.data(from: url, maximumBytes: 8, session: session) }
      await fulfillment(of: [started], timeout: 5)
      task.cancel()
      do { _ = try await task.value; XCTFail("Cancelled transfer succeeded") }
      catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
      await fulfillment(of: [stopped], timeout: 5)
    }
  }
  func testDefaultStorageIsIsolatedAndRedirectsRemainHTTPOnly() {
    let configuration = CustomBackgroundDownload.configuration()
    XCTAssertNil(configuration.urlCache); XCTAssertNil(configuration.httpCookieStorage)
    XCTAssertNil(configuration.urlCredentialStorage); XCTAssertFalse(configuration.httpShouldSetCookies)
    XCTAssertNil(configuration.identifier)
    let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
    let task = session.dataTask(with: url); defer { task.cancel() }
    let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!
    let policy = CustomBackgroundDownload.RedirectPolicy()
    for (url, allowed) in [(URL(string: "https://other.invalid/image")!, true),
      (URL(string: "http://other.invalid/image")!, true), (URL(fileURLWithPath: "/never-read"), false)] {
      policy.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: url)) {
        XCTAssertEqual($0?.url, allowed ? url : nil)
      }
    }
  }
  func testUnsupportedURLsAndInvalidLimitsDoNotStartATransfer() async throws {
    let session = session(); defer { session.invalidateAndCancel() }
    BackgroundBytesProtocol.fixture.set(status: 200, data: Data())
    for (url, limit, expected) in [(URL(fileURLWithPath: "/never-read"), 8, CustomBackgroundDownload.Failure.unsupportedURL),
      (url, 0, .invalidLimit), (url, Int.max, .invalidLimit)] {
      do { _ = try await CustomBackgroundDownload.data(from: url, maximumBytes: limit, session: session); XCTFail("Expected rejection") }
      catch { XCTAssertEqual(error as? CustomBackgroundDownload.Failure, expected) }
    }
    XCTAssertNil(BackgroundBytesProtocol.fixture.request)
  }
}

/// In-memory URL loading only; all requests are intercepted and no socket is opened.
private final class BackgroundBytesProtocol: URLProtocol, @unchecked Sendable {
  static let fixture = Fixture()
  final class Fixture: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 200, data = Data(), length: String?, hold = false, headers = true
    private var captured: URLRequest?
    private var started: (@Sendable () -> Void)?, stopped: (@Sendable () -> Void)?
    var request: URLRequest? { lock.withLock { captured } }
    func set(status: Int, data: Data, length: String? = nil, hold: Bool = false, headers: Bool = true,
      started: (@Sendable () -> Void)? = nil, stopped: (@Sendable () -> Void)? = nil) {
      lock.withLock {
        self.status = status; self.data = data; self.length = length; self.hold = hold; self.headers = headers
        self.started = started; self.stopped = stopped; captured = nil
      }
    }
    func receive(_ request: URLRequest) -> (Int, Data, String?, Bool, Bool, (@Sendable () -> Void)?, (@Sendable () -> Void)?) {
      lock.withLock { captured = request; return (status, data, length, hold, headers, started, stopped) }
    }
  }
  private let callbackLock = NSLock()
  private var stopCallback: (@Sendable () -> Void)?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let (status, data, length, hold, headers, started, stopped) = Self.fixture.receive(request)
    callbackLock.withLock { stopCallback = stopped }
    if headers {
      let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
        headerFields: length.map { ["Content-Length": $0] })!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }
    started?()
    if !hold {
      client?.urlProtocol(self, didLoad: data.prefix(data.count / 2))
      client?.urlProtocol(self, didLoad: data.suffix(data.count - data.count / 2))
      client?.urlProtocolDidFinishLoading(self)
    }
  }
  override func stopLoading() {
    let callback = callbackLock.withLock { let result = stopCallback; stopCallback = nil; return result }
    callback?()
  }
}
