import AppKit
import XCTest
@testable import Typebar

final class RuntimeInputRuleTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  func testLiveSnapshotDoesNotStartOrReplaceRestartOnlyRules() {
    let original = InputRules(strictSpace: true, stopOnErrorMode: .word,
      codeUnindentOnBackspace: true, minimumAccuracy: 60, minimumWpm: 10)
    var session = TypingSession(configuration: .words(3, rules: original), prompt: "abc bay cedar")
    session.synchronizeLiveInputRules(.init(quickEnd: true, freedomMode: true,
      oppositeShiftMode: .keymap))
    var expected = original
    expected.quickEnd = true
    expected.freedomMode = true
    expected.oppositeShiftMode = .keymap
    XCTAssertEqual(session.configuration.rules, expected)
    XCTAssertFalse(session.hasStarted)
    XCTAssertEqual(session.typed, "")
    XCTAssertEqual(session.prompt, "abc bay cedar")
  }

  func testFreedomChangesTheNextDeletionWithoutRewindingOnToggle() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("abc ", at: start)
    session.deleteBackward(at: start)
    XCTAssertEqual(session.typed, "abc ")
    session.synchronizeLiveInputRules(.init(freedomMode: true))
    XCTAssertEqual(session.typed, "abc ")
    session.deleteBackward(at: start)
    XCTAssertEqual(session.typed, "abc")
    session.insertBatch(" ", at: start)
    session.synchronizeLiveInputRules(.init())
    session.deleteBackward(at: start)
    XCTAssertEqual(session.typed, "abc ")
    XCTAssertEqual(session.startedAt, start)
  }

  func testConfidenceOnBlocksPreviousWrongWordButAllowsCurrentWordDeletion() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("abx ", at: start)
    session.synchronizeLiveInputRules(.init(confidenceMode: .on))
    session.deleteBackward(at: start)
    XCTAssertEqual(session.typed, "abx ")
    session.insertBatch("b", at: start)
    session.deleteBackward(at: start)
    XCTAssertEqual(session.typed, "abx ")
    session.synchronizeLiveInputRules(.init())
    session.deleteBackward(at: start)
    XCTAssertEqual(session.typed, "abx")
  }

  func testMaximumConfidenceBlocksBothDeletePathsThenFreedomRemovesTheRestriction() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("abc ba", at: start)
    session.synchronizeLiveInputRules(.init(confidenceMode: .maximum))
    session.deleteBackward(at: start)
    session.deleteWordBackward(at: start)
    XCTAssertEqual(session.typed, "abc ba")
    session.synchronizeLiveInputRules(.init(freedomMode: true))
    session.deleteWordBackward(at: start)
    XCTAssertEqual(session.typed, "abc ")
    session.deleteBackward(at: start)
    XCTAssertEqual(session.typed, "abc")
  }

  func testRecoveryVariantsOnlyDeleteAfterTheNextWrongAttempt() throws {
    for (mode, expected) in [(DeleteOnErrorMode.letter, "a"), (.letterHard, "a"),
      (.word, ""), (.wordHard, "")]
    {
      var session = TypingSession(configuration: .timed(seconds: 1), prompt: "abc bay cedar")
      session.insertBatch("ab", at: start)
      session.synchronizeLiveInputRules(.init(deleteOnErrorMode: mode))
      XCTAssertEqual(session.typed, "ab")
      session.insertBatch("x", at: start.addingTimeInterval(0.1))
      XCTAssertEqual(session.typed, expected, mode.rawValue)
      session.tick(at: start.addingTimeInterval(1))
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.inputMetrics?.totalAttempts, 3)
      XCTAssertEqual(result.inputMetrics?.correctAttempts, 2)
      XCTAssertEqual(result.replayEvents.filter { $0.kind == .insert }.map(\.text), ["a", "b", "x"])
      XCTAssertTrue(result.replayEvents.contains { $0.kind == .delete && $0.automatic })
      XCTAssertTrue(result.configuration.rules.deleteOnError)
      XCTAssertEqual(result.configuration.rules.deleteOnErrorMode, mode)
    }
  }

  func testRecoveryToggleKeepsOldMistakeAndDisablingRetainsTheNextOne() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("abx", at: start)
    session.synchronizeLiveInputRules(.init(deleteOnErrorMode: .word))
    XCTAssertEqual(session.typed, "abx")
    XCTAssertEqual(session.errors, 1)
    session.synchronizeLiveInputRules(.init())
    session.insertBatch("y", at: start)
    XCTAssertEqual(session.typed, "abxy")
    XCTAssertEqual(session.errors, 2)
    XCTAssertFalse(session.configuration.rules.deleteOnError)
  }

  func testHardRecoveryCanReturnToPreviousWordAfterBeingEnabledLive() {
    for (mode, expected) in [(DeleteOnErrorMode.letterHard, "abc"), (.wordHard, "")] {
      var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
      session.insertBatch("abc ", at: start)
      session.synchronizeLiveInputRules(.init(deleteOnErrorMode: mode))
      session.insertBatch("x", at: start)
      XCTAssertEqual(session.typed, expected, mode.rawValue)
    }
  }

  func testOppositeShiftChangesRejectedAttemptsAndCanBeDisabled() throws {
    for mode in [OppositeShiftMode.on, .keymap] {
      var session = TypingSession(configuration: .timed(seconds: 1), prompt: "abc bay cedar")
      session.insertBatch("a", at: start)
      session.synchronizeLiveInputRules(.init(oppositeShiftMode: mode))
      session.insertBatch("b", forceError: true, at: start)
      XCTAssertEqual(session.typed, "a", mode.rawValue)
      XCTAssertEqual(session.lastInputWasCorrect, false)
      session.synchronizeLiveInputRules(.init())
      session.insertBatch("b", at: start)
      XCTAssertEqual(session.typed, "ab")
      session.tick(at: start.addingTimeInterval(1))
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.inputMetrics?.totalAttempts, 3)
      XCTAssertEqual(result.inputMetrics?.correctAttempts, 2)
      XCTAssertEqual(result.replayEvents.filter { !$0.isStoppedInsertion }.map(\.text), ["a", "b"])
      XCTAssertEqual(result.replayEvents.filter(\.isStoppedInsertion).map(\.text), ["b"])
    }
  }

  func testLiveOppositeShiftStillFailsMasterDifficulty() {
    var session = TypingSession(configuration: .words(3, difficulty: .master), prompt: "abc bay cedar")
    session.synchronizeLiveInputRules(.init(oppositeShiftMode: .on))
    session.insertBatch("a", forceError: true, at: start)
    XCTAssertTrue(session.isFinished)
    XCTAssertEqual(session.typed, "")
  }

  func testQuickEndStartsApplyingAtTheNextFinalWordInput() {
    var session = TypingSession(configuration: .words(2), prompt: "abc bay")
    session.insertBatch("abc bx", at: start)
    session.synchronizeLiveInputRules(.init(quickEnd: true))
    XCTAssertFalse(session.isFinished)
    session.insertBatch("z", at: start.addingTimeInterval(0.1))
    XCTAssertTrue(session.isFinished)
    XCTAssertEqual(session.typed, "abc bxz")
  }

  func testQuickEndToggleAloneDoesNotFinishAnAlreadyFullWrongFinalWord() {
    var session = TypingSession(configuration: .words(2), prompt: "abc bay")
    session.insertBatch("abc bxz", at: start)
    session.synchronizeLiveInputRules(.init(quickEnd: true))
    session.tick(at: start.addingTimeInterval(0.1))
    XCTAssertFalse(session.isFinished)
    XCTAssertEqual(session.typed, "abc bxz")
    XCTAssertTrue(session.configuration.rules.quickEnd)
    session.deleteBackward(at: start)
    session.insertBatch("z", at: start.addingTimeInterval(0.2))
    XCTAssertTrue(session.isFinished)
  }

  func testDisablingQuickEndRequiresTheIncorrectFinalWordCommitAgain() {
    var session = TypingSession(configuration: .words(2, rules: .init(quickEnd: true)), prompt: "abc bay")
    session.insertBatch("abc bx", at: start)
    session.synchronizeLiveInputRules(.init())
    session.insertBatch("z", at: start)
    XCTAssertFalse(session.isFinished)
    session.insertBatch(" ", at: start.addingTimeInterval(0.1))
    XCTAssertTrue(session.isFinished)
  }

  func testConfidenceAndRecoveryClearStoppedInputAliasesWithoutRestoringThem() {
    for live in [InputRules(confidenceMode: .maximum), InputRules(deleteOnErrorMode: .word)] {
      var session = TypingSession(configuration: .words(3, rules: .init(stopOnErrorMode: .letter)),
        prompt: "abc bay cedar")
      session.insertBatch("ab", at: start)
      session.synchronizeLiveInputRules(live)
      XCTAssertFalse(session.configuration.rules.stopOnError)
      XCTAssertEqual(session.configuration.rules.stopOnErrorMode, .off)
      session.synchronizeLiveInputRules(.init())
      session.insertBatch("x", at: start)
      XCTAssertEqual(session.typed, "abx")
      XCTAssertEqual(session.configuration.rules.stopOnErrorMode, .off)
    }
  }

  func testNoSpaceHardRecoveryUsesTheExistingHiddenBoundaryAfterLiveToggle() {
    var session = TypingSession(configuration: .words(2, language: .simplifiedChinese),
      prompt: "晨光窗边", noSpaceWordEndIndices: [2, 4])
    session.insertBatch("晨光窗", at: start)
    session.synchronizeLiveInputRules(.init(deleteOnErrorMode: .wordHard))
    session.insertBatch("x", at: start)
    XCTAssertEqual(session.typed, "晨光")
    XCTAssertEqual(session.errors, 0)
  }

  func testFinalConfigurationRoundTripsAndRepeatKeepsTheLastLiveRules() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "abc bay cedar")
    session.insertBatch("a", at: start)
    let live = InputRules(hideExtraLetters: true, blindMode: true, quickEnd: true,
      freedomMode: true, oppositeShiftMode: .keymap)
    session.synchronizeLiveInputRules(live)
    session.tick(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.configuration.rules, live)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 1)
    XCTAssertEqual(result.replayEvents.map(\.text), ["a"])
    session.synchronizeLiveInputRules(.init())
    XCTAssertEqual(session.configuration, result.configuration)
    XCTAssertEqual(session.repeatedAttempt().configuration, result.configuration)
    XCTAssertFalse(session.repeatedAttempt().hasStarted)
    XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONEncoder().encode(result)), result)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
  }

  @MainActor func testRealCommandConsumerAppliesEveryLiveOptionWithoutRestarting() throws {
    let suite = "TypebarTests.runtime-rules.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("ab", at: start)
    let ids = ["input.freedomMode.on", "input.confidenceMode.max", "input.deleteOnError.word",
      "input.oppositeShiftMode.keymap", "input.quickEnd.on", "input.deleteOnError.off",
      "input.oppositeShiftMode.off", "input.quickEnd.off", "input.freedomMode.off"]
    for id in ids {
      let command = try XCTUnwrap(InputRuleCommandCatalog.target(for: id))
      XCTAssertFalse(command.requiresRestart)
      XCTAssertFalse(command.exitsChallenge)
      command.apply(to: settings, session: &session)
      XCTAssertEqual(session.configuration.rules, settings.inputRules, id)
      XCTAssertEqual(AppSettings(defaults: defaults).inputRules, settings.inputRules, id)
      XCTAssertEqual(session.typed, "ab")
      XCTAssertEqual(session.startedAt, start)
    }
  }

  @MainActor func testRealCommandDependenciesRespectTheMostRecentSelection() throws {
    let suite = "TypebarTests.runtime-rule-dependencies.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.stopOnErrorMode = .letter
    var session = TypingSession(configuration: .words(3, rules: settings.inputRules), prompt: "abc bay cedar")
    session.insertBatch("ab", at: start)
    InputRuleCommandTarget.deleteOnError(.word).apply(to: settings, session: &session)
    XCTAssertEqual(session.configuration.rules.stopOnErrorMode, .off)
    XCTAssertEqual(session.configuration.rules.deleteOnErrorMode, .word)
    InputRuleCommandTarget.confidenceMode(.maximum).apply(to: settings, session: &session)
    XCTAssertEqual(session.configuration.rules.deleteOnErrorMode, .off)
    XCTAssertFalse(session.configuration.rules.deleteOnError)
    InputRuleCommandTarget.freedomMode(true).apply(to: settings, session: &session)
    XCTAssertEqual(session.configuration.rules.confidenceMode, .off)
    XCTAssertTrue(session.configuration.rules.freedomMode)
    session.deleteBackward(at: start)
    XCTAssertEqual(session.typed, "a")
  }

  @MainActor func testNativeInputReadsLatestRulesBeforeInsertAndDeletion() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    var live = InputRules()
    let input = TypingInputView(frame: .zero)
    input.onInsert = { text, forced in
      session.synchronizeLiveInputRules(live)
      session.insertBatch(text, forceError: forced, at: self.start)
    }
    input.onDelete = {
      session.synchronizeLiveInputRules(live)
      session.deleteBackward(at: self.start)
    }
    input.insertText("ab", replacementRange: .init())
    live.deleteOnErrorMode = .word
    live.deleteOnError = true
    input.insertText("x", replacementRange: .init())
    XCTAssertEqual(session.typed, "")
    input.insertText("a", replacementRange: .init())
    live = .init(confidenceMode: .maximum)
    input.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
    XCTAssertEqual(session.typed, "a")
    live = .init()
    input.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
    XCTAssertEqual(session.typed, "")
  }

  func testQuickEndRemainsBlockedByStoppedInputAndLiveAutomaticRecovery() {
    for initial in [InputRules(stopOnErrorMode: .word), InputRules()] {
      var session = TypingSession(configuration: .words(2, rules: initial), prompt: "abc bay")
      session.insertBatch("abc bx", at: start)
      let live = initial.stopOnErrorMode.isEnabled
        ? InputRules(quickEnd: true) : InputRules(deleteOnErrorMode: .word, quickEnd: true)
      session.synchronizeLiveInputRules(live)
      session.insertBatch("z", at: start)
      XCTAssertFalse(session.isFinished)
      XCTAssertEqual(session.typed, initial.stopOnErrorMode.isEnabled ? "abc bxz" : "abc ")
    }
  }

  func testEveryTerminalOutcomeRejectsLateLiveRuleChanges() {
    let finishers: [(inout TypingSession, Date) -> Void] = [
      { $0.tick(at: $1) }, { $0.abandon(at: $1) }, { $0.bailOut(at: $1) },
    ]
    for finish in finishers {
      var session = TypingSession(configuration: .timed(seconds: 1), prompt: "abc bay cedar")
      session.insertBatch("a", at: start)
      session.synchronizeLiveInputRules(.init(quickEnd: true, confidenceMode: .maximum,
        oppositeShiftMode: .keymap))
      finish(&session, start.addingTimeInterval(1))
      XCTAssertTrue(session.isFinished)
      let configuration = session.configuration
      session.synchronizeLiveInputRules(.init(deleteOnErrorMode: .word, freedomMode: true))
      XCTAssertEqual(session.configuration, configuration)
    }
    var failed = TypingSession(configuration: .words(3, difficulty: .master), prompt: "abc bay cedar")
    failed.insertBatch("x", at: start)
    let configuration = failed.configuration
    failed.synchronizeLiveInputRules(.init(quickEnd: true, confidenceMode: .maximum))
    XCTAssertTrue(failed.isFinished)
    XCTAssertEqual(failed.configuration, configuration)
  }

  @MainActor func testLateCommandPersistsFuturePreferenceButCannotRewriteFinishedResult() throws {
    let suite = "TypebarTests.runtime-rules-terminal.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "abc bay cedar")
    session.insertBatch("a", at: start)
    session.tick(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    InputRuleCommandTarget.confidenceMode(.maximum).apply(to: settings, session: &session)
    XCTAssertEqual(AppSettings(defaults: defaults).confidenceMode, .maximum)
    XCTAssertEqual(session.configuration, result.configuration)
    XCTAssertEqual(session.typed, "a")
  }

  @MainActor func testNativeCandidatePreflightSynchronizesWithoutScoringTheProbe() throws {
    var session = TypingSession(configuration: .words(2), prompt: "abc bay")
    session.insertBatch("abc b", at: start)
    var live = InputRules(quickEnd: true, confidenceMode: .maximum)
    let input = TypingInputView(frame: .zero)
    input.onCompositionStarted = {
      session.synchronizeLiveInputRules(live)
      session.beginComposition(at: self.start.addingTimeInterval(0.1))
    }
    input.shouldFinishWithComposition = { text, forced in
      session.synchronizeLiveInputRules(live)
      return session.shouldFinishWithComposition(text, forceError: forced,
        at: self.start.addingTimeInterval(0.2))
    }
    input.onInsert = { text, forced in
      session.synchronizeLiveInputRules(live)
      session.insertBatch(text, forceError: forced, at: self.start.addingTimeInterval(0.2))
    }
    input.setMarkedText("xx", selectedRange: .init(), replacementRange: .init())
    XCTAssertEqual(session.typed, "abc b")
    XCTAssertFalse(session.isFinished, "Quick End cannot auto-confirm an incorrect candidate")
    XCTAssertEqual(session.configuration.rules.confidenceMode, .maximum)
    live = .init(deleteOnErrorMode: .word)
    input.setMarkedText("ay", selectedRange: .init(), replacementRange: .init())
    XCTAssertTrue(session.isFinished)
    XCTAssertEqual(session.typed, "abc bay")
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 7)
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 7)
    XCTAssertEqual(result.configuration.rules.deleteOnErrorMode, .word)
    XCTAssertEqual(result.configuration.rules.confidenceMode, .off)
    XCTAssertFalse(result.configuration.rules.quickEnd)
    XCTAssertEqual(result.replayEvents.filter { $0.kind == .insert }.map(\.text).joined(), "abc bay")
  }
}
