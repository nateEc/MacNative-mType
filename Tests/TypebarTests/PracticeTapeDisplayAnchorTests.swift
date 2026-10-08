import AppKit
import SwiftUI
import XCTest
@testable import Typebar

final class PracticeTapeDisplayAnchorTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  func testHiddenExtraLettersDoNotMoveTheTapePastTheVisibleCursor() {
    var session = TypingSession(configuration: .words(3, rules: .init(hideExtraLetters: true)),
      prompt: "abc bay cedar")
    session.insertBatch("abcxy", at: start)
    XCTAssertEqual(anchor(session, .letter), 3)
    XCTAssertEqual(anchor(session, .word), 0)
    XCTAssertEqual(PracticeTapePolicy.horizontalOffset(
      anchorCharacterIndex: anchor(session, .letter), mode: .letter,
      margin: 0, glyphWidth: 10, containerWidth: 800), 30)
  }

  func testEarlyWordCommitAnchorsAtTheNextTargetWordRatherThanTypedLength() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("a ", at: start)
    XCTAssertEqual(anchor(session, .letter), 4)
    XCTAssertEqual(anchor(session, .word), 4)
    XCTAssertEqual(session.typed.count, 2)
  }

  func testBlindToggleChangesOnlyTheRenderedExtraWidthInBothTapeModes() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("abcxy", at: start)
    XCTAssertEqual(anchor(session, .letter), 5)
    session.setBlindMode(true)
    XCTAssertEqual(anchor(session, .letter), 3)
    session.insertBatch(" ", at: start)
    XCTAssertEqual(anchor(session, .word), 4)
    XCTAssertEqual(anchor(session, .letter), 4)
    session.setBlindMode(false)
    XCTAssertEqual(anchor(session, .word), 6)
    XCTAssertEqual(anchor(session, .letter), 6)
  }

  func testOffAndNoInputStayAtTheStartAndZenKeepsEnteredWordBoundaries() {
    let empty = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    XCTAssertEqual(anchor(empty, .letter), 0)
    XCTAssertEqual(anchor(empty, .word), 0)
    var zen = TypingSession(configuration: .init(mode: .zen, duration: nil,
      wordLimit: nil, difficulty: .normal, rules: .init()), prompt: "")
    zen.insertBatch("🙂 abc", at: start)
    XCTAssertEqual(anchor(zen, .letter), 5)
    XCTAssertEqual(anchor(zen, .word), 2)
    XCTAssertEqual(anchor(zen, .off), 0)
  }

  @MainActor func testNativeTapeOffsetMeasuresTheSelectedFontInsteadOfAFixedGlyphWidth() throws {
    for font in [NSFont.monospacedSystemFont(ofSize: 18, weight: .regular),
                 NSFont.systemFont(ofSize: 28)] {
      let text = AttributedString("WWW iii bay")
      let expected = try XCTUnwrap(PromptCaretLayout.rect(
        in: text, characterOffset: 4, containerSize: .init(width: 10_000, height: 200),
        font: font, lineSpacing: 0))
      XCTAssertEqual(PracticeTapePolicy.horizontalOffset(
        prompt: text, anchorCharacterIndex: 4, mode: .letter, margin: 0, font: font,
        containerWidth: 800), expected.minX, accuracy: 0.001)
      XCTAssertNotEqual(expected.minX, 4 * font.pointSize * 0.62)
    }
  }

  @MainActor func testNativeTapeOffsetKeepsExplicitHintMetricsAndMarginClamping() throws {
    var text = AttributedString("a")
    var hint = AttributedString("x")
    hint.font = .system(size: 9, weight: .semibold, design: .monospaced)
    hint.baselineOffset = -7.56
    hint.kern = -11.16
    text += hint
    text += AttributedString("bcx bay")
    let font = NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)
    let rect = try XCTUnwrap(PromptCaretLayout.rect(
      in: text, characterOffset: 5, containerSize: .init(width: 10_000, height: 200),
      font: font, lineSpacing: 0))
    XCTAssertEqual(PracticeTapePolicy.horizontalOffset(
      prompt: text, anchorCharacterIndex: 5, mode: .letter, margin: 0.1, font: font,
      containerWidth: 100), rect.minX - 10, accuracy: 0.001)
    XCTAssertEqual(PracticeTapePolicy.horizontalOffset(
      prompt: text, anchorCharacterIndex: 5, mode: .letter, margin: 2, font: font,
      containerWidth: 800), rect.minX - 800, accuracy: 0.001)
    XCTAssertEqual(PracticeTapePolicy.horizontalOffset(
      prompt: text, anchorCharacterIndex: 5, mode: .off, margin: 0, font: font,
      containerWidth: 800), 0)
    XCTAssertEqual(PracticeTapePolicy.horizontalOffset(
      prompt: text, anchorCharacterIndex: 100, mode: .letter, margin: 0, font: font,
      containerWidth: 800), 0)
  }

  private func anchor(_ session: TypingSession, _ mode: PracticeTapeMode) -> Int {
    let glyphs = session.promptGlyphs
    let rendering = PromptRendering.make(glyphs: glyphs, indices: PromptGlyphLayout.indices(
      glyphs: glyphs, words: session.promptWordPresentations,
      hideExtraLetters: session.configuration.rules.hideExtraLetters)) { _, glyph in
        AttributedString(PromptControlCharacterPresentation.text(for: glyph.character, state: glyph.state))
      }
    return PracticeTapePolicy.anchorCharacterIndex(session: session, rendering: rendering, mode: mode)
  }
}
