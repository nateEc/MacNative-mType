import AppKit
import SwiftUI
import Vision
import XCTest
@testable import Typebar

@MainActor final class CorpusAttributionTests: XCTestCase {
  private var resources: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Resources")
  }

  private func mount<V: View>(_ view: V, size: CGSize) -> (NSHostingView<AnyView>, NSWindow) {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height)))
    let window = NSWindow(contentRect: .init(origin: .zero, size: size),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    for _ in 0..<5 {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    return (host, window)
  }

  // An unshown SwiftUI host has no exported AX tree. Read its actual rendered
  // pixels instead, without seeding Vision with the expected credit strings.
  private func visibleLines(in host: NSView, capture: String) throws -> [VNRecognizedTextObservation] {
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      .write(to: URL(fileURLWithPath: capture))
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US"]
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
    return request.results ?? []
  }

  private func scrollView(in view: NSView) -> NSScrollView? {
    if let scroll = view as? NSScrollView { return scroll }
    return view.subviews.lazy.compactMap { self.scrollView(in: $0) }.first
  }

  func testAllNoticeChoicesReadTheirActualLocalFilesAndKeepTheFullCredit() throws {
    for notice in CorpusLicenseNotice.allCases {
      XCTAssertFalse(try XCTUnwrap(notice.read(resourceDirectory: resources)).isEmpty)
    }
    let notice = try XCTUnwrap(CorpusLicenseNotice.englishLarge.read(resourceDirectory: resources))
    XCTAssertTrue(notice.contains(LargeEnglishAttribution.sourceName))
    XCTAssertTrue(notice.contains(LargeEnglishAttribution.copyright))
    XCTAssertTrue(notice.contains("prominently displayed"))
    XCTAssertTrue(notice.contains("=== WordNet"))
    XCTAssertTrue(notice.contains("wordfreq 3.1.1"))
  }

  func testMissingAndInvalidNoticeFilesAreNotReportedAsValidText() throws {
    XCTAssertNil(CorpusLicenseNotice.englishLarge.read(resourceDirectory: nil))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    XCTAssertNil(CorpusLicenseNotice.englishLarge.read(resourceDirectory: directory))
    try Data([0xff]).write(to: directory.appendingPathComponent("EnglishLargeCorpusNotices.txt"))
    XCTAssertNil(CorpusLicenseNotice.englishLarge.read(resourceDirectory: directory))
  }

  func testActualAboutIncludesProminentAttributionWithoutShowingAWindow() throws {
    let suite = "CorpusAttributionTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    // No real service or account is involved in the About view's existing task.
    defaults.set("", forKey: "remoteAccount.endpoint.v1")
    let account = AccountSession(defaults: defaults)
    let (host, window) = mount(AboutTypebarView(metadata: .init(info: [:]), account: account),
      size: .init(width: 620, height: 760))
    defer {
      host.rootView = AnyView(EmptyView()); window.contentView = nil; window.close()
      defaults.removePersistentDomain(forName: suite)
    }
    let lines = try visibleLines(in: host, capture: "/tmp/typebar-large-english-about.png")
    for expected in [LargeEnglishAttribution.sourceName, LargeEnglishAttribution.copyright] {
      let line = try XCTUnwrap(lines.first { $0.topCandidates(1).first?.string == expected })
      XCTAssertGreaterThan(line.boundingBox.minY, 0.5, "Credit must be prominent in the first viewport")
    }
    XCTAssertFalse(window.isVisible)
    XCTAssertNil(window.attachedSheet)
  }

  func testNativeLicenseReaderDisplaysTheBundledDocumentWithoutShowingAWindow() throws {
    let (host, window) = mount(CorpusLicensesView(resourceDirectory: resources),
      size: .init(width: 608, height: 668))
    defer { host.rootView = AnyView(EmptyView()); window.contentView = nil; window.close() }
    let lines = try visibleLines(in: host, capture: "/tmp/typebar-large-english-license-reader.png")
    let text = lines.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    // Vision may split one rendered sentence into separate observations.
    // Normalize only whitespace; keep the actual wording and raw diagnostics.
    let readableText = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    XCTAssertTrue(readableText.contains("Typebar independent large English corpus"), text)
    XCTAssertTrue(readableText.contains("Includes material from the UK Advanced Cryptics Dictionary."), text)
    XCTAssertFalse(text.contains("此安装包的许可文件无法读取"), text)
    let scroll = try XCTUnwrap(scrollView(in: host))
    let document = try XCTUnwrap(scroll.documentView)
    XCTAssertGreaterThan(document.bounds.height, scroll.contentView.bounds.height)
    let bottom = document.isFlipped ? document.bounds.maxY - scroll.contentView.bounds.height : 0
    scroll.contentView.scroll(to: .init(x: 0, y: bottom))
    scroll.reflectScrolledClipView(scroll.contentView)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    let tail = try visibleLines(in: host, capture: "/tmp/typebar-large-english-license-reader-tail.png")
      .compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    XCTAssertTrue(tail.contains("10.1080/17470218.2013.850521"), tail)
    XCTAssertFalse(window.isVisible)
  }
}
