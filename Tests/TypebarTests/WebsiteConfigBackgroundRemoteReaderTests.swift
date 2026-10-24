import Foundation
import XCTest
@testable import Typebar

@MainActor
final class WebsiteConfigBackgroundRemoteReaderTests: XCTestCase {
  private func bytes(_ result: WebsiteConfigBackgroundResource.Remote, address: WebsiteConfigValue,
    file: StaticString = #filePath, line: UInt = #line) -> Data? {
    switch result {
    case .received(let actual, let data): XCTAssertEqual(actual, address, file: file, line: line); return data
    case .failed(let actual, _): XCTAssertEqual(actual, address, file: file, line: line); XCTFail("Expected received bytes", file: file, line: line); return nil
    }
  }
  private func failed(_ result: WebsiteConfigBackgroundResource.Remote, address: WebsiteConfigValue,
    reason: WebsiteConfigBackgroundResource.Failure = .transport, file: StaticString = #filePath, line: UInt = #line) {
    guard case .failed(let actual, let actualReason) = result else { return XCTFail("Expected failed intent", file: file, line: line) }
    XCTAssertEqual(actual, address, file: file, line: line); XCTAssertEqual(actualReason, reason, file: file, line: line)
  }

  func testRawUTF16IntentIsNotReplacedByItsTransportURL() async throws {
    let raw = WebsiteConfigValue.string(units: Array(" \thttps://example.invalid/render?q=".utf16) + [0xD800])
    var seen: URL?
    let reader = WebsiteConfigBackgroundRemoteReader { url, budget in seen = url; XCTAssertEqual(budget, 3); return Data([1, 2, 3]) }
    let result = try await reader.read(address: raw, maximumBytes: 3)
    XCTAssertEqual(bytes(result, address: raw), Data([1, 2, 3]))
    XCTAssertEqual(seen?.absoluteString, "https://example.invalid/render?q=%EF%BF%BD")
    XCTAssertEqual(raw.stringUnits?.last, 0xD800)
  }

  func testExplicitBaseResolvesRelativeAndSchemeRelativeAddressesWithoutExtensionRules() async throws {
    let base = URL(string: "https://example.invalid/settings/page?old=1")!
    var requests: [String] = []
    let reader = WebsiteConfigBackgroundRemoteReader(baseURL: base) { url, _ in requests.append(url.absoluteString); return Data([7]) }
    for (raw, expected) in [("../render?x=1", "https://example.invalid/render?x=1"),
      ("//images.invalid/image", "https://images.invalid/image"), ("/image", "https://example.invalid/image")] {
      let address = WebsiteConfigValue.string(raw)
      let response = try await reader.read(address: address, maximumBytes: 1)
      XCTAssertEqual(bytes(response, address: address), Data([7])); XCTAssertEqual(requests.last, expected)
    }
  }

  func testDataURLsDecodeBytesPercentBase64WhitespaceAndFragmentsWithoutNetwork() async throws {
    var requests = 0
    let reader = WebsiteConfigBackgroundRemoteReader { _, _ in requests += 1; return Data() }
    for (raw, expected) in [
      ("data:,%00%FF+%2b,", Data([0, 255, 43, 43, 44])),
      ("data:text/plain,a%ZZ?x=1#not-body", Data("a%ZZ?x=1".utf8)),
      ("data:;base64,YQ", Data([97])), ("DATA:; BASE64, YW Jj\n", Data("abc".utf8)),
      ("data:;base64,YR==", Data([97])), ("data:,漢", Data("漢".utf8))] {
      let address = WebsiteConfigValue.string(raw)
      let result = try await reader.read(address: address, maximumBytes: expected.count)
      XCTAssertEqual(bytes(result, address: address), expected, raw)
    }
    XCTAssertEqual(requests, 0)
  }

  func testMalformedDataAndDisallowedSchemesKeepFailedRawIntent() async throws {
    var requests = 0
    let reader = WebsiteConfigBackgroundRemoteReader { _, _ in requests += 1; return Data([1]) }
    for raw in ["data:no-comma", "data:;base64,YQ=", "data:;base64,Y", "data:;base64,_-==",
      "file:///never-read", "javascript:alert(1)", "blob:https://example.invalid/stale", "../missing-base"] {
      let address = WebsiteConfigValue.string(raw)
      failed(try await reader.read(address: address, maximumBytes: 10), address: address)
    }
    XCTAssertEqual(requests, 0)
  }

