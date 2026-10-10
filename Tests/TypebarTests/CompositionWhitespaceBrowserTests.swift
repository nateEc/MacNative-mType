import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import Typebar

/// QA-only engine probe. No website, reference code, or network is loaded.
@MainActor final class CompositionWhitespaceBrowserTests: XCTestCase {
  private final class Probe: NSObject, WKNavigationDelegate {
    let completed: XCTestExpectation
    var values: [String]?
    var error: Error?

    init(completed: XCTestExpectation) { self.completed = completed }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      webView.evaluateJavaScript("""
        Array.from(document.querySelectorAll('div')).map(e => {
          if (getComputedStyle(e).whiteSpace !== 'normal') throw Error('unexpected whitespace');
          return e.innerText;
        })
        """) {
        result, error in
        self.values = result as? [String]
        self.error = error
        self.completed.fulfill()
      }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: Error) {
      self.error = error
      completed.fulfill()
    }
  }

  func testNormalWhitespaceEngineProbeWithoutOpeningWindow() throws {
    let candidates = ["a\nb", "a\r\nb", "首行\n次行", "سلام\nשלום", "a\n\n b", "a\u{200B}\nb"]
    let json = try String(decoding: JSONEncoder().encode(candidates), as: UTF8.self)
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let web = WKWebView(frame: .init(x: 0, y: 0, width: 1000, height: 600),
      configuration: configuration)
    let completion = expectation(description: "local normal-whitespace layout")
    let probe = Probe(completed: completion)
    web.navigationDelegate = probe
    defer { web.stopLoading(); web.navigationDelegate = nil }
    web.loadHTMLString("""
      <!doctype html><html lang="en"><meta charset="utf-8">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'">
      <body><script>
      for (const text of \(json)) {
        const line = document.createElement('div');
        line.textContent = text;
        document.body.appendChild(line);
      }
      </script></body></html>
      """, baseURL: nil)
    wait(for: [completion], timeout: 20)
    XCTAssertNil(probe.error)
    let values = try XCTUnwrap(probe.values)
    print("COMPOSITION WHITESPACE WEBKIT \(values.debugDescription)")
    XCTAssertEqual(values.count, candidates.count)
    XCTAssertEqual(values, ["a b", "a\r b", "首行 次行", "سلام שלום", "a b", "a\u{200B} b"])
    for (candidate, displayed) in zip(candidates, values) {
      let host = NSHostingView(rootView:
        BelowCompositionPrompt(text: candidate,
          font: .monospacedSystemFont(ofSize: 28, weight: .regular), color: .labelColor)
          .frame(width: 1000, height: 600, alignment: .top))
      host.frame = .init(x: 0, y: 0, width: 1000, height: 600)
      for _ in 0..<3 {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
      }
      func fields(_ view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
      }
      let field = try XCTUnwrap(fields(host).first)
      XCTAssertEqual(Array(field.stringValue.utf16), Array(displayed.utf16))
      XCTAssertEqual(field.accessibilityLabel(), "正在组合：\(candidate)")
      XCTAssertNil(host.window)
    }
    XCTAssertNil(web.window)
  }
}
