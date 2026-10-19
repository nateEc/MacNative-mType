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
      "<p>one</p>\n<p>two</p><p>three</p>",
      "<math><mi>x</mi><mo>+</mo><mn>2</mn></math><p>equation</p>",
      "<svg><title>Vector title</title><text>visible label</text></svg>after",
      "<ruby>漢<rt>かん</rt>字<rt>じ</rt></ruby>",
      "<textarea>&amp; raw <b>markup</b></textarea>tail",
      "<select><option>first<option>second</select>tail",
      "<noscript><p>fallback</p></noscript>tail",
      "<noscript>&amp; <b>literal</b></noscript>tail",
      "<NOSCRIPT class='reader'><span>upper</span></NOSCRIPT>tail",
      "<noscript data-label='a>b'><b>quoted</b></noscript>tail",
      "<noscript>unfinished <b>tag",
      "<script>const tag = '<noscript><b>x</b></noscript>';</script>tail",
      "<style>.x:before{content:'<noscript><b>x</b></noscript>'}</style>tail",
      "<div data-fragment='<noscript><b>x</b></noscript>'>shown</div>",
      "<svg><noscript><text>foreign</text></noscript></svg>tail",
      "<svg><foreignObject><div><noscript><b>html</b></noscript></div></foreignObject></svg>tail",
      "<math><annotation-xml encoding='text/html'><noscript><b>math html</b></noscript></annotation-xml></math>tail",
      "<math><annotation-xml data-x='encoding=text/html' encoding='application/xml'><noscript><b>math xml</b></noscript></annotation-xml></math>tail",
      "<math><annotation-xml data-x=\"encoding='text/html'\" encoding='application/xml'><noscript><b>quoted xml</b></noscript></annotation-xml></math>tail",
      "<math><mtext><noscript><b>math text</b></noscript></mtext></math>tail",
      "<noscript>outer<noscript>inner</noscript>rest</noscript>tail",
      "<iframe><noscript><b>frame</b></noscript></iframe>tail",
      "<xmp><noscript><b>raw</b></noscript></xmp>tail",
      "<!-- <noscript><b>comment</b></noscript> -->tail",
      "<p>first<table><tr><td>cell</table>last</p>"
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
      if source.contains("data-x='encoding=text/html'") {
        XCTAssertEqual(browserText, "math xmltail", "Only the actual encoding attribute controls HTML integration")
      }
      if source.contains("quoted xml") {
        XCTAssertEqual(browserText, "quoted xmltail")
      }
    }
    XCTAssertNil(web.window)
  }
}
