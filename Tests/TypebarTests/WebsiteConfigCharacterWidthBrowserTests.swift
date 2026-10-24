import AppKit
import WebKit
import XCTest
@testable import Typebar

@MainActor
final class WebsiteConfigCharacterWidthBrowserTests: XCTestCase {
  @MainActor private final class Probe: NSObject, WKNavigationDelegate {
    let done: XCTestExpectation
    let fonts: [String]
    var rows: [Double]?, error: Error?
    init(_ done: XCTestExpectation, fonts: [String]) { self.done = done; self.fonts = fonts }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      webView.callAsyncJavaScript("""
        const rows = [];
        for (let i = 0; i < fonts.length; i++) {
          const family = 'OwnedZero' + i;
          const face = new FontFace(family, 'url(data:font/ttf;base64,' + fonts[i] + ')');
          await face.load(); document.fonts.add(face);
          if (face.status !== 'loaded') throw new Error('Owned font failed');
          for (const size of [12, 28, 40]) {
            for (const columns of [20, 30.5, 1000]) {
              const element = document.createElement('div');
              element.style.cssText = 'position:absolute;display:block;padding:0;border:0;max-width:none;box-sizing:content-box;height:1px';
              element.style.fontFamily = family;
              element.style.fontSize = size + 'px';
              element.style.width = columns + 'ch';
              document.body.appendChild(element);
              rows.push(element.getBoundingClientRect().width);
              element.remove();
            }
          }
        }
        return rows;
        """, arguments: ["fonts": fonts], in: nil, in: .page) { result in
          switch result { case .success(let value): self.rows = value as? [Double]; case .failure(let error): self.error = error }
          self.done.fulfill()
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
      self.error = error; done.fulfill()
    }
  }

  func testOwnedZeroMetricsAgainstWindowlessCSSCharacterUnits() async throws {
    let data = [600, 900].map {
      OwnedTestFontFixture.make(postScriptName: "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: ""),
        advanceWidth: $0, character: 48)
    }
    let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
    let web = WKWebView(frame: .zero, configuration: config)
    let done = expectation(description: "owned ch font oracle")
    let probe = Probe(done, fonts: data.map { $0.base64EncodedString() }); web.navigationDelegate = probe
    defer { web.stopLoading(); web.navigationDelegate = nil }
    web.loadHTMLString("""
      <!doctype html><meta charset="utf-8">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; font-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
      <body></body>
      """, baseURL: nil)
    await fulfillment(of: [done], timeout: 20)
    XCTAssertNil(probe.error); XCTAssertNil(web.window)
    let widths = try XCTUnwrap(probe.rows); XCTAssertEqual(widths.count, 18)
    var index = 0
    for bytes in data {
      for size: Double in [12, 28, 40] {
        for columns: Double in [20, 30.5, 1000] {
          let draft = try WebsiteConfigNativeProfile.prepareDraft("{\"fontSize\":\(size / 16),\"maxLineWidth\":\(columns)}",
            pointsPerRem: 16, context: .init())
          let resource = try WebsiteConfigFontResource.prepare(typography: draft.keyboardTypography,
            language: .english, local: .data(bytes))
          guard index < widths.count else { return XCTFail("Missing browser result") }
          // WebKit resolves layout lengths to 1/64 CSS px; native keeps fractional points.
          XCTAssertEqual(resource.chAdvance * columns, widths[index], accuracy: 1.0 / 64,
            "Owned zero advance must determine ch, not a generic font-size multiplier")
          index += 1
        }
      }
    }
  }
}
