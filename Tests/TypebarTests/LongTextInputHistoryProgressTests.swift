import Foundation
import SwiftData
import XCTest
@testable import Typebar

final class LongTextInputHistoryProgressTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 860_000_000)
  private func attempt(_ source: String, rules: InputRules = .init(), difficulty: Difficulty = .normal,
    modifiers: [TestModifier] = []) -> TypingSession {
    TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: difficulty, rules: rules, customTextCompletion: .finish,
      customTextOrdering: .inOrder, customTextPipeDelimiter: false, modifiers: modifiers),
      customText: source, finiteTextSource: source)
  }
  private func progress(_ source: String, _ session: TypingSession, offset: Int = 0) -> Int {
    LongSavedTextProgress.advancedOffset(in: source, from: offset, session: session)
  }

  func testWrongFullActiveWordCountsByItsInputLengthNotItsSpelling() {
    let source = "ab cd ef"
    var session = attempt(source)
    session.insertBatch("ax", at: start)
    XCTAssertEqual(session.completedWordCount, 0)
    XCTAssertEqual(progress(source, session), 3)
    session.bailOut(at: start.addingTimeInterval(1))
    XCTAssertEqual(progress(source, session), 3)
  }

  func testShortFinalFieldIsExcludedButEarlierWrongCommittedFieldStillCounts() {
    let source = "amber bay elm"
    var session = attempt(source)
    session.insertBatch("x ", at: start)
    XCTAssertEqual(progress(source, session), 0)
    session.insertBatch("b", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(progress(source, session), 6)
    session.insertBatch("ay", at: start.addingTimeInterval(2))
    XCTAssertEqual(progress(source, session), 10)
  }

  func testRecordedASCIICommitBelongsToTheLastFieldsLength() {
    let source = "abc def ghi"
    var session = attempt(source)
    session.insertBatch("ab ", at: start)
    XCTAssertEqual(session.typed, "ab ")
    XCTAssertEqual(progress(source, session), 4)
  }

  func testWrongFieldWithRequiredLFDoesNotCountUntilItsDisplayLengthIsReached() {
    let source = "ab\ncd ef"
    var session = attempt(source)
    session.insertBatch("ax", at: start)
    XCTAssertEqual(progress(source, session), 0)
    session.insert("\n", at: start.addingTimeInterval(1))
    XCTAssertEqual(progress(source, session), 3)
  }

  func testStrictRetainedLFMayCompleteOneFieldButNotInventTwoNavigations() {
    let source = "\n\n\n\n"
    var session = attempt(source, rules: .init(strictSpace: true))
    session.insert("\n", at: start)
    XCTAssertEqual(session.completedWordCount, 0)
    XCTAssertEqual(progress(source, session), 1)
    session.insert("\n", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(progress(source, session), 1)
    session.insert("\n", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(progress(source, session), 2)
  }

  func testDeletingRetainedLFUsesTheUpdatedFieldInsteadOfTheRawPrefix() {
    let source = "\n\n\n\n"
    var session = attempt(source, rules: .init(strictSpace: true, freedomMode: true))
    session.insertBatch("\n\n\n", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "\n\n")
    XCTAssertEqual(progress(source, session), 1)
  }

  func testWordStopSpacesStayInOneFieldEvenWhenTheyLookLikeCommits() {
    let source = "ab cd ef"
    var session = attempt(source, rules: .init(stopOnErrorMode: .word))
    session.insertBatch("ax  cd", at: start)
    XCTAssertEqual(session.completedWordCount, 0)
    XCTAssertEqual(progress(source, session), 3)
    XCTAssertEqual(session.result(), nil)
  }

  func testDeletedFutureFieldRemainsInTheAttemptedHistoryWithAnEmptyLastValue() {
    let source = "ab cd ef gh"
    var session = attempt(source, rules: .init(freedomMode: true))
    session.insertBatch("ax cd e", at: start)
    session.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "ax cd ")
    XCTAssertEqual(progress(source, session), 6)
    session.deleteWordBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(session.typed, "ax ")
    XCTAssertEqual(progress(source, session), 6, "历史只扣去最后一个不足显示长度的字段，不能改成当前词游标规则")
  }

  func testAutomaticWordDeletionLeavesAnEmptyFieldRatherThanCreditingTheFailedText() {
    let source = "ab cd ef"
    var session = attempt(source, rules: .init(deleteOnErrorMode: .word))
    session.insertBatch("ax", at: start)
    XCTAssertEqual(session.typed, "")
    XCTAssertEqual(progress(source, session), 0)
    session.insertBatch("ab cd", at: start.addingTimeInterval(1))
    XCTAssertEqual(progress(source, session), 6)
  }

  func testUTF16LengthsNotNativeGraphemeLengthsDetermineTheLastField() {
    let source = "ab cd"
    var session = attempt(source)
    session.insert("🙂", at: start)
    XCTAssertEqual(session.typed.count, 1)
    XCTAssertEqual(progress(source, session), 3)
    let emojiSource = "🙂 cd"
    var emoji = attempt(emojiSource)
    emoji.insert("x", at: start)
    XCTAssertEqual(progress(emojiSource, emoji), 0)
    emoji.insert("x", at: start.addingTimeInterval(1))
    XCTAssertEqual(progress(emojiSource, emoji), 2)
  }

  func testFullWrongMasterFieldCountsAlthoughTheTerminalOutcomeIsFailure() {
    let source = "ab cd ef"
    var session = attempt(source, difficulty: .master)
    session.insertBatch("ax", at: start)
    XCTAssertEqual(session.outcome, .failed)
    XCTAssertEqual(progress(source, session), 3)
  }

  func testNonzeroOriginalOffsetAndInternalTABKeepTheirSourceUnits() {
    let source = "seed ab\tcd ef"
    var session = attempt("ab\tcd ef")
    session.insertBatch("ax\tcd", at: start)
    XCTAssertEqual(progress(source, session, offset: 5), 11)
    XCTAssertEqual(LongSavedTextProgress.remainingText(in: source, after: 11), "ef")
  }

  func testBailedOutContinuousLFSourceDoesNotChangeItsResultReplayOrTheRepeatedHistory() throws {
    let source = String(repeating: "\n", count: 10_001)
    let config = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextCompletion: .finish,
      customTextOrdering: .inOrder, customTextPipeDelimiter: false)
    var session = TestSessionFactory.make(configuration: config,
      customText: String(source.prefix(10_000)), finiteTextSource: source)
    session.insertBatch(String(source.prefix(101)), at: start)
    session.bailOut(at: start.addingTimeInterval(1))
    XCTAssertEqual(progress(source, session), 101)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), session.typed)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start)).results, [result])
    XCTAssertEqual(progress(source, session.repeatedAttempt()), 0)
  }

  func testFailedLastASCIICommitDoesNotPadAShortFieldToItsDisplayLength() {
    let source = "ab cd"
    var session = attempt(source, difficulty: .expert)
    session.insertBatch("ab x ", at: start)
    XCTAssertEqual(session.outcome, .failed)
    XCTAssertEqual(progress(source, session), 3)
  }

  func testDeletionRemovesOneBMPUnitFromGraphemeBuiltBySeparateEvents() {
    let source = "ab cd"
    var session = attempt(source)
    session.insert("e", at: start)
    session.insert("\u{0301}", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed.count, 1)
    XCTAssertEqual(progress(source, session), 3)
    session.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(session.typed, "e")
    XCTAssertEqual(progress(source, session), 0)
    session.deleteBackward(at: start.addingTimeInterval(3))
    XCTAssertEqual(session.typed, "")
    XCTAssertEqual(progress(source, session), 0)
    // Genuine missing-unit legacy events retain their whole-grapheme delete.
    let legacy: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, text: "e"),
      .init(offset: 1, kind: .insert, text: "\u{301}"), .init(offset: 2, kind: .delete, text: "")]
    XCTAssertEqual(TypingReplay.typedText(events: legacy, through: 2), "")
  }

  func testNoSpaceInputUsesItsSavedWordTargetsInsteadOfOneFlattenedField() {
    let source = "ab cd ef"
    var session = attempt(source, modifiers: [.noSpaces])
    XCTAssertEqual(session.prompt, "abcdef")
    session.insertBatch("axc", at: start)
    XCTAssertEqual(progress(source, session), 3)
    session.insert("d", at: start.addingTimeInterval(1))
    XCTAssertEqual(progress(source, session), 6)
  }

  func testUnderscoreSuffixIsRequiredInTheTransformedDisplayLength() {
    let source = "ab cd ef"
    var session = attempt(source, modifiers: [.underscoreSeparators])
    XCTAssertEqual(session.prompt, "ab_cd_ef")
    session.insertBatch("ax", at: start)
    XCTAssertEqual(progress(source, session), 0)
    session.insert("_", at: start.addingTimeInterval(1))
    XCTAssertEqual(progress(source, session), 3)
  }

  func testNoSpaceDeletionRetainsTheAttemptedEmptyFutureField() {
    let source = "ab cd ef gh"
    var session = attempt(source, rules: .init(freedomMode: true), modifiers: [.noSpaces])
    session.insertBatch("axcde", at: start)
    for step in 1...3 { session.deleteBackward(at: start.addingTimeInterval(Double(step))) }
    XCTAssertEqual(session.typed, "ax")
    XCTAssertEqual(progress(source, session), 6)
  }

  func testDeletionMayRemoveOnlyPartOfAnEarlierFlagInsertionEvent() {
    let source = "abcd ef"
    var session = attempt(source)
    session.insert("\u{1F1FA}", at: start)
    session.insert("🇨🇦", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed.utf16.count, 6)
    session.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(session.typed.utf16.count, 5)
    XCTAssertEqual(progress(source, session), 5)
    session.deleteBackward(at: start.addingTimeInterval(3))
    XCTAssertEqual(session.typed, "🇺🇨")
    XCTAssertEqual(progress(source, session), 5)
    for remaining in stride(from: 3, through: 0, by: -1) {
      session.deleteBackward(at: start.addingTimeInterval(Double(7 - remaining)))
      XCTAssertEqual(session.typed.utf16.count, remaining)
      XCTAssertEqual(progress(source, session), 0)
    }
    XCTAssertEqual(progress(source, session), 0)
    var legacy: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, text: "\u{1F1FA}"),
      .init(offset: 1, kind: .insert, text: "🇨🇦"), .init(offset: 2, kind: .delete, text: "")]
    XCTAssertEqual(TypingReplay.typedText(events: legacy, through: 2), "🇺🇨")
    legacy.append(.init(offset: 3, kind: .delete, text: ""))
    XCTAssertEqual(TypingReplay.typedText(events: legacy, through: 3), "")
    XCTAssertEqual(SavedTextInputHistoryPolicy.progressWordCount(displays: ["abcd", "ef"], events: legacy), 0)
  }

  func testIncorrectFinalCommitProjectionTrimUsesECMAScriptWhitespaceNotFoundationNEL() {
    // Policy-level raw snapshots, not a claim that insertion guards preserve
    // these scalars: native input maps NBSP/BOM to ASCII space before replay.
    for (scalar, expected) in [("\u{0085}", 2), ("\u{00A0}", 1), ("\u{FEFF}", 1)] {
      let events = ("ab xx" + scalar + " ").map {
        TypingReplayEvent(offset: 0, kind: .insert, text: String($0))
      }
      XCTAssertEqual(SavedTextInputHistoryPolicy.progressWordCount(
        displays: ["ab", "xyz"], events: events), expected)
    }
  }

  @MainActor
  func testWrongWordOffsetRoundTripsWithoutRewritingOldProgressOrResults() throws {
    let source = "ab cd ef"
    var session = attempt(source)
    session.insertBatch("ax", at: start)
    session.bailOut(at: start.addingTimeInterval(1))
    let offset = progress(source, session)
    XCTAssertEqual(offset, 3)
    let result = try XCTUnwrap(session.result())
    let container = try ModelContainer(for: SavedCustomTextRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let old = SavedCustomTextRecord(title: "Unchanged older offset", text: source, longProgress: 1)
    let new = SavedCustomTextRecord(title: "Owned history exercise", text: source, longProgress: offset)
    container.mainContext.insert(old)
    container.mainContext.insert(new)
    try container.mainContext.save()
    let records = try container.mainContext.fetch(FetchDescriptor<SavedCustomTextRecord>())
    XCTAssertEqual(records.first(where: { $0.id == old.id })?.longProgress, 1)
    XCTAssertEqual(records.first(where: { $0.id == new.id })?.text, source)
    XCTAssertEqual(records.first(where: { $0.id == new.id })?.longProgress, 3)
    let saved = NamedSavedText(id: new.id, title: new.title, text: source, longProgress: offset)
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], savedTexts: [saved], at: start))
    XCTAssertEqual(archive.savedTexts, [saved])
    XCTAssertEqual(archive.results, [result])
    XCTAssertTrue(TypebarArchiveMerge.savedTextsToInsert(from: archive, existing: [saved]).isEmpty)
    XCTAssertTrue(TypebarArchiveMerge.savedTextsToInsert(from: archive, existing: [], deletedIDs: [new.id]).isEmpty)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), "ax")
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
  }

  func testContinuousProgressProjectsEveryFieldAcrossTheTenThousandCharacterChunk() {
    let source = String(repeating: "\n", count: 10_001)
    var session = attempt(source)
    session.insertBatch(String(source.prefix(10_000)), at: start)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(progress(source, session), 10_000)
    session.insert("\n", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(progress(source, session), source.count)
    XCTAssertEqual(progress(source, session.repeatedAttempt()), 0)
  }
}
