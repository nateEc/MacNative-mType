import AppKit
import XCTest
@testable import Typebar

@MainActor final class TapeNewlineProjectionTests: XCTestCase {
  private final class Canvas: NSView {
    let native: TapeNewlineTextLayout
    init(_ native: TapeNewlineTextLayout) { self.native = native; super.init(frame: .init(x: 0, y: 0, width: 400, height: 120)) }
    required init?(coder: NSCoder) { fatalError("test-only canvas") }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { NSColor.white.setFill(); dirtyRect.fill(); native.draw(in: dirtyRect) }
  }
  func testVirtualSlotsUseFieldIdentityInsidePersistentNewlineFlow() throws {
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    var session = TypingSession(configuration: .words(3), prompt: "a\nbc tail")
    session.insertBatch("a\nb", at: Date(timeIntervalSinceReferenceDate: 917_100_000))
    let presentation = try XCTUnwrap(PromptCompositionPresentation(session: session,
      composition: "XYZ😀", style: .replace))
    let rendering = presentation.render { _, glyph, cell in AttributedString(cell?.text ?? String(glyph.character)) }
    let map = try XCTUnwrap(rendering.compositionTextMap)
    let descriptors = TapePromptProjection.words(session: session, rendering: rendering)
    let field = try XCTUnwrap(session.promptCompositionField)
    let cells = map.fieldRuns.filter { $0.fieldID == field.index }.flatMap(\.cells).filter { !$0.isGap }
    XCTAssertTrue(cells.contains { $0.id < 0 })
    for rtl in [false, true] {
      let native = TapeNewlineTextLayout()
      native.configure(text: rendering.text, words: descriptors, font: font,
        rightToLeft: rtl, resets: true, compositionMap: map)
      let frame = try XCTUnwrap(native.projectedFieldRect(field.index))
      for cell in cells {
        let rect = try XCTUnwrap(native.projectedCellRect(cell.id))
        XCTAssertEqual(rect.minY, frame.minY, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(rect.minX, frame.minX - 0.001)
        XCTAssertLessThanOrEqual(rect.maxX, frame.maxX + 0.001)
      }
      XCTAssertEqual(frame.minY, native.metrics.rowHeight, accuracy: 0.001)
      let wordPass = try XCTUnwrap(native.requestProjectedScroll(fieldID: field.index,
        acceptedUTF16Count: 0, mode: .word, hidesExtras: false, viewportWidth: 400,
        duration: 0, time: 0, overflowing: { _, _ in false }))
      let letterPass = try XCTUnwrap(native.requestProjectedScroll(fieldID: field.index,
        acceptedUTF16Count: 1, mode: .letter, hidesExtras: false, viewportWidth: 400,
        duration: 0, time: 0, overflowing: { _, _ in false }))
      XCTAssertEqual(letterPass.advance - wordPass.advance,
        try XCTUnwrap(native.projectedCellRect(cells[0].id)).width, accuracy: 0.001)
      XCTAssertNil(native.projectedCellRect(Int.min))
      XCTAssertNil(native.projectedFieldRect(Int.min))
      let activeIDs = Set(cells.map(\.id))
      for (canonical, aliases) in map.canonicalAliases where aliases.allSatisfy({ activeIDs.contains($0) }) && !aliases.isEmpty {
        XCTAssertEqual(native.projectedCanonicalRect(canonical, after: false), native.projectedCellRect(aliases[0]))
        XCTAssertEqual(native.projectedCanonicalRect(canonical, after: true), native.projectedCellRect(aliases[aliases.count - 1]))
      }
      XCTAssertEqual(session.typed, "a\nb")
      let canvas = Canvas(native)
      let window = NSWindow(contentRect: canvas.frame, styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentView = canvas
      defer { window.contentView = nil; window.close() }
      let bitmap = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
      canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
      let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      XCTAssertGreaterThan(png.count, 500)
      if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("tape-multiline-projection-\(rtl ? "rtl" : "ltr").png"))
      }
      XCTAssertFalse(window.isVisible)
    }
  }

  func testProjectionRebuildDoesNotResurrectHorizontallyRemovedReturnWord() throws {
    var session = TypingSession(configuration: .words(3), prompt: "a\nbc tail")
    session.insertBatch("a\nb", at: Date(timeIntervalSinceReferenceDate: 917_100_000))
    let native = TapeNewlineTextLayout()
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    let active = try XCTUnwrap(session.promptCompositionField).index
    for (iteration, marked) in ["XYZ", "候选😀", ""].enumerated() {
      let presentation = try XCTUnwrap(PromptCompositionPresentation(session: session, composition: marked, style: .replace))
      let rendering = presentation.render { _, glyph, cell in AttributedString(cell?.text ?? String(glyph.character)) }
      native.configure(text: rendering.text, words: TapePromptProjection.words(session: session, rendering: rendering),
        font: font, rightToLeft: false, resets: iteration == 0, compositionMap: rendering.compositionTextMap)
      if iteration == 0 {
        let pass = try XCTUnwrap(native.requestProjectedScroll(fieldID: active, acceptedUTF16Count: 1,
          mode: .letter, hidesExtras: false, viewportWidth: 400, duration: 0, time: 0,
          overflowing: { id, _ in id == 0 }))
        XCTAssertEqual(pass.removedWords, [0])
      }
      XCTAssertNil(native.projectedFieldRect(0))
      XCTAssertEqual(native.removedWordIndices, [0])
      let frame = try XCTUnwrap(native.projectedFieldRect(active))
      XCTAssertEqual(frame.minY, native.metrics.rowHeight, accuracy: 0.001,
        "The removed word's Return topology survives candidate rebuilds")
    }
  }
}
