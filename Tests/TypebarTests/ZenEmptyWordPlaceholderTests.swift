import SwiftUI
import XCTest
@testable import Typebar

final class ZenEmptyWordPlaceholderTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 400)
  private func session() -> TypingSession {
    .init(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(freedomMode: true)), prompt: "")
  }

  func testRealSessionPlaceholderFollowsOnlyEmptyActiveFieldsAndSurvivesDeletion() {
    var input = session()
    XCTAssertEqual(input.zenEmptyWordPlaceholderGlyphIndex, 0)
    for (text, expected) in [("a", nil), (" ", 2), ("候", nil), ("\n", 4), ("\t", nil)] as [(String, Int?)] {
      input.insertBatch(text, at: start)
      XCTAssertEqual(input.zenEmptyWordPlaceholderGlyphIndex, expected)
    }
    input.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "a 候\n"); XCTAssertEqual(input.zenEmptyWordPlaceholderGlyphIndex, 4)
    input.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertNil(input.zenEmptyWordPlaceholderGlyphIndex)
    XCTAssertEqual(input.typed, "a 候"); XCTAssertEqual(input.prompt, "")
  }

  func testPlaceholderIsNotEnteredInputAndDoesNotLeakToFinishedResultOrRepeat() throws {
    var input = session(); input.insertBatch("a\n", at: start)
    XCTAssertEqual(input.zenEmptyWordPlaceholderGlyphIndex, 2)
    XCTAssertEqual(input.promptGlyphs.last?.character, " ")
    XCTAssertEqual(input.promptGlyphs.last?.state, .current)
    input.finishZen(at: start.addingTimeInterval(15))
    XCTAssertNil(input.zenEmptyWordPlaceholderGlyphIndex)
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(input.typed, "a\n"); XCTAssertEqual(result.prompt, "")
    XCTAssertFalse(result.replayEvents.contains { $0.text.contains("_") })
    XCTAssertEqual(input.repeatedAttempt().zenEmptyWordPlaceholderGlyphIndex, 0)
    XCTAssertNil(TypingSession(configuration: .words(2), prompt: " a").zenEmptyWordPlaceholderGlyphIndex)
  }

  func testOnlyTheExplicitZenCurrentSpaceBecomesAnInvisibleUnderscore() {
    let glyph = TypingPromptGlyph(character: " ", state: .current)
    for style in TypoIndicatorStyle.allCases {
      XCTAssertEqual(PromptControlCharacterPresentation.plan(for: glyph, style: style,
        isZen: true, isEmptyWordPlaceholder: true), .init(text: "_", hint: nil, opacity: 0))
      XCTAssertEqual(PromptControlCharacterPresentation.plan(for: glyph, style: style,
        isZen: true), .init(text: " ", hint: nil, opacity: 1))
      XCTAssertEqual(PromptControlCharacterPresentation.plan(for: glyph, style: style,
        isEmptyWordPlaceholder: true), .init(text: " ", hint: nil, opacity: 1))
    }
    XCTAssertEqual(PromptControlCharacterPresentation.plan(for: .init(character: " ", state: .correct),
      style: .off, isZen: true, isEmptyWordPlaceholder: true).text, " ")
  }

  func testCompositionReplacementOwnsTheEmptyFieldInsteadOfTheHiddenSentinel() {
    let plan = PromptControlCharacterPresentation.plan(for: .init(character: " ", state: .current),
      style: .both, isZen: true, compositionReplacement: "候🙂", isEmptyWordPlaceholder: true)
    XCTAssertEqual(plan, .init(text: "候🙂", hint: nil, opacity: 1))
  }

  func testPrunedPlaceholderCannotRestoreAWordOrRetainRenderingMetadata() {
    let glyphs = [TypingPromptGlyph(character: " ", state: .current)]
    let rendering = PromptRendering.make(glyphs: glyphs, indices: [], emptyWordPlaceholderGlyphID: 0) { _, _ in
      XCTFail("Pruned cells must not render"); return AttributedString("_")
    }
    XCTAssertNil(rendering.emptyWordPlaceholderGlyphID); XCTAssertTrue(rendering.text.characters.isEmpty)
    let words = [TypingPromptWordPresentation(range: 0..<0, phase: .active, hasInputError: false, hasCommitError: false)]
    let plan = ASLPromptWordPlan(glyphs: glyphs, ids: [0], words: words, placeholderGlyphID: 0)
    XCTAssertTrue(plan.measuredWords(frames: [:], glyphs: glyphs, ids: [0]).isEmpty)
    let frame = CGRect(x: 0, y: 0, width: 15, height: 30)
    XCTAssertEqual(plan.measuredWords(frames: [0: frame], glyphs: glyphs, ids: [0]), [0: frame])
    XCTAssertTrue(ASLPromptWordPlan(glyphs: glyphs, ids: [0], words: words)
      .measuredWords(frames: [0: frame], glyphs: glyphs, ids: [0]).isEmpty,
      "Ordinary target separators must not become placeholder ink")
  }
}
