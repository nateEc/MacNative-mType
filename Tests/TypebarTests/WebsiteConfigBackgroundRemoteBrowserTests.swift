import Foundation
import WebKit
import XCTest
@testable import Typebar

@MainActor
final class WebsiteConfigBackgroundRemoteBrowserTests: XCTestCase {
  @MainActor private final class Probe: NSObject, WKNavigationDelegate {
    let completion: XCTestExpectation
    let inputs: [[UInt16]]
    var rows: [[String: Any]]?, error: Error?
    init(_ completion: XCTestExpectation, inputs: [[UInt16]]) { self.completion = completion; self.inputs = inputs }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      webView.callAsyncJavaScript("""
        const rows = [];
        for (const units of inputs) {
          const raw = String.fromCharCode(...units);
          if (raw.trimStart().slice(0,5).toLowerCase() === 'data:') {
            try {
              const response = await fetch(raw);
              rows.push({data:Array.from(new Uint8Array(await response.arrayBuffer()))});
            } catch { rows.push({failed:true}); }
          } else {
            const image = document.createElement('img');
            image.setAttribute('src', raw);
            rows.push({url:image.src});
          }
        }
        return rows;
        """, arguments: ["inputs": inputs], in: nil, in: .page) { result in
          switch result { case .success(let value): self.rows = value as? [[String: Any]]; case .failure(let error): self.error = error }
          self.completion.fulfill()
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
      self.error = error; completion.fulfill()
    }
  }

  func testNativeAddressesAndDataBytesAgainstWindowlessBrowserWithoutExternalFetches() async throws {
    let fixtures = [
      "https://example.invalid/a b.png", "../render?x=1", "//images.invalid/image", "/image",
      "https://EXAMPLE.invalid:443/a/../image?q='hello'", "https://example.invalid/a/./b",
      "https:\\images.invalid\\image", "\\\\images.invalid\\image", "https://example.invalid/a%20b",
      "https://example.invalid/image?q=漢#part", " \thttps://example.invalid/a\nb\r ",
      "folder/a:b.png", "//[::1]/a.png", "https://example.invalid", "https://example.invalid/a/%2E%2e/b.png",
      "https://bücher.invalid/a.png", "HTTPS://EXAMPLE.invalid:443/a.png",
      "data:,%00%ff+%2b,", "data:text/plain,a%ZZ?x=1#not-body", "data:;base64,YQ", "data:;base64,YQ=",
      "data:;base64,YR==", "data:;base64,YW Jj\n", "data:; base64,YQ==", "data:;base64,_-==",
      "data:,漢", "data:,a #fragment", "data:,%0A%09", "data:no-comma", "data:;base64,",
      "data:;base64,YQ%3D%3D", "data:;base64,YQ%0A==", "data:;base64,YWJ", "data:;base64,AA=", "data:;base64,===="
    ].map { Array($0.utf16) } + [Array("https://example.invalid/?q=".utf16) + [0xD800]]
    let base = URL(string: "https://example.invalid/folder/page?old=1")!
    let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
    let web = WKWebView(frame: .zero, configuration: configuration)
    let done = expectation(description: "owned local URL and data oracle")
    let probe = Probe(done, inputs: fixtures); web.navigationDelegate = probe
    defer { web.stopLoading(); web.navigationDelegate = nil }
    web.loadHTMLString("""
      <!doctype html><meta charset="utf-8">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src 'none'; connect-src data:; script-src 'unsafe-inline'">
      """, baseURL: base)
    await fulfillment(of: [done], timeout: 20)
    XCTAssertNil(probe.error); XCTAssertNil(web.window)
    let rows = try XCTUnwrap(probe.rows); XCTAssertEqual(rows.count, fixtures.count)
    for (units, row) in zip(fixtures, rows) {
      let raw = WebsiteConfigValue.string(units: units)
      var actualURL: String?
      let reader = WebsiteConfigBackgroundRemoteReader(baseURL: base) { url, _ in actualURL = url.absoluteString; return Data([7]) }
      let result = try await reader.read(address: raw, maximumBytes: 1024)
      if let expected = row["url"] as? String {
        XCTAssertEqual(actualURL, expected, String(decoding: units, as: UTF16.self))
      } else if let expected = row["data"] as? [UInt8] {
        guard case .received(let address, let data) = result else { XCTFail("Browser data succeeded but native failed"); continue }
        XCTAssertEqual(address, raw); XCTAssertEqual(data, Data(expected), String(decoding: units, as: UTF16.self))
      } else {
        XCTAssertEqual(row["failed"] as? Bool, true)
        guard case .failed(let address, .transport) = result else { XCTFail("Browser data failed but native succeeded"); continue }
        XCTAssertEqual(address, raw)
      }
    }
  }
}
