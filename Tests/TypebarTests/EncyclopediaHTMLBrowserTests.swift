import Foundation
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

  func testNativeIntroductionTextMatchesDetachedDOMWithoutOpeningWindow() async throws {
    var html = [
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
      "<p>first<table><tr><td>cell</table>last</p>",
      "<svg><![CDATA[<noscript><b>literal</b></noscript>]]></svg>tail",
      "<svg><desc><noscript><b>description</b></noscript></desc></svg>tail",
      "<math><mrow><annotation-xml encoding='text/html'><noscript><b>row</b></noscript></annotation-xml></mrow></math>tail",
      "<table><tr><td><noscript><b>cell</b></noscript></td></tr></table>tail",
      "<select><noscript><b>option</b></noscript><option>next</select>tail",
      "<select><noscript><option>first</option></noscript><option>next</select>tail",
      "<select><option><noscript><b>inside</b></noscript>after</select>tail",
      "<select><optgroup><noscript><b>group</b></noscript><option>next</select>tail",
      "<datalist><noscript><b>data</b></noscript></datalist>tail",
      "<svg><title><noscript><b>svg title</b></noscript></title></svg>tail",
      "<svg><title><b>bold</b></title></svg>tail",
      "<svg><desc><b>bold</b></desc></svg>tail",
      "<svg><select><noscript><b>foreign</b></noscript></select></svg>tail",
      "<select><option>one</option></select><noscript><b>outside</b></noscript>tail",
      "<select><optgroup><noscript><b>group</b></noscript></optgroup></select><noscript><b>outside</b></noscript>tail",
      "<svg><foreignObject><select><noscript><b>inside</b></noscript></select></foreignObject></svg><noscript><b>outside</b></noscript>tail",
      "<select><option>one<select><option>two</select><noscript><b>after</b></noscript>tail",
      "<select><option>one</select><select><noscript><b>two</b></noscript></select>tail",
      "<svg><foreignObject><svg><title><b>inner</b></title></svg></foreignObject></svg>tail",
      "<svg><title><svg><title><b>nested</b></title></svg></title></svg>tail",
      "<math><mtext><svg><title><b>mixed</b></title></svg></mtext></math>tail",
      "<math><mtext><noscript><b>inside</b></noscript></mtext><noscript><b>outside</b></noscript></math>tail"
    ]
    let wrappers = [
      ("<div>", "</div>"), ("<select>", "</select>"),
      ("<svg>", "</svg>"), ("<svg><desc>", "</desc></svg>"),
      ("<svg><foreignObject>", "</foreignObject></svg>"),
      ("<math>", "</math>"), ("<math><mtext>", "</mtext></math>"),
      ("<math><annotation-xml encoding='text/html'>", "</annotation-xml></math>"),
      ("<table><tr><td>", "</td></tr></table>")
    ]
    let fragments = [
      "left<noscript><b>right</b></noscript>end",
      "left<noscript>&amp; right</noscript>end",
      "left<script><noscript><b>right</b></noscript></script>end",
      "left<style><noscript><b>right</b></noscript></style>end",
      "left<svg><title><b>right</b></title></svg>end"
    ]
    for (open, close) in wrappers {
      for fragment in fragments { html.append(open + fragment + close + "tail") }
    }
    let browserValues = try await browserTexts(for: html)
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
  }

#if TYPEBAR_LIVE_NETWORK_QA
  func testPublicWikipediaIntroductionsMatchDetachedDOM() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.timeoutIntervalForRequest = 10
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    var samples: [(host: String, pageID: Int, html: String)] = []
    for host in ["en", "de", "zh"] {
      let summaryURL = try XCTUnwrap(URL(string: "https://\(host).wikipedia.org/api/rest_v1/page/random/summary"))
      let (identityData, identityResponse) = try await session.data(from: summaryURL)
      XCTAssertEqual((identityResponse as? HTTPURLResponse)?.statusCode, 200, host)
      let identity = try XCTUnwrap(JSONSerialization.jsonObject(with: identityData) as? [String: Any])
      let pageID = try XCTUnwrap(identity["pageid"] as? Int)
      var components = URLComponents()
      components.scheme = "https"
      components.host = "\(host).wikipedia.org"
      components.path = "/w/api.php"
      components.queryItems = [
        .init(name: "action", value: "query"), .init(name: "format", value: "json"),
        .init(name: "pageids", value: String(pageID)), .init(name: "prop", value: "extracts"),
        .init(name: "exintro", value: "true")
      ]
      let (sectionData, sectionResponse) = try await session.data(from: try XCTUnwrap(components.url))
      XCTAssertEqual((sectionResponse as? HTTPURLResponse)?.statusCode, 200, host)
      let section = try XCTUnwrap(JSONSerialization.jsonObject(with: sectionData) as? [String: Any])
      let query = try XCTUnwrap(section["query"] as? [String: Any])
      let pages = try XCTUnwrap(query["pages"] as? [String: Any])
      let page = try XCTUnwrap(pages[String(pageID)] as? [String: Any])
      let extract = try XCTUnwrap(page["extract"] as? String)
      samples.append((host, pageID, extract))
    }
    for sample in samples {
      let values = try await browserTexts(for: [sample.html])
      let browserText = try XCTUnwrap(values.first,
        "\(sample.host) page \(sample.pageID): HTML UTF-16 \(sample.html.utf16.count)")
      let native = LivePracticeContentService.introductionText(fromHTML: sample.html)
      XCTAssertTrue(native == browserText,
        "\(sample.host) page \(sample.pageID): native UTF-16 \(native?.utf16.count ?? -1), browser \(browserText.utf16.count)")
    }
  }
#endif

  private func browserTexts(for html: [String]) async throws -> [String] {
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
    await fulfillment(of: [completion], timeout: 20)
    XCTAssertNil(probe.error)
    XCTAssertNil(web.window)
    return try XCTUnwrap(probe.values)
  }
}
