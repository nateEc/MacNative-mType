import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PracticePromptViewportTests: XCTestCase {
  private func root(fontSize: CGFloat, lines: Int, measures: Bool = true) -> some View {
    let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
    let text = AttributedString(String(repeating: "probe cue mark ", count: 30))
    return PracticePromptViewport(
      text: text, font: font, lineSpacing: 12, isRightToLeft: false, lineCount: lines,
      measuresTextRows: measures
    ) {
      Text(text).font(Font(font)).lineSpacing(12)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }.frame(width: 360)
  }

  private func settle(_ view: NSView) {
    view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    view.layoutSubtreeIfNeeded()
  }

  private func scroll(in view: NSView) throws -> NSScrollView {
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    return try XCTUnwrap(descendants(view).compactMap { $0 as? NSScrollView }.first)
  }

  private func viewport(fontSize: CGFloat, lines: Int, measures: Bool = true) throws -> (NSWindow, NSScrollView) {
    let host = NSHostingView(rootView: root(fontSize: fontSize, lines: lines, measures: measures))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 360, height: 400),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    settle(host)
    return (window, try scroll(in: host))
  }

  func testOrdinaryViewportUsesThreeNativeRowsAndTracksTheActualFont() throws {
    for size: CGFloat in [18, 40] {
      let (window, scroll) = try viewport(fontSize: size, lines: 3)
      defer { window.contentView = nil }
      let row = NSLayoutManager().defaultLineHeight(for: .monospacedSystemFont(ofSize: size, weight: .medium)) + 12
      XCTAssertEqual(scroll.bounds.height, row * 3, accuracy: 1)
      XCTAssertFalse(window.isVisible)
      if size == 40, let directory = ProcessInfo.processInfo.environment["TYPEBAR_VIEWPORT_QA_IMAGE_DIRECTORY"],
        let host = window.contentView, let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("ordinary-three-rows.png"))
      }
    }
  }

  func testZenViewportUsesTwoNativeRowsInsteadOfTheOrdinaryThree() throws {
    let (window, scroll) = try viewport(fontSize: 28, lines: 2)
    defer { window.contentView = nil }
    let row = NSLayoutManager().defaultLineHeight(for: .monospacedSystemFont(ofSize: 28, weight: .medium)) + 12
    XCTAssertEqual(scroll.bounds.height, row * 2, accuracy: 1)
    XCTAssertFalse(window.isVisible)
  }

  func testSameMountedViewportRecalculatesAfterFontAndModeChange() throws {
    let host = NSHostingView(rootView: root(fontSize: 18, lines: 3))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 360, height: 400),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    defer { window.contentView = nil }
    settle(host)
    let initial = (NSLayoutManager().defaultLineHeight(for: .monospacedSystemFont(ofSize: 18, weight: .medium)) + 12) * 3
    XCTAssertEqual(try scroll(in: host).bounds.height, initial, accuracy: 1)
    host.rootView = root(fontSize: 40, lines: 2)
    settle(host)
    let expected = (NSLayoutManager().defaultLineHeight(for: .monospacedSystemFont(ofSize: 40, weight: .medium)) + 12) * 2
    XCTAssertEqual(try scroll(in: host).bounds.height, expected, accuracy: 1)
    XCTAssertFalse(window.isVisible)
  }

  func testSpecialRenderersKeepTheirExplicitUnmeasuredFallback() throws {
    let (window, scroll) = try viewport(fontSize: 40, lines: 3, measures: false)
    defer { window.contentView = nil }
    XCTAssertEqual(scroll.bounds.height, 184, accuracy: 1)
    XCTAssertFalse(window.isVisible)
  }

  func testEmptyShortAndPartialPromptsReserveCompleteRows() {
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)
    let expected = PromptViewportLayout.fallbackHeight(font: font, lineSpacing: 12, lineCount: 3)
    for text in ["", "probe", "probe\ncue", "probe\ncue\nmark", String(repeating: "probe ", count: 100)] {
      XCTAssertEqual(PromptViewportLayout.height(in: AttributedString(text), width: 360,
        font: font, lineSpacing: 12, lineCount: 3), expected, accuracy: 1, text)
    }
  }

  func testUnavailableWidthUsesTheFontInsteadOfCollapsingOrProducingNaN() {
    let font = NSFont.monospacedSystemFont(ofSize: 18, weight: .medium)
    for width: CGFloat in [0, -1, .nan, .infinity] {
      XCTAssertEqual(PromptViewportLayout.height(in: AttributedString("probe"), width: width,
        font: font, lineSpacing: 12, lineCount: 2),
        PromptViewportLayout.fallbackHeight(font: font, lineSpacing: 12, lineCount: 2))
    }
  }

  func testNativeRowsUseTheSameHintFontAndRTLParagraphAsTheCaret() {
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)
    for (body, rtl, spacing) in [("مرحبا عالم ", true, CGFloat(8)), ("漢字 e\u{301} 🧑🏽‍💻 ↵\n", false, CGFloat(12))] {
      var text = AttributedString(String(repeating: body, count: 20))
      var hint = AttributedString("hint")
      hint.font = .system(size: 9)
      text += hint
      let height = PromptViewportLayout.height(in: text, width: 180, font: font,
        lineSpacing: spacing, isRightToLeft: rtl, lineCount: 3)
      XCTAssertTrue(height.isFinite)
      XCTAssertGreaterThan(height, 0)
      let storage = PromptCaretLayout.preparedStorage(in: text, font: font,
        lineSpacing: spacing, isRightToLeft: rtl)
      let paragraph = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
      XCTAssertEqual(paragraph?.lineSpacing, spacing)
      XCTAssertEqual(paragraph?.baseWritingDirection, rtl ? .rightToLeft : .leftToRight)
      let hintFont = storage.attribute(.font, at: storage.length - 1, effectiveRange: nil) as? NSFont
      XCTAssertEqual(hintFont?.pointSize ?? 0, max(9, font.pointSize * 0.48), accuracy: 0.01)
    }
  }

  func testCompletePinnedHeightFunctionMatchesNativeRowReduction() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    struct Fixture: Decodable { let rows: [Double], lineCount: Int, height: Double }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", project.appendingPathComponent("Scripts/check-source-line-display.mjs").path,
      reference, "--emit-height-fixtures"]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 14)
    for fixture in fixtures {
      let height = try XCTUnwrap(PromptViewportLayout.height(
        forRowHeights: fixture.rows.map { CGFloat($0) }, lineCount: fixture.lineCount))
      XCTAssertEqual(height, fixture.height, accuracy: 1)
    }
  }
}
