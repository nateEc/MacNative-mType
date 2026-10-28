import Foundation
import WebKit
import XCTest
@testable import Typebar

/// QA-only local browser oracle; never linked into or loaded by the application.
@MainActor
final class WebsiteConfigBackgroundGeometryBrowserTests: XCTestCase {
  private final class Probe: NSObject, WKNavigationDelegate {
    let completed: XCTestExpectation
    var values: [[String: Any]]?
    var error: Error?
    init(completed: XCTestExpectation) { self.completed = completed }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      webView.callAsyncJavaScript("return await window.geometryReady", arguments: [:], in: nil,
        in: .page) { result in
        switch result {
        case .success(let value): self.values = value as? [[String: Any]]
        case .failure(let error): self.error = error
        }
        self.completed.fulfill()
      }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
      self.error = error; completed.fulfill()
    }
  }

  func testSelectedFileDataURLsAgainstActualHiddenBrowserImageDecode() async throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned source") }
    struct Frame: Decodable { let stored: String? }
    struct Sample: Decodable { let frames: [Frame] }
    struct Output: Decodable { let fileFixtures: [Sample] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path, reference, "--background-settings"]
    process.standardOutput = output; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    let payload = try JSONDecoder().decode(Output.self, from: data)
    let addresses = payload.fileFixtures.compactMap { $0.frames.last?.stored }; XCTAssertEqual(addresses.count, 18)
    let json = String(decoding: try JSONEncoder().encode(addresses), as: UTF8.self)
    let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
    let web = WKWebView(frame: .zero, configuration: configuration)
    let completion = expectation(description: "owned selected file data URLs")
    let probe = Probe(completed: completion); web.navigationDelegate = probe
    defer { web.stopLoading(); web.navigationDelegate = nil }
    web.loadHTMLString("""
      <!doctype html><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; script-src 'unsafe-inline'">
      <script>window.geometryReady=(async()=>{
        const rows=[];for(const address of \(json)) {
          const image=new Image();image.src=address;let ready=true;
          try{await image.decode();}catch{ready=false;}rows.push({ready});
        }return rows;
      })();</script>
      """, baseURL: nil)
    await fulfillment(of: [completion], timeout: 20)
    XCTAssertNil(probe.error); XCTAssertNil(web.window)
    let rows = try XCTUnwrap(probe.values); XCTAssertEqual(rows.count, addresses.count)
    for (address, row) in zip(addresses, rows) {
      let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(address.components(separatedBy: ",").last)))
      let resource = try WebsiteConfigBackgroundResource.prepare(loadedData: bytes, source: .local)
      let ready: Bool; if case .ready = resource.state { ready = true } else { ready = false }
      XCTAssertEqual(ready, try XCTUnwrap(row["ready"] as? Bool), address.prefix(48).description)
    }
  }

  func testSettingsRangeSanitationAgainstActualHiddenBrowser() async throws {
    let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
    let web = WKWebView(frame: .zero, configuration: configuration)
    let completion = expectation(description: "owned local range sanitation")
    let probe = Probe(completed: completion); web.navigationDelegate = probe
    defer { web.stopLoading(); web.navigationDelegate = nil }
    web.loadHTMLString("""
      <!doctype html><meta charset="utf-8">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'">
      <script>window.geometryReady=Promise.resolve((()=>{
        const rows=[];
        for(const max of [5,2,2,1])for(const token of ['NaN','Infinity','-Infinity','-0','0.05','0.15','0.35','0.75','1e-7','200','-1']) {
          const input=document.createElement('input');input.type='range';input.min='0';input.max=String(max);input.step='0.1';input.value=token;
          rows.push({max,token,value:input.valueAsNumber});
        }
        return rows;
      })());</script>
      """, baseURL: nil)
    await fulfillment(of: [completion], timeout: 20)
    XCTAssertNil(probe.error); XCTAssertNil(web.window)
    let rows = try XCTUnwrap(probe.values); XCTAssertEqual(rows.count, 44)
    for row in rows {
      let token = try XCTUnwrap(row["token"] as? String), max = try XCTUnwrap(row["max"] as? Double)
      let input: Double = token == "NaN" ? .nan : token == "Infinity" ? .infinity : token == "-Infinity" ? -.infinity : try XCTUnwrap(Double(token))
      XCTAssertEqual(BackgroundSettingsPreferences.sanitized(input, range: 0...max, step: 0.1), try XCTUnwrap(row["value"] as? Double), "\(max):\(token)")
    }
  }

  func testPinnedDeclarationsInActualCSSOMWithoutOpeningWindow() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? environment["TYPEBAR_REFERENCE_ROOT"]
    else { throw XCTSkip("Requires pinned reference checkout") }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-background-filter.mjs").path, reference]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(payload["pin"] as? String, "91bd24bb8513785c7364cbea29296ff7adafac41")
    let groups = try XCTUnwrap(payload["geometryFixtures"] as? [[[String: Any]]])
    let json = String(decoding: try JSONSerialization.data(withJSONObject: groups), as: UTF8.self)
      .replacingOccurrences(of: "<", with: "\\u003c")
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let web = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
    let completion = expectation(description: "owned local background CSSOM")
    let probe = Probe(completed: completion)
    web.navigationDelegate = probe
    defer { web.stopLoading(); web.navigationDelegate = nil }
    web.loadHTMLString("""
      <!doctype html><meta charset="utf-8">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
      <style>html,body{margin:0}#box{position:fixed;left:0;top:0;width:800px;height:600px;display:flex;justify-content:center;align-items:center}</style>
      <div id="box"></div><script>
      window.geometryReady = (async () => {
        const canvas = document.createElement('canvas'); canvas.width = 100; canvas.height = 50;
        const source = canvas.toDataURL(), parent = document.getElementById('box'), results = [];
        let groupIndex = 0;
        for (const group of \(json)) {
          const image = new Image(); image.src = source; await image.decode();
          parent.replaceChildren(image);
          let index = 0;
          for (const op of group) {
            document.documentElement.style.fontSize = op.root + 'px';
            if (op.style) for (const [key,value] of Object.entries(op.style)) image.style[key] = value;
            const cs = getComputedStyle(image), rect = image.getBoundingClientRect();
            results.push({group:groupIndex,index:index++,x:rect.x,y:rect.y,width:rect.width,height:rect.height,
              boxX:image.offsetLeft,boxY:image.offsetTop,boxWidth:parseFloat(cs.width),boxHeight:parseFloat(cs.height),
              topStyle:image.style.top,widthStyle:image.style.width,filterStyle:image.style.filter,transformStyle:image.style.transform});
          }
          groupIndex++;
        }
        return results;
      })();
      </script>
      """, baseURL: nil)
    await fulfillment(of: [completion], timeout: 20)
    XCTAssertNil(probe.error); XCTAssertNil(web.window)
    let rows = try XCTUnwrap(probe.values)
    XCTAssertEqual(rows.count, 16)
    func number(_ text: String) throws -> Double {
      switch text {
      case "Infinity": return .infinity
      case "-Infinity": return -.infinity
      case "NaN": return .nan
      default: return try XCTUnwrap(Double(text))
      }
    }
    for (groupIndex, group) in groups.enumerated() {
      var native: WebsiteConfigBackgroundGeometry?
      var filter = WebsiteConfigBackgroundFilter()
      for (index, op) in group.enumerated() {
        if let blur = op["blur"] as? String {
          let value = try number(blur)
          if native == nil { native = .init(blurRem: value) } else { _ = native?.apply(blurRem: value) }
          _ = filter.apply(.init(blurRem: value, brightness: 1, saturation: 1, opacity: 1))
        }
        let state = try XCTUnwrap(native)
        let root = try XCTUnwrap(op["root"] as? Double)
        let layout = try state.resolve(viewport: .init(width: 800, height: 600),
          intrinsicSize: .init(width: 100, height: 50), pointsPerRem: root)
        let row = try XCTUnwrap(rows.first { $0["group"] as? Int == groupIndex && $0["index"] as? Int == index })
        let expected: [String: Double] = ["boxX": layout.imageBox.minX, "boxY": layout.imageBox.minY,
          "boxWidth": layout.imageBox.width, "boxHeight": layout.imageBox.height,
          "x": layout.transformedBounds.minX, "y": layout.transformedBounds.minY,
          "width": layout.transformedBounds.width, "height": layout.transformedBounds.height]
        for (key, value) in expected {
          // Allow one CSS layout quantum plus float matrix rounding, not a visual approximation.
          XCTAssertEqual(try XCTUnwrap(row[key] as? Double), value, accuracy: 0.02, "\(groupIndex)/\(index) \(key)")
        }
        let filterStyle = try XCTUnwrap(row["filterStyle"] as? String)
        if filterStyle.isEmpty { XCTAssertEqual(filter.stages, []) }
        else {
          XCTAssertTrue(filterStyle.hasPrefix("blur(")); XCTAssertTrue(filterStyle.hasSuffix("rem)"))
          let amount = try XCTUnwrap(Double(filterStyle.dropFirst(5).dropLast(4)))
          XCTAssertEqual(filter.stages, [.blur(rem: amount)])
        }
        let transformStyle = try XCTUnwrap(row["transformStyle"] as? String)
        if transformStyle.isEmpty { XCTAssertEqual(state.scale, 1) }
        else { XCTAssertEqual(state.scale, try XCTUnwrap(Double(transformStyle.dropFirst(6).dropLast()))) }
      }
    }
    let freshInvalid = try XCTUnwrap(rows.first { $0["group"] as? Int == 1 && $0["index"] as? Int == 0 })
    XCTAssertEqual(freshInvalid["boxWidth"] as? Double, 100)
    XCTAssertEqual(freshInvalid["boxHeight"] as? Double, 50)
  }
}
