import AppKit
import SwiftUI
import XCTest
@testable import Typebar

final class RuntimeExtraVisibilityTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  func testActiveToggleImmediatelyRemovesExtraLayoutAndRestoresItAtTheSameWord() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("abcxy", at: start)
    let visible = session.promptGlyphs
    XCTAssertEqual(displayText(session), "abcxy bay cedar")
    session.setHideExtraLetters(true)
    XCTAssertTrue(session.configuration.rules.hideExtraLetters)
    XCTAssertEqual(displayText(session), "abc bay cedar")
    XCTAssertEqual(session.promptGlyphs.count, visible.count, "Logical glyph indices stay stable")
    XCTAssertTrue(session.promptGlyphs.suffix(2).allSatisfy { $0.state == .hidden })
    XCTAssertEqual(render(session).characterOffset(forGlyphAt: 3), 3)
    XCTAssertEqual(tapeAnchor(session, .letter), 3)
    session.setHideExtraLetters(false)
    XCTAssertEqual(session.promptGlyphs, visible)
    XCTAssertEqual(displayText(session), "abcxy bay cedar")
    XCTAssertEqual(render(session).characterOffset(forGlyphAt: 3), 5)
  }

  func testCommittedExtrasAcrossWordsKeepTheirOwnersAndErrorBordersAfterToggle() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("abcx bayyz ", at: start)
    let words = session.promptWordPresentations
    session.setHideExtraLetters(true)
    XCTAssertEqual(displayText(session), "abc bay cedar")
    XCTAssertEqual(session.promptWordPresentations, words)
    XCTAssertEqual(render(session).characterOffset(forGlyphAt: 8), 8)
    XCTAssertEqual(tapeAnchor(session, .word), 8)
    let appearances = PromptGlyphAppearance.plan(glyphs: session.promptGlyphs,
      words: session.promptWordPresentations, mode: .word, blindMode: false)
    XCTAssertTrue(appearances[0..<3].allSatisfy { $0.color == .error && $0.hasErrorUnderline })
    session.setHideExtraLetters(false)
    XCTAssertEqual(displayText(session), "abcx bayyz cedar")
    XCTAssertEqual(render(session).characterOffset(forGlyphAt: 8), 11)
    XCTAssertEqual(tapeAnchor(session, .word), 11)
    XCTAssertEqual(session.errors, 3)
  }

  func testToggleIsPresentationOnlyAndResultUsesTheFinalActiveSetting() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "abc bay cedar")
    session.insertBatch("abcx", at: start)
    let typed = session.typed
    let lastFeedback = session.lastInputWasCorrect
    let accuracy = session.preciseAccuracy
    for hidden in [true, true, false, true] { session.setHideExtraLetters(hidden) }
    XCTAssertEqual(session.typed, typed)
    XCTAssertEqual(session.startedAt, start)
    XCTAssertEqual(session.errors, 1)
    XCTAssertEqual(session.preciseAccuracy, accuracy)
    XCTAssertEqual(session.lastInputWasCorrect, lastFeedback)
    session.tick(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertTrue(result.configuration.rules.hideExtraLetters)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 4)
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 3)
    XCTAssertEqual(result.replayEvents.map(\.text), ["a", "b", "c", "x"])
    XCTAssertEqual(result.preciseAccuracy, 75)
    XCTAssertEqual(result.errorCount, 1)
    XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONEncoder().encode(result)), result)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
  }

  func testPreviouslyHiddenExtrasCanBeShownWithoutStartingANewAttempt() {
    var session = TypingSession(configuration: .words(3, rules: .init(hideExtraLetters: true)),
      prompt: "abc bay cedar")
    session.setHideExtraLetters(false)
    XCTAssertFalse(session.hasStarted)
    session.insertBatch("abcx", at: start)
    XCTAssertEqual(displayText(session), "abcx bay cedar")
    XCTAssertEqual(session.startedAt, start)
    XCTAssertEqual(session.typed, "abcx")
  }

  func testBlindAndHiddenExtraSettingsRemainIndependent() {
    var session = TypingSession(configuration: .words(3, rules: .init(blindMode: true)),
      prompt: "abc bay cedar")
    session.insertBatch("abcx", at: start)
    session.setHideExtraLetters(true)
    XCTAssertEqual(displayText(session), "abc bay cedar")
    session.setBlindMode(false)
    XCTAssertEqual(displayText(session), "abc bay cedar")
    XCTAssertEqual(session.promptGlyphs.last?.state, .hidden)
    session.setHideExtraLetters(false)
    XCTAssertEqual(displayText(session), "abcx bay cedar")
    XCTAssertEqual(session.promptGlyphs.last?.state, .extra)
    XCTAssertEqual(session.errors, 1)
    session.setBlindMode(true)
    XCTAssertEqual(displayText(session), "abc bay cedar")
  }

  func testTerminalFlagIsFrozenAndRepeatedAttemptStartsWithItsFinishedConfiguration() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "abc bay cedar")
    session.insertBatch("abcx", at: start)
    session.setHideExtraLetters(true)
    session.tick(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    session.setHideExtraLetters(false)
    XCTAssertTrue(session.configuration.rules.hideExtraLetters)
    XCTAssertEqual(session.configuration, result.configuration)
    let repeated = session.repeatedAttempt()
    XCTAssertTrue(repeated.configuration.rules.hideExtraLetters)
    XCTAssertFalse(repeated.hasStarted)
    XCTAssertEqual(displayText(repeated), session.prompt)
  }

  @MainActor func testNativeInsertUsesTheLatestPreferenceBeforeTheNextAcceptedKey() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    var hiddenPreference = false
    let input = TypingInputView(frame: .zero)
    input.onInsert = { text, forced in
      session.setHideExtraLetters(hiddenPreference)
      session.insertBatch(text, forceError: forced, at: self.start)
    }
    input.insertText("abc", replacementRange: .init())
    hiddenPreference = true
    input.insertText("x", replacementRange: .init())
    XCTAssertEqual(displayText(session), "abc bay cedar")
    XCTAssertEqual(session.typed, "abcx")
    XCTAssertEqual(session.errors, 1)
    hiddenPreference = false
    input.insertText("y", replacementRange: .init())
    XCTAssertEqual(displayText(session), "abcxy bay cedar")
    XCTAssertEqual(session.typed, "abcxy")
  }

  @MainActor func testNativeCompositionUpdatesVisibilityWithoutAcceptingTheCandidate() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("abc", at: start)
    let input = TypingInputView(frame: .zero)
    input.onCompositionStarted = {
      session.setHideExtraLetters(true)
      session.beginComposition(at: self.start.addingTimeInterval(0.1))
    }
    input.onInsert = { text, forced in
      session.setHideExtraLetters(true)
      session.insertBatch(text, forceError: forced, at: self.start.addingTimeInterval(0.2))
    }
    input.setMarkedText("x", selectedRange: .init(), replacementRange: .init())
    XCTAssertTrue(session.configuration.rules.hideExtraLetters)
    XCTAssertEqual(session.typed, "abc")
    XCTAssertEqual(session.preciseAccuracy, 100)
    XCTAssertFalse(session.shouldFinishWithComposition("x", forceError: false))
    input.insertText("x", replacementRange: .init())
    XCTAssertEqual(session.typed, "abcx")
    XCTAssertEqual(displayText(session), "abc bay cedar")
    XCTAssertEqual(session.errors, 1)
  }

  @MainActor func testRealCommandConsumerUpdatesAndPersistsPreferenceWithoutRestarting() throws {
    let suite = "TypebarTests.runtime-extra-command.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("abcxy", at: start)
    let before = session.configuration
    for (id, hidden) in [("input.hideExtraLetters.on", true), ("input.hideExtraLetters.off", false)] {
      let target = try XCTUnwrap(InputRuleCommandCatalog.target(for: id))
      XCTAssertFalse(target.requiresRestart)
      XCTAssertFalse(target.exitsChallenge)
      target.apply(to: settings, session: &session)
      XCTAssertEqual(settings.hideExtraLetters, hidden)
      XCTAssertEqual(AppSettings(defaults: defaults).hideExtraLetters, hidden)
      var expected = before
      expected.rules.hideExtraLetters = hidden
      XCTAssertEqual(session.configuration, expected)
      XCTAssertEqual(displayText(session), hidden ? "abc bay cedar" : "abcxy bay cedar")
      XCTAssertEqual(session.typed, "abcxy")
      XCTAssertEqual(session.startedAt, start)
      XCTAssertEqual(session.errors, 2)
    }
    session.setHideExtraLetters(true)
    session.abandon(at: start.addingTimeInterval(1))
    let finished = session.configuration
    InputRuleCommandTarget.hideExtraLetters(false).apply(to: settings, session: &session)
    XCTAssertFalse(settings.hideExtraLetters)
    XCTAssertEqual(session.configuration, finished, "A future preference cannot rewrite a terminal result")
  }

  func testStoppedOrAutomaticallyDeletedErrorsAreNotRescoredByVisibility() throws {
    for rules in [InputRules(stopOnErrorMode: .letter), InputRules(deleteOnErrorMode: .letter)] {
      var session = TypingSession(configuration: .timed(seconds: 1, rules: rules), prompt: "abc bay")
      session.insertBatch("x", at: start)
      session.setHideExtraLetters(true)
      session.setHideExtraLetters(false)
      session.setHideExtraLetters(true)
      XCTAssertEqual(session.typed, "")
      XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(session.preciseAccuracy, 0)
      session.tick(at: start.addingTimeInterval(1))
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.inputMetrics?.totalAttempts, 1)
      XCTAssertEqual(result.inputMetrics?.correctAttempts, 0)
      XCTAssertTrue(result.configuration.rules.hideExtraLetters)
      XCTAssertEqual(result.replayEvents.count, rules.deleteOnErrorMode.isEnabled ? 2 : 0)
    }
  }

  func testAllowedAndBlockedDeletionKeepTheirExistingExtraOwnershipRules() {
    for confidence in [ConfidenceMode.off, .maximum] {
      var session = TypingSession(configuration: .words(3, rules: .init(confidenceMode: confidence)),
        prompt: "abc bay cedar")
      session.insertBatch("abcx ", at: start)
      session.setHideExtraLetters(true)
      session.deleteBackward(at: start.addingTimeInterval(0.2))
      session.setHideExtraLetters(false)
      XCTAssertEqual(session.typed, confidence == .maximum ? "abcx " : "abcx")
      XCTAssertEqual(displayText(session), "abcx bay cedar")
      XCTAssertEqual(session.errors, 1)
      XCTAssertEqual(session.promptWordPresentations[0].hasCommitError, confidence == .maximum)
    }
  }

  func testMemoryConcealmentStillWinsAfterBothVisibilityTransitions() {
    var session = TypingSession(configuration: TestConfiguration.words(2).with(modifiers: [.memory]),
      prompt: "abc bay")
    session.insertBatch("abcx", at: start)
    for hidden in [true, false] {
      session.setHideExtraLetters(hidden)
      XCTAssertEqual(displayText(session), hidden ? "abc bay" : "abcx bay")
      XCTAssertTrue(session.promptGlyphsInDisplayOrder.allSatisfy { $0.state == .hidden })
      let appearances = PromptGlyphAppearance.plan(glyphs: session.promptGlyphs,
        words: session.promptWordPresentations, mode: .word, blindMode: false)
      XCTAssertTrue(appearances.allSatisfy { $0.color == .hidden && !$0.hasErrorUnderline })
      XCTAssertEqual(session.errors, 1)
    }
  }

  func testUnicodeCaretIndicesAndZenContentAreUnaffectedByExtraVisibility() {
    var session = TypingSession(configuration: .words(2), prompt: "🙂e\u{301} bay")
    session.insertBatch("🙂e\u{301}Ω", at: start)
    session.setHideExtraLetters(true)
    XCTAssertEqual(displayText(session), "🙂e\u{301} bay")
    XCTAssertEqual(render(session).characterOffset(forGlyphAt: 2), 2)
    session.setHideExtraLetters(false)
    XCTAssertEqual(displayText(session), "🙂e\u{301}Ω bay")
    XCTAssertEqual(render(session).characterOffset(forGlyphAt: 2), 3)
    XCTAssertEqual(session.preciseAccuracy, 80)
    var zen = TypingSession(configuration: .init(mode: .zen, duration: nil,
      wordLimit: nil, difficulty: .normal, rules: .init()), prompt: "")
    zen.insertBatch("🙂 e\u{301}Ω", at: start)
    for hidden in [true, false] {
      zen.setHideExtraLetters(hidden)
      XCTAssertEqual(displayText(zen), "🙂 e\u{301}Ω ")
      XCTAssertEqual(zen.preciseAccuracy, 100)
      XCTAssertEqual(zen.errors, 0)
    }
  }

  func testEveryTerminalOutcomeRejectsLateVisibilityMutation() {
    let finishers: [(inout TypingSession, Date) -> Void] = [
      { $0.tick(at: $1) }, { $0.abandon(at: $1) }, { $0.bailOut(at: $1) },
    ]
    for finish in finishers {
      var session = TypingSession(configuration: .timed(seconds: 1), prompt: "abc bay cedar")
      session.insertBatch("abcx", at: start)
      session.setHideExtraLetters(true)
      finish(&session, start.addingTimeInterval(1))
      XCTAssertTrue(session.isFinished)
      let configuration = session.configuration
      session.setHideExtraLetters(false)
      XCTAssertEqual(session.configuration, configuration)
    }
    var failed = TypingSession(configuration: .words(2, difficulty: .master), prompt: "abc bay")
    failed.setHideExtraLetters(true)
    failed.insertBatch("x", at: start)
    XCTAssertTrue(failed.isFinished)
    failed.setHideExtraLetters(false)
    XCTAssertTrue(failed.configuration.rules.hideExtraLetters)
  }

  private func displayText(_ session: TypingSession) -> String {
    String(session.promptGlyphsInDisplayOrder.map(\.character))
  }

  private func render(_ session: TypingSession) -> PromptRendering {
    let glyphs = session.promptGlyphs
    return PromptRendering.make(glyphs: glyphs, indices: PromptGlyphLayout.indices(
      glyphs: glyphs, words: session.promptWordPresentations,
      hideExtraLetters: session.configuration.rules.hideExtraLetters)) { _, glyph in
        AttributedString(String(glyph.character))
      }
  }

  private func tapeAnchor(_ session: TypingSession, _ mode: PracticeTapeMode) -> Int {
    PracticeTapePolicy.anchorCharacterIndex(session: session, rendering: render(session), mode: mode)
  }
}
