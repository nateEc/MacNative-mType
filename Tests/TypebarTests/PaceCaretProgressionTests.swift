import XCTest
@testable import Typebar

final class PaceCaretProgressionTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)

  func testFirstAnimationTargetsNextLetterImmediately() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "ab cd efg")
    session.configurePace(wpm: 60)
    session.beginComposition(at: start)
    XCTAssertEqual(session.paceCaretFrame(at: start)?.target, .init(word: 0, letter: 1))
    XCTAssertEqual(session.paceCaretFrame(at: start)?.from, .init(word: 0, letter: 0))
    XCTAssertEqual(session.paceCaretFrame(at: start)?.fraction, 0)
  }

  func testExhaustedPaceDoesNotStayPinnedToLastGlyph() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "ab")
    session.configurePace(wpm: 60)
    session.beginComposition(at: start)
    XCTAssertNil(session.paceCaretFrame(at: start.addingTimeInterval(3)))
  }

  func testWrongCommitMovesPaceByTheFullTargetIncludingCommit() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "ab cd efg")
    session.configurePace(wpm: 60)
    session.insertBatch("ax ", at: start)
    let frame = session.paceCaretFrame(at: start.addingTimeInterval(0.2))
    XCTAssertEqual(frame?.target, .init(word: 1, letter: 2))
    XCTAssertEqual(frame.flatMap { session.paceCaretGlyphIndex(for: $0.target) }, 5)
  }

  private func progress(_ words: [String] = ["ab ", "cd ", "efg"], wpm: Double = 60) -> PaceCaretProgress {
    var value = PaceCaretProgress(wpm: wpm, catalog: .init(prompt: "", noSpaceWords: words))!
    value.start(at: start, blind: false)
    return value
  }

  func testWordBoundaryAndHalfStepInterpolationUseAbsoluteDeadlines() throws {
    let value = progress()
    XCTAssertEqual(value.frame(at: start.addingTimeInterval(0.2), blind: false)?.target, .init(word: 0, letter: 2))
    XCTAssertEqual(value.frame(at: start.addingTimeInterval(0.4), blind: false)?.target, .init(word: 1, letter: 0))
    XCTAssertEqual(try XCTUnwrap(value.frame(at: start.addingTimeInterval(0.1), blind: false)).fraction,
      0.5, accuracy: 1e-6)
  }

  func testDuplicateWrongAndCorrectCommitsDoNotMultiplyCorrection() {
    var value = progress()
    value.handleCommit(word: 0, correct: false, blind: false)
    value.handleCommit(word: 0, correct: false, blind: false)
    value.advance(to: start.addingTimeInterval(0.2), blind: false)
    XCTAssertEqual(value.frame(at: start.addingTimeInterval(0.2), blind: false)?.target, .init(word: 1, letter: 2))
    value.handleCommit(word: 0, correct: true, blind: false)
    value.handleCommit(word: 0, correct: true, blind: false)
    XCTAssertEqual(value.frame(at: start.addingTimeInterval(0.4), blind: false)?.target, .init(word: 1, letter: 0))
  }

  func testActualBackspaceAndCorrectResubmissionUndoWrongWordOnce() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "ab cd efg")
    session.configurePace(wpm: 60)
    session.insertBatch("ax ", at: start)
    session.tick(at: start.addingTimeInterval(0.2))
    session.deleteBackward(at: start.addingTimeInterval(0.25))
    session.deleteBackward(at: start.addingTimeInterval(0.25))
    session.insertBatch("b ", at: start.addingTimeInterval(0.3))
    XCTAssertEqual(session.typed, "ab ")
    XCTAssertEqual(session.paceCaretFrame(at: start.addingTimeInterval(0.4))?.target, .init(word: 1, letter: 0))
  }

  func testBlindDefersPendingCorrectionAndDoesNotRecordBlindCommits() {
    var value = progress()
    value.handleCommit(word: 0, correct: false, blind: false)
    value.advance(to: start.addingTimeInterval(0.2), blind: true)
    value.advance(to: start.addingTimeInterval(0.4), blind: true)
    XCTAssertEqual(value.frame(at: start.addingTimeInterval(0.6), blind: false)?.target, .init(word: 2, letter: 1))
    var untracked = progress()
    untracked.handleCommit(word: 0, correct: false, blind: true)
    untracked.handleCommit(word: 0, correct: true, blind: false)
    XCTAssertEqual(untracked.frame(at: start.addingTimeInterval(0.2), blind: false)?.target, .init(word: 0, letter: 2))
  }

  func testUTF16NewlineAndNoSpaceCorrectionLengthsAreNotGlyphCounts() {
    for (words, expected) in [(["😀 ", "x ", "abcd"], PaceCaretPosition(word: 2, letter: 0)),
      (["ab\n", "cd ", "efg"], .init(word: 1, letter: 2)),
      (["ab", "cd", "efg"], .init(word: 1, letter: 1))] {
      var value = progress(words)
      value.handleCommit(word: 0, correct: false, blind: false)
      XCTAssertEqual(value.frame(at: start.addingTimeInterval(0.2), blind: false)?.target, expected)
    }
    let catalog = PaceCaretCatalog(prompt: "😀 ab")
    XCTAssertEqual(catalog.glyphIndex(at: .init(word: 0, letter: 1)), 0)
    XCTAssertEqual(catalog.glyphIndex(at: .init(word: 0, letter: 2)), 1)
  }

  func testLateClockAndFrameReadsDoNotDriftOrConsumePendingCorrection() {
    var value = progress()
    value.handleCommit(word: 0, correct: false, blind: false)
    let date = start.addingTimeInterval(0.25)
    XCTAssertEqual(value.frame(at: date, blind: false), value.frame(at: date, blind: false))
    XCTAssertEqual(value.frame(at: date, blind: false)?.target, .init(word: 1, letter: 2))
    value.advance(to: date, blind: false)
    XCTAssertEqual(value.frame(at: start.addingTimeInterval(0.4), blind: false)?.target, .init(word: 2, letter: 0))
  }

  func testChangingModeMidAttemptReinitializesWithoutRestartingOrRevivingOldSteps() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "ab cd efg")
    session.configurePace(wpm: 60)
    session.insertBatch("a", at: start)
    XCTAssertNotNil(session.paceCaretFrame(at: start))
    session.configurePace(wpm: 120)
    session.insertBatch("b", at: start.addingTimeInterval(0.1))
    session.tick(at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.typed, "ab")
    XCTAssertEqual(session.startedAt, start)
    XCTAssertNil(session.paceCaretFrame(at: start.addingTimeInterval(0.2)))
    var repeated = session.repeatedAttempt()
    repeated.configurePace(wpm: 120)
    repeated.insertBatch("a", at: start.addingTimeInterval(1))
    XCTAssertEqual(repeated.paceCaretFrame(at: start.addingTimeInterval(1))?.target, .init(word: 0, letter: 1))
  }

  func testRejectedLeadingSpaceAndCompletedOrAbandonedAttemptsHaveNoFrame() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "ab cd")
    session.configurePace(wpm: 60)
    session.insertBatch(" ", at: start)
    XCTAssertNil(session.paceCaretFrame(at: start))
    session.insertBatch("a", at: start)
    session.abandon(at: start.addingTimeInterval(1))
    XCTAssertNil(session.paceCaretFrame(at: start.addingTimeInterval(1)))
    var completed = TypingSession(configuration: .timed(seconds: 1), prompt: "ab cd")
    completed.configurePace(wpm: 60)
    completed.insertBatch("a", at: start)
    completed.tick(at: start.addingTimeInterval(1))
    XCTAssertTrue(completed.isFinished)
    XCTAssertNil(completed.paceCaretFrame(at: start.addingTimeInterval(1)))
  }

  func testCatalogGrowthRetainsExistingStepsAndLargeTargetsFastForwardBoundedly() {
    var value = progress(["ab"])
    value.append(" cd")
    XCTAssertEqual(value.frame(at: start.addingTimeInterval(0.4), blind: false)?.target, .init(word: 1, letter: 0))
    let large = progress(Array(repeating: "ab ", count: 20_000), wpm: .greatestFiniteMagnitude)
    XCTAssertNil(large.frame(at: start.addingTimeInterval(1), blind: false))
  }

  func testClockRegressionNeverRewindsTheConsumedStep() {
    var value = progress()
    value.advance(to: start.addingTimeInterval(0.4), blind: false)
    XCTAssertEqual(value.frame(at: start.addingTimeInterval(0.1), blind: false)?.target, .init(word: 1, letter: 0))
  }

  func testInvalidAndDisabledTargetsDoNotCreateAProgressController() {
    for speed in [0, 0.25, -1, .nan, .infinity] {
      XCTAssertNil(PaceCaretProgress(wpm: speed, catalog: .init(prompt: "ab")))
    }
    XCTAssertNil(PaceCaretProgress(wpm: 60, catalog: .init(prompt: "")))
  }

  func testRealNoSpaceAndNewlineNavigationFeedTheSameCorrection() {
    var noSpace = TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil,
      wordLimit: nil, difficulty: .normal, rules: .init(), modifiers: [.noSpaces]),
      customText: "ab cd efg")
    noSpace.configurePace(wpm: 60)
    noSpace.insertBatch("ax", at: start)
    XCTAssertEqual(noSpace.completedWordCount, 1)
    XCTAssertEqual(noSpace.paceCaretFrame(at: start.addingTimeInterval(0.2))?.target, .init(word: 1, letter: 1))
    var newline = TypingSession(configuration: .timed(seconds: 30), prompt: "ab\ncd efg")
    newline.configurePace(wpm: 60)
    newline.insertBatch("ax\n", at: start)
    XCTAssertEqual(newline.paceCaretFrame(at: start.addingTimeInterval(0.2))?.target, .init(word: 1, letter: 2))
  }

  func testStoppedAndAutomaticallyDeletedCommitDoesNotAdjustPace() {
    for rules in [InputRules(stopOnErrorMode: .word), InputRules(deleteOnErrorMode: .letter)] {
      var session = TypingSession(configuration: .timed(seconds: 30, rules: rules), prompt: "ab cd efg")
      session.configurePace(wpm: 60)
      session.insertBatch("ax ", at: start)
      XCTAssertEqual(session.paceCaretFrame(at: start.addingTimeInterval(0.2))?.target, .init(word: 0, letter: 2))
    }
  }

  func testPaceDoesNotAlterSavedResultOrReplayFields() throws {
    var ordinary = TypingSession(configuration: .timed(seconds: 30), prompt: "ab cd efg")
    var paced = ordinary
    paced.configurePace(wpm: 60)
    for text in ["ax ", "cd ", "ef"] {
      ordinary.insertBatch(text, at: start)
      paced.insertBatch(text, at: start)
    }
    ordinary.bailOut(at: start.addingTimeInterval(15))
    paced.bailOut(at: start.addingTimeInterval(15))
    let old = try XCTUnwrap(ordinary.result()), new = try XCTUnwrap(paced.result())
    XCTAssertEqual(new.replayEvents, old.replayEvents)
    XCTAssertEqual(new.characterStats, old.characterStats)
    XCTAssertEqual(new.preciseWpm, old.preciseWpm)
    XCTAssertEqual(new.preciseAccuracy, old.preciseAccuracy)
    XCTAssertNil(paced.paceCaretFrame(at: start.addingTimeInterval(15)))
  }

  func testGlyphEndAnchorsDoNotJumpToTheNextLineOrDisappearOnTheFinalWord() {
    let catalog = PaceCaretCatalog(prompt: "ab\ncd")
    XCTAssertEqual(catalog.glyphAnchor(at: .init(word: 0, letter: 2)), .init(glyphIndex: 1, after: true))
    XCTAssertEqual(catalog.glyphAnchor(at: .init(word: 1, letter: 2)), .init(glyphIndex: 4, after: true))
    XCTAssertNil(catalog.glyphAnchor(at: .init(word: 2, letter: 0)))
  }

  func testNativeInterpolationUsesLinearCornersWidthsAndReducedMotion() {
    let from = CGRect(x: 10, y: 20, width: 12, height: 18)
    let to = CGRect(x: 50, y: 60, width: 20, height: 30)
    XCTAssertEqual(PromptPaceCaretGeometry.rect(from: from, to: to, fromAfter: false, toAfter: false,
      style: .bar, rightToLeft: false, fraction: 0.25, reducesMotion: false),
      CGRect(x: 20, y: 30, width: 14, height: 21))
    XCTAssertEqual(PromptPaceCaretGeometry.rect(from: from, to: to, fromAfter: false, toAfter: false,
      style: .bar, rightToLeft: false, fraction: 0.25, reducesMotion: true), to)
  }

  func testWordEndPlacementRespectsDirectionAndFullWidthGap() {
    let rect = CGRect(x: 10, y: 20, width: 12, height: 18)
    for style in [TypingCaretStyle.bar, .block, .outline, .underline] {
      for rtl in [false, true] {
        let after = PromptPaceCaretGeometry.rect(from: rect, to: rect, fromAfter: true, toAfter: true,
          style: style, rightToLeft: rtl, fraction: 1, reducesMotion: false, afterWidth: 5)
        XCTAssertEqual(after.width, style.usesFullGlyphWidth ? 5 : 12)
        XCTAssertEqual(after.minX, rtl ? (style.usesFullGlyphWidth ? 5 : -2) : 22)
      }
    }
  }

  func testForcedCorrectTextDoesNotBecomeAnUnqualifiedCorrectCommit() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "ab cd efg")
    session.configurePace(wpm: 60)
    session.insertBatch("ab ", forceError: true, at: start)
    XCTAssertEqual(session.paceCaretFrame(at: start.addingTimeInterval(0.2))?.target, .init(word: 1, letter: 2))
  }
}
