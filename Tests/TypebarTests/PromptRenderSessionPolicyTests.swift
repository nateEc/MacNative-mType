import XCTest
@testable import Typebar

final class PromptRenderSessionPolicyTests: XCTestCase {
  func testCandidateSessionControlsHighlightAndCaretWithoutReadingPlaceholder() {
    let placeholder = TypingSession(configuration: .words(2), prompt: "alpha beta")
    let candidate = TypingSession(configuration: .words(2).with(modifiers: [.aslVisual]), prompt: "alpha beta")
    let placeholderPolicy = PromptRenderSessionPolicy(
      session: placeholder, highlightMode: .word, usesTapePractice: false,
      mainCaretDrawsMarker: false, paceCaretDrawsMarker: false)
    let candidatePolicy = PromptRenderSessionPolicy(
      session: candidate, highlightMode: .word, usesTapePractice: false,
      mainCaretDrawsMarker: false, paceCaretDrawsMarker: false)
    XCTAssertFalse(placeholderPolicy.usesIndependentPromptCarets)
    XCTAssertTrue(candidatePolicy.usesIndependentPromptCarets)
    XCTAssertEqual(candidatePolicy.highlightMode, .word)

    let hiddenCandidate = TypingSession(configuration: .words(2).with(modifiers: [.arrowStream]),
      prompt: "alpha beta")
    let hiddenPolicy = PromptRenderSessionPolicy(
      session: hiddenCandidate, highlightMode: .nextWord, usesTapePractice: false,
      mainCaretDrawsMarker: true, paceCaretDrawsMarker: false)
    XCTAssertEqual(hiddenPolicy.highlightMode, .letter)
  }

  func testPaceIndexComesFromCandidateAndIsSuppressedForIndependentCaret() {
    let candidate = TypingSession(configuration: .words(2), prompt: "alpha beta")
    let ordinary = PromptRenderSessionPolicy(
      session: candidate, highlightMode: .off, usesTapePractice: false,
      mainCaretDrawsMarker: false, paceCaretDrawsMarker: false)
    XCTAssertEqual(ordinary.paceGuideIndex, candidate.paceCaretFrame().flatMap {
      candidate.paceCaretGlyphIndex(for: $0.target)
    })
    let tape = PromptRenderSessionPolicy(
      session: candidate, highlightMode: .off, usesTapePractice: true,
      mainCaretDrawsMarker: false, paceCaretDrawsMarker: true)
    XCTAssertTrue(tape.usesIndependentPromptCarets)
    XCTAssertNil(tape.paceGuideIndex)
  }
}
