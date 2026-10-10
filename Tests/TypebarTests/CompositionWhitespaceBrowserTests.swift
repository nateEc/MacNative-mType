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
    var geometry: [[String: Any]]?
    var error: Error?

    init(completed: XCTestExpectation) { self.completed = completed }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      webView.evaluateJavaScript("""
        Array.from(document.querySelectorAll('div')).map(e => {
          if (getComputedStyle(e).whiteSpace !== 'normal') throw Error('unexpected whitespace');
          const ranges = [];
          for (let i = 0; i < e.firstChild.length; i++) {
            const range = document.createRange();
            range.setStart(e.firstChild, i);
            range.setEnd(e.firstChild, i + 1);
            const rect = range.getBoundingClientRect();
            ranges.push({unit: e.firstChild.data.charCodeAt(i), x: rect.x, y: rect.y,
              width: rect.width, height: rect.height});
          }
          return {text: e.innerText, height: e.getBoundingClientRect().height, ranges};
        })
        """) {
        result, error in
        self.geometry = result as? [[String: Any]]
        self.values = self.geometry?.compactMap { $0["text"] as? String }
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
    let candidates = ["a\nb", "a\r\nb", "首行\n次行", "سلام\nשלום", "a\n\n b", "a\u{200B}\nb", "a\rb"]
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
    XCTAssertEqual(values, ["a b", "a\r b", "首行 次行", "سلام שלום", "a b", "a\u{200B} b", "a\rb"])
    for row in try XCTUnwrap(probe.geometry) {
      let ranges = try XCTUnwrap(row["ranges"] as? [[String: Any]])
      let firstY = try XCTUnwrap(ranges.first?["y"] as? Double)
      for range in ranges where range["unit"] as? Int == 13 {
        XCTAssertEqual(try XCTUnwrap(range["width"] as? Double), 0)
        XCTAssertEqual(try XCTUnwrap(range["y"] as? Double), firstY)
      }
    }
    var singleLineHeight: CGFloat?
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
      if singleLineHeight == nil { singleLineHeight = field.bounds.height }
      if candidate.contains("\r") {
        XCTAssertEqual(field.bounds.height, try XCTUnwrap(singleLineHeight), accuracy: 1)
      }
      // WebKit innerText retains dynamic CR, but its measured glyph has no advance.
      let visibleText = displayed.replacingOccurrences(of: "\r", with: "")
      XCTAssertEqual(Array(field.stringValue.utf16), Array(visibleText.utf16))
      XCTAssertEqual(field.accessibilityLabel(), "正在组合：\(candidate)")
      XCTAssertNil(host.window)
    }
    XCTAssertNil(web.window)
  }
}
