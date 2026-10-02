import AppKit
import SwiftUI
import XCTest
@testable import Typebar

final class StoppedInputPresentationTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 907_200_000)

  func testStoppedLetterShowsTypoWithoutAcceptingText() {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .letter)), prompt: "ab cd")
    session.insertBatch("a", at: start)
    session.insertBatch("x", at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.promptGlyphs[1].state, .incorrect)
    XCTAssertEqual(session.promptGlyphs[1].typedCharacter, "x")
    XCTAssertEqual(session.typed, "a")
    XCTAssertEqual(session.nextExpectedCharacter, "b")
    XCTAssertEqual(session.promptCaretGlyphIndex, 1)
    XCTAssertTrue(session.promptWordPresentations[0].hasInputError)
    session.bailOut(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.result()?.replayEvents.last?.inputStopped, true)
    XCTAssertEqual(TypingReplay.typedText(events: session.result()?.replayEvents ?? [], through: 1), "a")
  }

  private func stopped(_ prefix: String = "a") -> TypingSession {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .letter)), prompt: "ab cd")
    session.insertBatch(prefix, at: start)
    session.insertBatch("x", at: start.addingTimeInterval(0.2))
    return session
  }

  private func render(_ session: TypingSession) -> PromptRendering {
    let glyphs = session.promptGlyphs
    let indices = PromptGlyphLayout.indices(glyphs: glyphs, words: session.promptWordPresentations,
      hideExtraLetters: session.configuration.rules.hideExtraLetters)
    return PromptRendering.make(glyphs: glyphs, indices: indices) { _, glyph in
      AttributedString(String(glyph.character))
    }
  }

  func testNextCorrectInputClearsTheTransientError() {
    var session = stopped()
    session.insertBatch("b", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.promptGlyphs[1].state, .correct)
    XCTAssertNil(session.promptGlyphs[1].typedCharacter)
    XCTAssertFalse(session.promptWordPresentations[0].hasInputError)
    XCTAssertEqual(session.promptCaretGlyphIndex, 2)
  }

  func testConsecutiveStoppedKeysReplaceRatherThanAccumulate() {
    var session = stopped()
    session.insertBatch("y", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.promptGlyphs[1].typedCharacter, "y")
    XCTAssertEqual(session.promptGlyphs.count, session.prompt.count)
    XCTAssertEqual(session.typed, "a")
  }

  func testDeleteRemovesRealTextAndClearsOnlyTheDisplayOverride() {
    for wholeWord in [false, true] {
      var session = stopped()
      XCTAssertEqual(TypingLiveInputFeedback.delete(from: &session, wholeWord: wholeWord,
        at: start.addingTimeInterval(1)), [true])
      XCTAssertEqual(session.typed, "")
      XCTAssertEqual(session.promptGlyphs[0].state, .current)
      XCTAssertNil(session.promptGlyphs[1].typedCharacter)
    }
  }

  func testPreventedFirstWordDeleteAndPreRejectedInputPreserveTheOverride() {
    var session = stopped("")
    XCTAssertEqual(session.promptGlyphs[0].typedCharacter, "x")
    XCTAssertEqual(TypingLiveInputFeedback.delete(from: &session, wholeWord: false, at: start), [])
    XCTAssertEqual(session.insertBatch("\n", at: start), [])
    XCTAssertEqual(session.promptGlyphs[0].typedCharacter, "x")
    XCTAssertEqual(session.typed, "")
  }

  func testOnlyTheFinalBatchCallbackPublishesAStoppedGlyph() {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .letter)), prompt: "ab cd")
    session.insertBatch("xa", at: start)
    XCTAssertEqual(session.typed, "a")
    XCTAssertNil(session.promptGlyphs[0].typedCharacter)
    XCTAssertEqual(session.promptGlyphs[1].state, .current)
    session.insertBatch("xy", at: start)
    XCTAssertEqual(session.promptGlyphs[1].typedCharacter, "y")
  }

  func testOppositeShiftRedrawClearsPriorOverrideWithoutDisplayingTheRejectedKey() {
    var session = stopped()
    var rules = session.configuration.rules
    rules.oppositeShiftMode = .on
    session.synchronizeLiveInputRules(rules)
    XCTAssertEqual(session.insertBatch("b", forceError: true, at: start), [false])
    XCTAssertEqual(session.typed, "a")
    XCTAssertEqual(session.promptGlyphs[1].state, .current)
    XCTAssertNil(session.promptGlyphs[1].typedCharacter)
  }

  func testBlindStoppedInputNeverCreatesAHiddenErrorForLaterUnblinding() {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .letter, blindMode: true)), prompt: "ab cd")
    session.insertBatch("x", at: start)
    session.setBlindMode(false)
    XCTAssertEqual(session.promptGlyphs[0].state, .current)
    XCTAssertNil(session.promptGlyphs[0].typedCharacter)
    XCTAssertFalse(session.promptWordPresentations[0].hasInputError)
  }

  func testCompositionStartKeepsOverrideButCandidateRedrawClearsItWithoutScoring() {
    var session = stopped()
    session.beginComposition(at: start)
    XCTAssertEqual(session.promptGlyphs[1].typedCharacter, "x")
    session.refreshLiveAccuracyAfterComposition(hadMarkedText: false, hasMarkedText: true)
    XCTAssertEqual(session.promptGlyphs[1].state, .current)
    XCTAssertNil(session.promptGlyphs[1].typedCharacter)
    XCTAssertEqual(session.typed, "a")
    session.bailOut(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.result()?.inputMetrics?.totalAttempts, 2)
  }

  func testClockDoesNotExpireTheOverrideButHighlightRedrawDoes() {
    var session = stopped()
    session.tick(at: start.addingTimeInterval(30))
    XCTAssertEqual(session.promptGlyphs[1].typedCharacter, "x")
    session.refreshPromptPresentation()
    XCTAssertEqual(session.promptGlyphs[1].state, .current)
    XCTAssertNil(session.promptGlyphs[1].typedCharacter)
  }

  func testTransientExtraBelongsBeforeItsWordSeparatorWithUnadvancedCaret() {
    let session = stopped("ab")
    XCTAssertEqual(session.typed, "ab")
    XCTAssertEqual(String(render(session).text.characters), "abx cd")
    XCTAssertEqual(session.promptGlyphs.last?.state, .extra)
    XCTAssertEqual(session.promptWordPresentations[0].extraGlyphIndices, [5])
    XCTAssertEqual(session.promptCaretGlyphIndex, 5)
    XCTAssertEqual(render(session).characterOffset(forGlyphAt: session.promptCaretGlyphIndex), 2)
    XCTAssertEqual(PracticeTapePolicy.anchorCharacterIndex(session: session,
      rendering: render(session), mode: .letter), 2)
    XCTAssertEqual(session.nextExpectedCharacter, " ")
  }

  func testHideExtraLettersDoesNotReserveTransientLayoutSpace() {
    var session = stopped("ab")
    session.setHideExtraLetters(true)
    XCTAssertEqual(String(render(session).text.characters), "ab cd")
    XCTAssertEqual(session.promptGlyphs.last?.state, .hidden)
    XCTAssertEqual(session.promptCaretGlyphIndex, 2)
    session.setHideExtraLetters(false)
    XCTAssertEqual(String(render(session).text.characters), "abx cd")
    XCTAssertEqual(session.typed, "ab")
  }

  func testEmptyNoSpaceWordOwnsTheTransientExtraAndNotTheLaterTarget() {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .letter)).with(modifiers: [.noSpaces]), prompt: "ab",
      noSpaceWordEndIndices: [0, 2], noSpaceTargetWords: ["", "ab"])
    session.insertBatch("x", at: start)
    XCTAssertEqual(session.promptGlyphs[0].state, .pending)
    XCTAssertEqual(session.promptGlyphs.last?.character, "x")
    XCTAssertEqual(session.promptWordPresentations[0].extraGlyphIndices, [2])
    XCTAssertEqual(String(render(session).text.characters), "xab")
    XCTAssertEqual(session.typed, "")
    XCTAssertNil(session.nextExpectedCharacter)
  }

  func testMemoryDoesNotRevealTheStoppedLetter() {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .letter)).with(modifiers: [.memory]), prompt: "ab cd")
    session.insertBatch("x", at: start)
    XCTAssertEqual(session.promptGlyphs[0].state, .hidden)
    let appearance = PromptGlyphAppearance.plan(glyphs: session.promptGlyphs,
      words: session.promptWordPresentations, mode: .letter, blindMode: false, typedEffect: .keep)
    XCTAssertEqual(appearance[0].color, .hidden)
  }

  func testWordHighlightShowsAnInputErrorButNotACommittedBorder() {
    let session = stopped()
    let appearance = PromptGlyphAppearance.plan(glyphs: session.promptGlyphs,
      words: session.promptWordPresentations, mode: .word, blindMode: false, typedEffect: .keep)
    XCTAssertEqual(appearance[0].color, .error)
    XCTAssertFalse(session.promptWordPresentations[0].hasCommitError)
  }

  @MainActor func testNativeCaretGeometryStaysAtTheRejectedLetter() throws {
    let session = stopped()
    let rendering = render(session)
    let offset = try XCTUnwrap(rendering.characterOffset(forGlyphAt: session.promptCaretGlyphIndex))
    let font = NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)
    let size = CGSize(width: 800, height: 200)
    let actual = try XCTUnwrap(PromptCaretLayout.rect(in: rendering.text, characterOffset: offset,
      containerSize: size, font: font, lineSpacing: 12))
    let expected = try XCTUnwrap(PromptCaretLayout.rect(in: AttributedString("ab cd"), characterOffset: 1,
      containerSize: size, font: font, lineSpacing: 12))
    XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.001)
    XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.001)
  }
}
