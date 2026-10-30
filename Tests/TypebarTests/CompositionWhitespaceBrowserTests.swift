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
          return {text: e.innerText, height: e.getBoundingClientRect().height,
            fontSize: getComputedStyle(e).fontSize, fontFamily: getComputedStyle(e).fontFamily, ranges};
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
    let candidates = ["a\nb", "a\r\nb", "首行\n次行", "سلام\nשלום", "a\n\n b", "a\u{200B}\nb", "a\rb", " \u{0301}b",
      "a \r b", " \r b", "a \r ", "a\u{2028}b", "a\u{2029}b",
      "a \u{2028} b", " \u{2028} b", "a \u{2028} ",
      "a \u{2029} b", " \u{2029} b", "a \u{2029} "]
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
    XCTAssertEqual(values, ["a b", "a\r b", "首行 次行", "سلام שלום", "a b", "a\u{200B} b", "a\rb", "\u{0301}b",
      "a \r b", "\r b", "a \r", "a\u{2028}b", "a\u{2029}b",
      "a \u{2028} b", "\u{2028} b", "a \u{2028}",
      "a \u{2029} b", "\u{2029} b", "a \u{2029}"])
    for row in try XCTUnwrap(probe.geometry) {
      let ranges = try XCTUnwrap(row["ranges"] as? [[String: Any]])
      let firstY = try XCTUnwrap(ranges.first?["y"] as? Double)
      for range in ranges where [13, 0x2028, 0x2029].contains(range["unit"] as? Int ?? -1) {
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
      if candidate.unicodeScalars.contains(where: { [13, 0x2028, 0x2029].contains(Int($0.value)) }) {
        XCTAssertEqual(field.bounds.height, try XCTUnwrap(singleLineHeight), accuracy: 1)
      }
      // The measured zero-advance controls remain in innerText, not in the native display string.
      let visibleText = displayed.replacingOccurrences(of: "\r", with: "")
        .replacingOccurrences(of: "\u{2028}", with: "").replacingOccurrences(of: "\u{2029}", with: "")
      XCTAssertEqual(Array(field.stringValue.utf16), Array(visibleText.utf16))
      XCTAssertEqual(field.accessibilityLabel(), "正在组合：\(candidate)")
      XCTAssertNil(host.window)
    }
    XCTAssertNil(web.window)
  }

  func testControlOnlyCandidatesAgainstActualBrowserEmptyContentAndNativeRanges() throws {
    let cases: [(String, Bool)] = [("\u{000C}", true), ("\u{000C}\u{000C}", true),
      (" \u{000C}\t\r\n ", true), ("\u{000B}", false), ("\u{0085}", false),
      ("\u{000C}\u{000B}", false), ("\u{000C}\u{0085}", false),
      ("\u{000C}\r", true), ("\r\u{000C}", true),
      ("\u{000C}\u{2028}", false), ("\u{000C}\u{2029}", false),
      ("\u{200B}\u{000C}", false), ("\u{000C}\u{200B}", false),
      ("\u{000C} a", false), ("a \u{000C}", false), ("\u{000C} \u{000C} a", false),
      ("\u{00A0}\u{000C}", false), ("\u{000C}\u{00A0}", false), (" \r \r ", true)]
    let json = String(decoding: try JSONEncoder().encode(cases.map { $0.0 }), as: UTF8.self)
    let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
    let web = WKWebView(frame: .init(x: 0, y: 0, width: 1000, height: 800), configuration: configuration)
    let completion = expectation(description: "local control-only whitespace layout")
    let probe = Probe(completed: completion); web.navigationDelegate = probe
    defer { web.stopLoading(); web.navigationDelegate = nil }
    web.loadHTMLString("""
      <!doctype html><meta charset="utf-8">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'">
      <style>div { font: 28px monospace; white-space: normal; }</style>
      <body><script>for (const text of \(json)) {
        const row = document.createElement('div'); row.textContent = text; document.body.appendChild(row);
      }</script></body>
      """, baseURL: nil)
    wait(for: [completion], timeout: 20)
    XCTAssertNil(probe.error)
    let rows = try XCTUnwrap(probe.geometry); XCTAssertEqual(rows.count, cases.count)
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    func root(_ text: String) -> some View {
      BelowCompositionPrompt(text: text, font: font, color: .black)
        .frame(width: 800, height: 200, alignment: .top)
    }
    let host = NSHostingView(rootView: root(""))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 800, height: 200),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.contentView = nil; window.close() }
    func field(_ view: NSView) -> BelowCompositionField? {
      (view as? BelowCompositionField) ?? view.subviews.lazy.compactMap { field($0) }.first
    }
    func flush() {
      for _ in 0..<3 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }
    flush()
    let original = try XCTUnwrap(field(host)), emptyHeight = original.bounds.height
    for ((candidate, empty), row) in zip(cases, rows) {
      XCTAssertEqual(row["fontSize"] as? String, "28px")
      XCTAssertEqual((row["text"] as? String)?.isEmpty, empty)
      let height = try XCTUnwrap(row["height"] as? Double)
      let ranges = try XCTUnwrap(row["ranges"] as? [[String: Any]])
      if empty {
        XCTAssertEqual(height, 0)
        for range in ranges { XCTAssertEqual(try XCTUnwrap(range["width"] as? Double), 0) }
      } else {
        XCTAssertGreaterThan(height, 0)
        for range in ranges where [11, 12, 133].contains(range["unit"] as? Int ?? -1) {
          XCTAssertGreaterThan(try XCTUnwrap(range["width"] as? Double), 0)
        }
      }
      XCTAssertEqual(BelowCompositionProjection(candidate).displayed.isEmpty, empty, candidate.debugDescription)
      host.rootView = root(candidate); flush()
      let current = try XCTUnwrap(field(host)); XCTAssertTrue(current === original)
      XCTAssertEqual(current.sourceText, candidate)
      XCTAssertEqual(current.accessibilityLabel(), "正在组合：\(candidate)")
      if empty {
        XCTAssertEqual(current.stringValue, " ")
        XCTAssertEqual(current.bounds.height, emptyHeight, accuracy: 1)
        XCTAssertNil(current.markedScreenRect(for: .init(location: 0, length: candidate.utf16.count), markedText: candidate))
        XCTAssertNil(current.insertionScreenRect(at: 0, markedText: candidate))
      } else {
        let index = try XCTUnwrap(candidate.utf16.firstIndex { [11, 12, 133].contains(Int($0)) })
        let offset = candidate.utf16.distance(from: candidate.utf16.startIndex, to: index)
        let rect = try XCTUnwrap(current.markedScreenRect(for: .init(location: offset, length: 1), markedText: candidate))
        XCTAssertEqual(rect.actualRange, NSRange(location: offset, length: 1))
        XCTAssertGreaterThan(rect.rect.width, 0)
      }
    }
    XCTAssertNil(web.window); XCTAssertFalse(window.isVisible)
  }

  func testAdvancingControlsKeepBrowserRowAndNativeSourceRectangles() throws {
    let controls = ["\u{000B}", "\u{000C}", "\u{0085}"]
    let candidates = controls.flatMap { ["a\($0)b", "a \($0) b", "\($0)b"] }
    let json = String(decoding: try JSONEncoder().encode(candidates), as: UTF8.self)
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let web = WKWebView(frame: .init(x: 0, y: 0, width: 1000, height: 600), configuration: configuration)
    let completion = expectation(description: "local advancing-control layout")
    let probe = Probe(completed: completion)
    web.navigationDelegate = probe
    defer { web.stopLoading(); web.navigationDelegate = nil }
    web.loadHTMLString("""
      <!doctype html><html lang="en"><meta charset="utf-8">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'">
      <style>div { font: 28px monospace; white-space: normal; }</style>
      <body><script>
      for (const text of \(json)) {
        const row = document.createElement('div'); row.textContent = text; document.body.appendChild(row);
      }
      </script></body></html>
      """, baseURL: nil)
    wait(for: [completion], timeout: 20)
    XCTAssertNil(probe.error)
    let rows = try XCTUnwrap(probe.geometry)
    XCTAssertEqual(rows.count, candidates.count)
    let snapshotDone = expectation(description: "local control glyph pixels")
    var snapshot: NSImage?, snapshotError: Error?
    web.takeSnapshot(with: nil) { image, error in
      snapshot = image; snapshotError = error; snapshotDone.fulfill()
    }
    wait(for: [snapshotDone], timeout: 20)
    XCTAssertNil(snapshotError)
    let image = try XCTUnwrap(snapshot)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      .write(to: URL(fileURLWithPath: "/tmp/typebar-below-advancing-control-webkit-20261030.png"))
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    func root(_ text: String) -> some View {
      BelowCompositionPrompt(text: text, font: font, color: .black)
        .frame(width: 800, height: 200, alignment: .top)
    }
    let host = NSHostingView(rootView: root("ab"))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 800, height: 200),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.contentView = nil; window.close() }
    func field(_ view: NSView) -> BelowCompositionField? {
      (view as? BelowCompositionField) ?? view.subviews.lazy.compactMap { field($0) }.first
    }
    func flush() {
      for _ in 0..<3 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }
    flush()
    let original = try XCTUnwrap(field(host)), height = original.bounds.height
    for (candidate, row) in zip(candidates, rows) {
      XCTAssertEqual(row["fontSize"] as? String, "28px")
      XCTAssertEqual(row["fontFamily"] as? String, "monospace")
      let ranges = try XCTUnwrap(row["ranges"] as? [[String: Any]])
      let control = try XCTUnwrap(ranges.first { [11, 12, 133].contains($0["unit"] as? Int ?? -1) })
      let baselineY = try XCTUnwrap(ranges.first?["y"] as? Double)
      XCTAssertGreaterThan(try XCTUnwrap(control["width"] as? Double), 0)
      for range in ranges { XCTAssertEqual(try XCTUnwrap(range["y"] as? Double), baselineY) }
      host.rootView = root(candidate); flush()
      let current = try XCTUnwrap(field(host))
      XCTAssertTrue(current === original)
      XCTAssertEqual(current.bounds.height, height, accuracy: 1, candidate.debugDescription)
      XCTAssertEqual(current.sourceText, candidate)
      XCTAssertEqual(current.accessibilityLabel(), "正在组合：\(candidate)")
      let offset = try XCTUnwrap(candidate.utf16.firstIndex { [11, 12, 133].contains(Int($0)) })
      let location = candidate.utf16.distance(from: candidate.utf16.startIndex, to: offset)
      let rect = current.markedScreenRect(for: .init(location: location, length: 1), markedText: candidate)
      XCTAssertNotNil(rect, candidate.debugDescription)
      if let rect {
        XCTAssertGreaterThan(rect.rect.width, 0)
        XCTAssertEqual(rect.actualRange, NSRange(location: location, length: 1))
        current.drawsBackground = true
        current.backgroundColor = .white
        let nativeBitmap = try XCTUnwrap(current.bitmapImageRepForCachingDisplay(in: current.bounds))
        current.cacheDisplay(in: current.bounds, to: nativeBitmap)
        let local = current.convert(window.convertFromScreen(rect.rect), from: nil)
        let scaleX = CGFloat(nativeBitmap.pixelsWide) / current.bounds.width
        let minimumX = max(0, Int((local.minX + 1) * scaleX))
        let maximumX = min(nativeBitmap.pixelsWide, Int((local.maxX - 1) * scaleX))
        var ink = 0
        if minimumX < maximumX {
          for x in minimumX..<maximumX {
            for y in 0..<nativeBitmap.pixelsHigh {
              if let color = nativeBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                color.alphaComponent > 0.1, max(color.redComponent, color.greenComponent, color.blueComponent) < 0.5 { ink += 1 }
            }
          }
        }
        XCTAssertGreaterThan(ink, 0, "Missing-glyph rectangle must contain actual ink: \(candidate.debugDescription)")
        if location == 1 {
          let unit = candidate.utf16[offset]
          try XCTUnwrap(nativeBitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/typebar-below-advancing-control-native-\(unit)-20261030.png"))
        }
      }
      print("ADVANCING CONTROL \(candidate.debugDescription) browser=\(control) nativeHeight=\(current.bounds.height) nativeRect=\(String(describing: rect))")
    }
    XCTAssertNil(web.window)
    XCTAssertFalse(window.isVisible)
  }
}
