import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class TapeControlProjectionTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 913_100_000)
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)

  private func render(_ session: TypingSession) -> PromptRendering {
    let glyphs = session.promptGlyphs, words = session.promptWordPresentations
    let placeholder = session.zenEmptyWordPlaceholderGlyphIndex
    return .make(glyphs: glyphs, indices: PromptGlyphLayout.indices(glyphs: glyphs,
      words: words, hideExtraLetters: session.configuration.rules.hideExtraLetters), emptyWordPlaceholderGlyphID: placeholder,
      words: words, removedTapeWordIndices: session.removedTapePromptWordIndices) { index, glyph in
      let plan = PromptControlCharacterPresentation.plan(for: glyph, style: .off,
        isZen: session.configuration.mode == .zen,
        isExtra: session.configuration.mode != .zen && index >= session.prompt.count,
        isEmptyWordPlaceholder: index == placeholder)
      var value = AttributedString(plan.text)
      value.foregroundColor = Color.gray.opacity(plan.opacity)
      return value
    }
  }

  private func layout(_ session: TypingSession, rtl: Bool = false)
    -> (PromptRendering, [TapePromptWord], TapeNewlineTextLayout) {
    let rendering = render(session), words = TapePromptProjection.words(session: session, rendering: rendering)
    let layout = TapeNewlineTextLayout()
    layout.configure(text: rendering.text, words: words, font: font, rightToLeft: rtl, resets: true)
    return (rendering, words, layout)
  }

  private func zen(_ input: String) -> TypingSession {
    var session = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "")
    session.insertBatch(input, at: start)
    return session
  }

  func testRealZenEmptyActiveWordOwnsPlaceholderWithoutPhantomFutureWord() throws {
    for input in ["", "a ", "a\n"] {
      let session = zen(input), (rendering, words, native) = layout(session)
      let id = try XCTUnwrap(session.zenEmptyWordPlaceholderGlyphIndex)
      let offset = try XCTUnwrap(rendering.characterOffset(forGlyphAt: id))
      let rect = try XCTUnwrap(native.glyphRect(at: offset, minimumOffset: offset), input)
      XCTAssertGreaterThan(rect.width, 0); XCTAssertGreaterThan(rect.height, 0)
      XCTAssertNotNil(native.wordRect(at: offset))
      XCTAssertEqual(words.count, session.promptWordPresentations.filter { $0.phase != .future }.count)
      XCTAssertEqual(session.typed, input); XCTAssertEqual(session.prompt, "")
    }
  }

  func testOrdinaryEmptyWordRetainsItsIdentityAndGapRatherThanBecomingAZenSentinel() {
    let session = TypingSession(configuration: .words(3), prompt: "a  b")
    let (_, words, native) = layout(session)
    XCTAssertEqual(session.promptWordPresentations.count, 3)
    XCTAssertEqual(words.map(\.index), [0, 1, 2])
    XCTAssertEqual(native.wordMetrics.map(\.index), [0, 1, 2])
    XCTAssertTrue(words[1].characters.isEmpty)
    XCTAssertGreaterThan(native.wordMetrics[1].gap, 0)
  }

  func testHiddenRetainedExtraReturnCannotReplaceTheCanonicalNewlineOwner() throws {
    var session = TypingSession(configuration: .words(4,
      rules: .init(strictSpace: true, hideExtraLetters: true)), prompt: "\n\n\nx")
    session.insertBatch("\n\n", at: start)
    let extras = session.promptWordPresentations.flatMap(\.extraGlyphIndices)
    XCTAssertTrue(extras.contains { session.promptGlyphs[$0].character == "\n"
      && session.promptGlyphs[$0].state == .hidden }, "Exercise hidden extra identity, not just an ordinary Return")
    let (rendering, words, native) = layout(session)
    for word in words where word.ownsNewline {
      let canonical = session.promptWordPresentations[word.index].range.upperBound
      let offset = try XCTUnwrap(rendering.characterOffset(forGlyphAt: canonical),
        "word=\(word.index), canonical=\(canonical), prompt=\(String(reflecting: session.prompt)), extras=\(extras), offsets=\(rendering.glyphCharacterOffsets), words=\(session.promptWordPresentations)")
      XCTAssertEqual(word.newlineCharacterOffset, offset)
      XCTAssertGreaterThan(try XCTUnwrap(native.wordMetrics.first { $0.index == word.index }?.newlineWidth), 0)
      XCTAssertTrue(word.controlCharacterOffsets.keys.allSatisfy { !extras.compactMap {
        rendering.characterOffset(forGlyphAt: $0) }.contains($0) })
    }
    XCTAssertEqual(session.typed, "\n\n")
  }

  func testRealZenConsecutiveReturnsHavePositiveHiddenCellsAndOneRowEach() throws {
    for rtl in [false, true] {
      let session = zen("\n\na"), (rendering, words, native) = layout(session, rtl: rtl)
      XCTAssertEqual(String(rendering.text.characters), "\n\na ", "Layout must not rewrite shared text or input")
      XCTAssertEqual(words.filter(\.ownsNewline).count, 2)
      let first = try XCTUnwrap(native.glyphRect(at: 0, minimumOffset: 0))
      let second = try XCTUnwrap(native.glyphRect(at: 1, minimumOffset: 1))
      let third = try XCTUnwrap(native.glyphRect(at: 2, minimumOffset: 2))
      XCTAssertGreaterThan(first.width, 0); XCTAssertGreaterThan(second.width, 0)
      XCTAssertEqual(second.minY - first.minY, native.metrics.rowHeight, accuracy: 0.01)
      XCTAssertEqual(third.minY - second.minY, native.metrics.rowHeight, accuracy: 0.01)
      XCTAssertEqual(native.metrics.contentHeight, native.metrics.rowHeight * 3)
      XCTAssertGreaterThan(try XCTUnwrap(native.wordMetrics[0].newlineWidth), 0)
      XCTAssertEqual(rendering.text.runs.first?.foregroundColor, Color.gray.opacity(0))
    }
  }

  func testRealZenTabUsesOneHiddenArrowAdvanceNotATabStop() throws {
    let (_, _, native) = layout(zen("a\tb"))
    let tab = try XCTUnwrap(native.glyphRect(at: 1, minimumOffset: 1))
    let expected = ("→" as NSString).size(withAttributes: [.font: font]).width
    XCTAssertEqual(tab.width, expected, accuracy: 0.01)
    XCTAssertEqual(try XCTUnwrap(native.glyphRect(at: 2, minimumOffset: 2)).minX,
      tab.maxX, accuracy: 0.01)
  }

  func testNoSpaceInternalReturnsBelongToTheirWordAndCreateOnlyOneStructuralRow() throws {
    let session = TypingSession(configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces]), prompt: "a\n\nbc",
      noSpaceWordEndIndices: [3, 5], noSpaceTargetWords: ["a\n\n", "bc"])
    let (rendering, words, native) = layout(session)
    XCTAssertEqual(words.count, 2)
    XCTAssertTrue(words[0].ownsNewline); XCTAssertFalse(words[1].ownsNewline)
    XCTAssertEqual(words[0].newlineCharacterOffset, rendering.characterOffset(forGlyphAt: 1))
    XCTAssertEqual(native.metrics.contentHeight, native.metrics.rowHeight * 2)
    let next = try XCTUnwrap(rendering.characterOffset(forGlyphAt: 3))
    XCTAssertEqual(try XCTUnwrap(native.glyphRect(at: next, minimumOffset: next)).minY,
      native.metrics.rowHeight, accuracy: 0.01)
  }

  func testNoSpaceBoundaryCannotGiveNextWordsLeadingReturnToPreviousWord() {
    let session = TypingSession(configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces]), prompt: "a\nbc",
      noSpaceWordEndIndices: [1, 3, 4], noSpaceTargetWords: ["a", "\nb", "c"])
    let (_, words, native) = layout(session)
    XCTAssertFalse(words[0].ownsNewline); XCTAssertTrue(words[1].ownsNewline)
    XCTAssertFalse(words[0].characters.overlaps(words[1].characters))
    XCTAssertEqual(native.metrics.contentHeight, native.metrics.rowHeight * 2)
  }

  func testRemovedInternalReturnWordKeepsOneStructuralRowAndNoCanonicalInk() throws {
    var session = TypingSession(configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(freedomMode: true), modifiers: [.noSpaces]), prompt: "ba\n\ncd",
      noSpaceWordEndIndices: [1, 4, 6], noSpaceTargetWords: ["b", "a\n\n", "cd"])
    session.removeTapePromptWords(.init(attemptID: session.automaticInputAttemptID, wordIndices: [1]))
    XCTAssertEqual(session.removedTapePromptWordIndices, [1])
    let (rendering, words, native) = layout(session)
    XCTAssertTrue(words[1].ownsNewline); XCTAssertTrue(words[1].characters.isEmpty)
    XCTAssertNil(words[1].newlineCharacterOffset)
    for id in 1..<4 { XCTAssertNil(rendering.characterOffset(forGlyphAt: id)) }
    XCTAssertEqual(native.metrics.contentHeight, native.metrics.rowHeight * 2)
    XCTAssertEqual(session.prompt, "ba\n\ncd"); XCTAssertEqual(session.typed, "")
  }

  func testHiddenControlCellsReserveGeometryWithoutDrawingInk() throws {
    func bitmap(_ text: AttributedString?) throws -> Data {
      let native = TapeNewlineTextLayout()
      if let text {
        native.configure(text: text, words: [.init(index: 0, glyphID: 0, characters: 0..<2,
          newlineCharacterOffset: 1, controlCharacterOffsets: [0: "\t", 1: "\n"])],
          font: font, rightToLeft: false, resets: true)
        XCTAssertGreaterThan(try XCTUnwrap(native.glyphRect(at: 0, minimumOffset: 0)).width, 0)
        XCTAssertGreaterThan(try XCTUnwrap(native.glyphRect(at: 1, minimumOffset: 1)).width, 0)
      }
      let image = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 180, pixelsHigh: 70,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
      let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: image))
      NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
      NSGraphicsContext.current = context
      NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 180, height: 70).fill()
      native.draw(in: .init(x: 0, y: 0, width: 180, height: 70))
      return try XCTUnwrap(image.representation(using: .png, properties: [:]))
    }
    var hidden = AttributedString("\t\n"); hidden.foregroundColor = Color.gray.opacity(0)
    var visible = AttributedString("\t\n"); visible.foregroundColor = .black
    let blank = try bitmap(nil), hiddenImage = try bitmap(hidden), visibleImage = try bitmap(visible)
    XCTAssertEqual(hiddenImage, blank, "Normalized Zen controls must remain completely invisible")
    XCTAssertNotEqual(visibleImage, blank, "Positive control boxes must actually contain drawable markers")
    if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
      for (name, data) in [("blank", blank), ("hidden", hiddenImage), ("visible", visibleImage)] {
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("tape-controls-\(name).png"))
      }
    }
  }

  func testCanonicalControlMetadataDoesNotReplaceCompositionOrMapStructuralBreak() throws {
    var text = AttributedString("候 🙂\n"); text.foregroundColor = .purple; text.underlineStyle = .single
    let native = TapeNewlineTextLayout()
    native.configure(text: text, words: [.init(index: 0, glyphID: 0, characters: 0..<4,
      newlineCharacterOffset: 0, controlCharacterOffsets: [0: "\n"])], font: font,
      rightToLeft: false, resets: true)
    for offset in 0..<3 { XCTAssertNotNil(native.glyphRect(at: offset, minimumOffset: offset)) }
    XCTAssertNil(native.glyphRect(at: 3, minimumOffset: 3), "Only the canonical raw LF can become a marker")
    let expected = ("候 🙂" as NSString).size(withAttributes: [.font: font]).width
    XCTAssertEqual(try XCTUnwrap(native.wordRect(at: 0)).width, expected, accuracy: 0.01)
  }
}
