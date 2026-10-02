import AppKit
import SwiftUI
import XCTest
@testable import Typebar

final class PromptControlGlyphTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 907_200_000)
  func testPendingTabHasAVisibleNativeDirectionMarker() {
    XCTAssertEqual(PromptControlCharacterPresentation.text(for: "\t", state: .pending), "→")
  }

  func testCorrectAndPendingReturnsKeepTheirMarkerAndSourceLineBreak() {
    for state in [TypingPromptCharacterState.correct, .pending] {
      XCTAssertEqual(PromptControlCharacterPresentation.text(for: "\n", state: state), "↵\n")
    }
  }

  func testExtraControlsHaveVisibleMarkersButCannotCreateNewSourceLines() {
    XCTAssertEqual(PromptControlCharacterPresentation.text(for: " ", state: .extra), "_")
    XCTAssertEqual(PromptControlCharacterPresentation.text(for: "\t", state: .extra), "→")
    XCTAssertEqual(PromptControlCharacterPresentation.text(for: "\n", state: .extra), "↵")
  }

  func testOrdinaryTypoUsesEachStyleWithoutChangingTheEnteredCharacter() {
    let glyph = TypingPromptGlyph(character: "b", state: .incorrect, typedCharacter: "x")
    for (style, text, hint) in [
      (TypoIndicatorStyle.off, "b", nil), (.replace, "x", nil),
      (.below, "b", "x"), (.both, "x", "b")
    ] {
      XCTAssertEqual(PromptControlCharacterPresentation.plan(for: glyph, style: style),
        .init(text: text, hint: hint, opacity: 1))
    }
    XCTAssertEqual(glyph.typedCharacter, "x")
  }

  func testStoppedSpaceReplacementIsAnUnderscoreButBelowHintIsWhitespace() {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .letter)), prompt: "ab cd")
    session.insertBatch("a", at: start)
    session.insertBatch(" ", at: start)
    let glyph = session.promptGlyphs[1]
    for (style, text, hint) in [
      (TypoIndicatorStyle.off, "b", nil), (.replace, "_", nil),
      (.below, "b", " "), (.both, "_", "b")
    ] {
      XCTAssertEqual(PromptControlCharacterPresentation.plan(for: glyph, style: style),
        .init(text: text, hint: hint, opacity: 1))
    }
    XCTAssertEqual(session.typed, "a")
    XCTAssertEqual(session.promptCaretGlyphIndex, 1)
    XCTAssertEqual(session.nextExpectedCharacter, "b")
  }

  func testTypedTabAndReturnAreIconsOnlyInReplacementOrExtraBodies() {
    for (entered, marker) in [(Character("\t"), "→"), ("\n", "↵")] {
      let glyph = TypingPromptGlyph(character: "b", state: .incorrect, typedCharacter: entered)
      XCTAssertEqual(PromptControlCharacterPresentation.plan(for: glyph, style: .replace).text, marker)
      XCTAssertEqual(PromptControlCharacterPresentation.plan(for: glyph, style: .both).hint, "b")
      XCTAssertEqual(PromptControlCharacterPresentation.plan(for: glyph, style: .below).text, "b")
      XCTAssertEqual(PromptControlCharacterPresentation.plan(for: glyph, style: .below).hint, " ")
      XCTAssertFalse(PromptControlCharacterPresentation.plan(for: glyph, style: .replace).text.contains("\n"))
    }
  }

  func testReplacingATargetReturnPreservesOnlyItsOwnSourceLineBreak() {
    for entered: Character in ["x", " ", "\t", "\n"] {
      let glyph = TypingPromptGlyph(character: "\n", state: .incorrect, typedCharacter: entered)
      let plan = PromptControlCharacterPresentation.plan(for: glyph, style: .both)
      XCTAssertEqual(plan.text.filter { $0 == "\n" }.count, 1)
      XCTAssertTrue(plan.text.hasSuffix("\n"))
      XCTAssertEqual(plan.hint, " ")
      XCTAssertEqual(plan.opacity, 0.2)
    }
    XCTAssertEqual(PromptControlCharacterPresentation.plan(
      for: .init(character: "\n", state: .incorrect, typedCharacter: "x"), style: .replace).text, "x\n")
  }

  func testTargetTabsHaveNoInvisibleTabStopsEvenWhenMistyped() {
    for state in [TypingPromptCharacterState.pending, .current, .correct, .incorrect, .hidden] {
      let glyph = TypingPromptGlyph(character: "\t", state: state)
      let plan = PromptControlCharacterPresentation.plan(for: glyph, style: .off)
      XCTAssertEqual(plan.text, "→")
      XCTAssertEqual(plan.opacity, 0.2)
      XCTAssertNil(plan.hint)
    }
    XCTAssertEqual(PromptControlCharacterPresentation.plan(
      for: .init(character: "\t", state: .incorrect, typedCharacter: "x"), style: .both),
      .init(text: "x", hint: " ", opacity: 0.2))
  }

  func testExtraMarkersDoNotInheritTargetControlDimmingOrHints() {
    for style in TypoIndicatorStyle.allCases {
      for (character, marker) in [(Character(" "), "_"), ("\t", "→"), ("\n", "↵")] {
        let plan = PromptControlCharacterPresentation.plan(
          for: .init(character: character, state: .extra), style: style)
        XCTAssertEqual(plan, .init(text: marker, hint: nil, opacity: 1))
      }
    }
  }

  func testConcealedExtraRetainsItsOriginWithoutBecomingASourceLineBreak() {
    let plan = PromptControlCharacterPresentation.plan(
      for: .init(character: "\n", state: .hidden), style: .both, isExtra: true)
    XCTAssertEqual(plan, .init(text: "↵", hint: nil, opacity: 1))
  }

  func testZenControlsRemainInvisibleAndPreserveItsEnteredWhitespace() {
    for style in TypoIndicatorStyle.allCases {
      for character: Character in ["\t", "\n"] {
        XCTAssertEqual(PromptControlCharacterPresentation.plan(
          for: .init(character: character, state: .correct), style: style, isZen: true),
          .init(text: String(character), hint: nil, opacity: 0))
      }
      XCTAssertEqual(PromptControlCharacterPresentation.plan(
        for: .init(character: " ", state: .correct), style: style, isZen: true),
        .init(text: " ", hint: nil, opacity: 1))
    }
  }

  func testSpacesAndNonASCIIWhitespaceAreNotInventedAsControlErrors() {
    for character: Character in [" ", "\u{00a0}", "\u{3000}", "🙂", "e\u{301}"] {
      XCTAssertEqual(PromptControlCharacterPresentation.plan(
        for: .init(character: character, state: .correct), style: .both),
        .init(text: String(character), hint: nil, opacity: 1))
    }
  }

  func testHiddenAndBlindNeutralizedGlyphsCannotPublishTypoHints() {
    for state in [TypingPromptCharacterState.hidden, .correct] {
      XCTAssertNil(PromptControlCharacterPresentation.plan(
        for: .init(character: "b", state: state, typedCharacter: "\n"), style: .both).hint)
    }
  }

  private func render(_ session: TypingSession, style: TypoIndicatorStyle = .off) -> PromptRendering {
    let glyphs = session.promptGlyphs
    let targetCount = session.prompt.count
    return PromptRendering.make(glyphs: glyphs, indices: PromptGlyphLayout.indices(
      glyphs: glyphs, words: session.promptWordPresentations,
      hideExtraLetters: session.configuration.rules.hideExtraLetters)) { index, glyph in
        AttributedString(PromptControlCharacterPresentation.plan(for: glyph, style: style,
          isZen: session.configuration.mode == .zen, isExtra: index >= targetCount).text)
      }
  }

  func testStoppedReturnAgainstALetterDoesNotReflowTheFollowingTarget() {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .letter)), prompt: "ab\ncd")
    session.insertBatch("a", at: start)
    session.insertBatch("\n", at: start)
    let rendering = render(session, style: .replace)
    XCTAssertEqual(String(rendering.text.characters), "a↵↵\ncd")
    XCTAssertEqual(rendering.characterOffset(forGlyphAt: 3), 4)
    XCTAssertEqual(rendering.characterOffset(forGlyphAt: session.promptCaretGlyphIndex), 1)
    XCTAssertEqual(session.typed, "a")
  }

  func testTabSymbolsAndReturnMarkersKeepFollowingCaretOffsets() {
    var session = TypingSession(configuration: .words(2), prompt: "\tab\ncd")
    session.insertBatch("\tab\n", at: start)
    let rendering = render(session)
    XCTAssertEqual(String(rendering.text.characters), "→ab↵\ncd")
    XCTAssertEqual(rendering.characterOffset(forGlyphAt: session.promptCaretGlyphIndex), 5)
    XCTAssertEqual(session.typed, "\tab\n")
  }

  @MainActor func testNativeGeometryPlacesTheCaretOnTheExistingLineForAStoppedReturn() throws {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .letter)), prompt: "ab\ncd")
    session.insertBatch("a", at: start)
    session.insertBatch("\n", at: start)
    let rendering = render(session, style: .replace)
    let font = NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)
    let size = CGSize(width: 800, height: 200)
    let rejected = try XCTUnwrap(PromptCaretLayout.rect(in: rendering.text,
      characterOffset: try XCTUnwrap(rendering.characterOffset(forGlyphAt: session.promptCaretGlyphIndex)),
      containerSize: size, font: font, lineSpacing: 12))
    let nextLine = try XCTUnwrap(PromptCaretLayout.rect(in: rendering.text,
      characterOffset: try XCTUnwrap(rendering.characterOffset(forGlyphAt: 3)),
      containerSize: size, font: font, lineSpacing: 12))
    XCTAssertGreaterThan(rejected.width, 0)
    XCTAssertGreaterThan(nextLine.minY, rejected.minY)
  }

  @MainActor func testNativeInputBridgeKeepsTheStoppedControlOutOfAcceptedText() throws {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .letter)), prompt: "ab\ncd")
    let input = TypingInputView(frame: .zero)
    input.acceptsNewlineInput = true
    input.onInsert = { text, forced in
      _ = TypingLiveInputFeedback.insertBatch(text, into: &session, forceError: forced, at: self.start)
    }
    input.insertText("a", replacementRange: .init())
    input.insertText("\n", replacementRange: .init())
    XCTAssertEqual(String(render(session, style: .replace).text.characters), "a↵↵\ncd")
    XCTAssertEqual(session.typed, "a")
    session.bailOut(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 2)
    XCTAssertEqual(result.replayEvents.map(\.text), ["a", "\n"])
    XCTAssertEqual(result.replayEvents.last?.inputStopped, true)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), "a")
  }

  func testRenderingAllStylesDoesNotMutateResultsOrArchiveInput() throws {
    var session = TypingSession(configuration: .words(2), prompt: "\tab\ncd")
    session.insertBatch("\tab\n", at: start)
    for style in TypoIndicatorStyle.allCases { _ = render(session, style: style) }
    session.insertBatch("cd", at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.typedCharacterCount, 6)
    XCTAssertEqual(result.prompt, "\tab\ncd")
    XCTAssertEqual(result.replayEvents.map(\.text).joined(), "\tab\ncd")
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    XCTAssertEqual(archive.version, TypebarArchive.currentVersion)
    XCTAssertEqual(archive.results, [result])
  }

  func testCompositionControlsUseTextWhitespaceInsteadOfBodyIconsOrTargetDimming() {
    XCTAssertEqual(PromptControlCharacterPresentation.plan(
      for: .init(character: "\t", state: .current), style: .both,
      compositionReplacement: " 候\t\n"), .init(text: "_候  ", hint: nil, opacity: 1))
    XCTAssertEqual(PromptControlCharacterPresentation.plan(
      for: .init(character: "\n", state: .current), style: .both,
      compositionReplacement: "候\n"), .init(text: "候 \n", hint: nil, opacity: 1))
  }

  func testZenCandidateDoesNotInventAnUnderscoreOrBecomeAnInvisibleEnteredTab() {
    XCTAssertEqual(PromptControlCharacterPresentation.plan(
      for: .init(character: "\t", state: .current), style: .both,
      isZen: true, compositionReplacement: " 候\t"),
      .init(text: " 候 ", hint: nil, opacity: 1))
  }

  func testCandidateReplacementCannotPublishThePreviousStoppedTypoHint() {
    XCTAssertEqual(PromptControlCharacterPresentation.plan(
      for: .init(character: "b", state: .incorrect, typedCharacter: "x"), style: .both,
      compositionReplacement: "候选"), .init(text: "候选", hint: nil, opacity: 1))
  }
}
