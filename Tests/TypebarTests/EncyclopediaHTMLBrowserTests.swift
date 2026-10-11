import WebKit
import XCTest
@testable import Typebar

/// QA-only local DOM comparison. Production has no browser dependency.
@MainActor final class EncyclopediaHTMLBrowserTests: XCTestCase {
  private final class Probe: NSObject, WKNavigationDelegate {
    let completed: XCTestExpectation
    var values: [String]?
    var error: Error?
    init(completed: XCTestExpectation) { self.completed = completed }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      webView.evaluateJavaScript("window.ownedExtracts") { result, error in
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

  func testNativeIntroductionTextMatchesDetachedDOMWithoutOpeningWindow() throws {
    let html = [
      "<p>North <b>harbor</b>&nbsp;2026 [12]</p><p>South &amp; west &#x1F680;.</p>",
      "<p>left\nright\tend</p><p>next&nbsp;word</p>",
      "<div>Über<br>12</div><div>&NotEqualTilde; ‘Boote’</div><!--ignored--><p>am</p><p>Ufer.</p>",
      "<img src='https://invalid.example/owned.png'>North<script>owned()</script><style>.x{}</style>tail",
      "<p>One <b>two</p>three",
      "<table>before<tr><td>x<td>y</table>after",
      "<template><b>hidden</b></template>tail",
      "<div hidden>hidden text</div><span title='attribute'>visible &copy; &#169;</span>",
      "<p>one</p>\n<p>two</p><p>three</p>"
    ]
    let encoded = String(decoding: try JSONEncoder().encode(html), as: UTF8.self)
      .replacingOccurrences(of: "<", with: "\\u003c")
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let web = WKWebView(frame: .zero, configuration: configuration)
    let completion = expectation(description: "local inert DOM text extraction")
    let probe = Probe(completed: completion)
    web.navigationDelegate = probe
    defer { web.stopLoading(); web.navigationDelegate = nil }
    web.loadHTMLString("""
      <!doctype html><meta charset="utf-8">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'">
      <script>
      window.ownedExtracts = \(encoded).map(html => {
        const container = document.createElement('div');
        container.innerHTML = html.replace(/<\\/p><p>+/g, ' ');
        return container.textContent;
      });
      </script>
      """, baseURL: nil)
    wait(for: [completion], timeout: 20)
    XCTAssertNil(probe.error)
    let browserValues = try XCTUnwrap(probe.values)
    XCTAssertEqual(browserValues.count, html.count)
    for (source, browserText) in zip(html, browserValues) {
      XCTAssertEqual(LivePracticeContentService.introductionText(fromHTML: source), browserText, source)
    }
    XCTAssertNil(web.window)
  }
}