  func testBudgetsCoverDataAndAnUntrustedDownloadAndOwnedReturnedBytes() async throws {
    let storage = NSMutableData(data: Data([1, 2, 3]))
    let reader = WebsiteConfigBackgroundRemoteReader { _, _ in Data(referencing: storage) }
    let address = WebsiteConfigValue.string("https://example.invalid/image")
    failed(try await reader.read(address: address, maximumBytes: 2), address: address, reason: .resourceLimit)
    let result = try await reader.read(address: address, maximumBytes: 3)
    storage.length = 0
    XCTAssertEqual(bytes(result, address: address), Data([1, 2, 3]))
    for raw in ["data:,abcd", "data:;base64,YWJjZA=="] {
      let address = WebsiteConfigValue.string(raw)
      failed(try await reader.read(address: address, maximumBytes: 3), address: address, reason: .resourceLimit)
    }
  }

  func testThrownTransportLimitAndCancellationAreNotBothOrdinaryFailures() async throws {
    let address = WebsiteConfigValue.string("https://example.invalid/image")
    for error in [CustomBackgroundDownload.Failure.resourceLimit, .httpStatus(404)] {
      let reader = WebsiteConfigBackgroundRemoteReader { _, _ in throw error }
      failed(try await reader.read(address: address, maximumBytes: 3), address: address,
        reason: error == .resourceLimit ? .resourceLimit : .transport)
    }
    for error: Error in [CancellationError(), URLError(.cancelled)] {
      let reader = WebsiteConfigBackgroundRemoteReader { _, _ in throw error }
      do { _ = try await reader.read(address: address, maximumBytes: 3); XCTFail("Cancellation became transport failure") }
      catch { XCTAssertTrue(error is CancellationError) }
    }
  }

  func testInvalidInputsRejectBeforeAnyDownload() async throws {
    var requests = 0
    let reader = WebsiteConfigBackgroundRemoteReader { _, _ in requests += 1; return Data() }
    for limit in [0, -1, Int.max] {
      do { _ = try await reader.read(address: .string("https://example.invalid/a"), maximumBytes: limit); XCTFail("Invalid limit accepted") }
      catch { XCTAssertEqual(error as? CustomBackgroundDownload.Failure, .invalidLimit) }
    }
    do { _ = try await reader.read(address: .number(7), maximumBytes: 1); XCTFail("Non-string accepted") }
    catch { guard case WebsiteConfigBackgroundRemoteReader.Failure.invalidAddress = error else { return XCTFail("Wrong input error") } }
    XCTAssertEqual(requests, 0)
  }

  func testActualIsolatedURLSessionReturnsBoundedBytesAndHTTPFailure() async throws {
    let configuration = CustomBackgroundDownload.configuration(); configuration.protocolClasses = [BackgroundBytesProtocol.self]
    let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
    let reader = WebsiteConfigBackgroundRemoteReader { try await CustomBackgroundDownload.data(from: $0, maximumBytes: $1, session: session) }
    let address = WebsiteConfigValue.string("https://background-test.invalid/render?image=1")
    BackgroundBytesProtocol.fixture.set(status: 200, data: Data([1, 2, 3]))
    let result = try await reader.read(address: address, maximumBytes: 3)
    XCTAssertEqual(bytes(result, address: address), Data([1, 2, 3]))
    XCTAssertNil(BackgroundBytesProtocol.fixture.request?.value(forHTTPHeaderField: "Authorization"))
    XCTAssertNil(BackgroundBytesProtocol.fixture.request?.value(forHTTPHeaderField: "Cookie"))
    BackgroundBytesProtocol.fixture.set(status: 404, data: Data([7]))
    failed(try await reader.read(address: address, maximumBytes: 3), address: address)
  }

  func testActualSessionCancellationPropagatesAndCancelsTheProtocol() async throws {
    for headers in [false, true] {
      let configuration = CustomBackgroundDownload.configuration(); configuration.protocolClasses = [BackgroundBytesProtocol.self]
      let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
      let started = expectation(description: "remote started"), stopped = expectation(description: "remote stopped")
      BackgroundBytesProtocol.fixture.set(status: 200, data: Data(), hold: true, headers: headers,
        started: { started.fulfill() }, stopped: { stopped.fulfill() })
      let reader = WebsiteConfigBackgroundRemoteReader { try await CustomBackgroundDownload.data(from: $0, maximumBytes: $1, session: session) }
      var received = false
      let task = Task { @MainActor in
        _ = try await reader.read(address: .string("https://background-test.invalid/held.png"), maximumBytes: 3)
        received = true
      }
      await fulfillment(of: [started], timeout: 5); task.cancel()
      do { try await task.value; XCTFail("Cancelled reader returned a response") }
      catch { XCTAssertTrue(error is CancellationError) }
      await fulfillment(of: [stopped], timeout: 5)
      XCTAssertFalse(received)
    }
  }
}
