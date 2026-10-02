import Foundation
import SwiftData
import XCTest
@testable import Typebar

final class LongBlankTextProgressTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 850_000_000)
  private let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
    difficulty: .normal, rules: .init(), customTextCompletion: .finish,
    customTextOrdering: .inOrder, customTextPipeDelimiter: false)

  func testExplicitLongLFSourceIsAdmittedWithoutRelaxingOrdinaryOrResourceLimits() {
    let source = String(repeating: "\n", count: 10_001)
    XCTAssertFalse(CustomTextPolicy.isValid(source))
    XCTAssertFalse(CustomTextPolicy.isValidSavedText(title: "Owned", text: source))
    XCTAssertTrue(CustomTextPolicy.isValidSavedText(title: "Owned", text: source, longProgress: 0))
    XCTAssertFalse(CustomTextPolicy.isValidSavedText(title: " ", text: source, longProgress: 0))
    XCTAssertFalse(CustomTextPolicy.isValidSavedText(title: "Owned", text: "  ", longProgress: 0))
    XCTAssertFalse(CustomTextPolicy.isValidSavedText(title: "Owned",
      text: String(repeating: "\n", count: 128_001), longProgress: 0))
    XCTAssertFalse(CustomTextPolicy.isValidSavedText(title: "Owned",
      text: String(repeating: "x", count: 10_001), longProgress: 0))
  }

  func testPureLFChunksReconstructTheWholeSourceAndOnlyWrapAfterTheFinalChunk() {
    let source = String(repeating: "\n", count: 29_999)
    var offset = 0
    var chunks: [String] = []
    while offset < source.count {
      let chunk = LongSavedTextProgress.nextChunk(in: source, after: offset)
      XCTAssertFalse(chunk.isEmpty)
      guard !chunk.isEmpty else { return }
      XCTAssertLessThanOrEqual(chunk.count, 10_000)
      chunks.append(chunk)
      let next = LongSavedTextProgress.offsetAfterCompletingChunk(in: source, from: offset)
      offset += chunk.count
      XCTAssertEqual(next, offset == source.count ? 0 : offset)
    }
    XCTAssertEqual(chunks.map(\.count), [10_000, 10_000, 9_999])
    XCTAssertEqual(chunks.joined(), source)
  }

  func testBlankOpeningAndBlankTailAreNotDiscardedAroundAnOwnedVisibleWord() {
    let opening = String(repeating: "\n", count: 10_000)
    let tail = "ab\n\n"
    let source = opening + tail
    XCTAssertTrue(CustomTextPolicy.isValidSavedText(title: "Owned", text: source, longProgress: 0))
    XCTAssertEqual(LongSavedTextProgress.nextChunk(in: source, after: 0), opening)
    XCTAssertEqual(LongSavedTextProgress.nextChunk(in: source, after: opening.count), tail)
    XCTAssertEqual(LongSavedTextProgress.remainingText(in: source, after: source.count - 1), "\n")
  }

  func testBailoutCreditsOnlyTheMatchedPureLFSlotsIncludingANonzeroResumeOffset() {
    let source = String(repeating: "\n", count: 5)
    for (typed, expected) in [("", 0), ("\n", 1), ("\n\n", 2), ("x", 0), ("\n\nx", 2)] {
      XCTAssertEqual(LongSavedTextProgress.advancedOffset(in: source, from: 0, typed: typed), expected)
    }
    XCTAssertEqual(LongSavedTextProgress.advancedOffset(in: source, from: 2, typed: "\n"), 3)
    XCTAssertEqual(LongSavedTextProgress.advancedOffset(in: source, from: 99, typed: "\n"), 5)
  }

  func testVisibleWordNeedsItsLFAndTheFollowingBlankNeedsASeparateLF() {
    let source = "ab\n\ncd"
    for (typed, expected) in [("ab", 0), ("ab\n", 3), ("ab\n\n", 4),
      ("ab\n\nc", 4), ("ab\n\ncd", 6), ("ab\n\nx", 4)] {
      XCTAssertEqual(LongSavedTextProgress.advancedOffset(in: source, from: 0, typed: typed), expected)
    }
  }

  func testASCIICommitCanRemainImplicitButTABRemainsPartOfTheWord() {
    XCTAssertEqual(LongSavedTextProgress.advancedOffset(in: "amber  bay", from: 0, typed: "amber"), 7)
    XCTAssertEqual(LongSavedTextProgress.advancedOffset(in: "ab\tcd ef", from: 0, typed: "ab\t"), 0)
    XCTAssertEqual(LongSavedTextProgress.advancedOffset(in: "ab\tcd ef", from: 0, typed: "ab\tcd"), 6)
    XCTAssertEqual(LongSavedTextProgress.advancedOffset(in: "ab\tcd\nef", from: 0, typed: "ab\tcd"), 0)
  }

  func testProgressLabelsCountBlankLFSlotsAndNotTABFragments() {
    XCTAssertEqual(LongSavedTextProgress.progressLabel(in: "\n\n\n", offset: 0), "0 / 3 词")
    XCTAssertEqual(LongSavedTextProgress.progressLabel(in: "\n\n\n", offset: 2), "2 / 3 词")
    XCTAssertEqual(LongSavedTextProgress.progressLabel(in: "\n\n\n", offset: 3), "3 / 3 词")
    XCTAssertEqual(LongSavedTextProgress.progressLabel(in: "ab\n\ncd", offset: 3), "1 / 3 词")
    XCTAssertEqual(LongSavedTextProgress.progressLabel(in: "ab\n\ncd", offset: 4), "2 / 3 词")
    XCTAssertEqual(LongSavedTextProgress.progressLabel(in: "ab\tcd ef", offset: 6), "1 / 2 词")
  }

  func testIndependentFiniteCursorCanConsumeAllBlankChunksWithoutFallback() throws {
    let source = String(repeating: "\n", count: 10_001)
    var cursor = try XCTUnwrap(CustomFiniteTextStream(source: source))
    XCTAssertEqual(cursor.nextChunk(), String(repeating: "\n", count: 10_000))
    XCTAssertTrue(cursor.hasRemaining)
    XCTAssertEqual(cursor.nextChunk(), "\n")
    XCTAssertFalse(cursor.hasRemaining)
    XCTAssertEqual(cursor.nextChunk(), "")
  }

  func testResumeRetainsAnLFOnlyTailButWrapsAnEmptyOrASCIIOnlyRemainder() {
    XCTAssertEqual(LongSavedTextProgress.resumingOffset(3, in: "ab\n\n"), 3)
    XCTAssertEqual(LongSavedTextProgress.resumingOffset(4, in: "ab\n\n"), 0)
    XCTAssertEqual(LongSavedTextProgress.resumingOffset(2, in: "ab  "), 0)
    XCTAssertEqual(LongSavedTextProgress.resumingOffset(-1, in: "ab\n"), 0)
    XCTAssertEqual(LongSavedTextProgress.resumingOffset(99, in: "ab\n"), 0)
  }

  func testChunkBoundaryDoesNotTreatAnInteriorTABAsACompletedWord() {
    let first = String(repeating: "a", count: 9_997) + " "
    let source = first + "b\tcd ef"
    XCTAssertEqual(LongSavedTextProgress.nextChunk(in: source, after: 0), first)
    XCTAssertEqual(LongSavedTextProgress.nextChunk(in: source, after: first.count), "b\tcd ef")
  }

  func testContinuousBlankSourceCompletesItsActualFinalTargetAndRepeatsItsInitialSlice() throws {
    let source = String(repeating: "\n", count: 10_001)
    let opening = String(repeating: "\n", count: 10_000)
    var attempt = TestSessionFactory.make(configuration: configuration,
      customText: opening, finiteTextSource: source)
    XCTAssertEqual(attempt.prompt, opening)
    attempt.insertBatch(opening, at: start)
    XCTAssertEqual(attempt.outcome, .active)
    XCTAssertEqual(attempt.completedWordCount, 10_000)
    XCTAssertEqual(attempt.prompt, source)
    XCTAssertEqual(attempt.nextExpectedCharacter, "\n")
    attempt.insert("\n", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 10_001)
    XCTAssertEqual(attempt.typed, source)
    XCTAssertEqual(attempt.errors, 0)
    XCTAssertEqual(attempt.repeatedAttempt().prompt, opening)
    let result = try XCTUnwrap(attempt.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), source)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
  }

  func testBlankSourceBailoutCanResumeOnlyItsMatchedPrefix() throws {
    let source = String(repeating: "\n", count: 10_001)
    var attempt = TestSessionFactory.make(configuration: configuration,
      customText: String(source.prefix(10_000)), finiteTextSource: source)
    attempt.insertBatch(String(repeating: "\n", count: 101), at: start)
    attempt.bailOut(at: start.addingTimeInterval(1))
    XCTAssertEqual(try XCTUnwrap(attempt.result()).outcome, .bailedOut)
    XCTAssertEqual(attempt.completedWordCount, 101)
    let offset = LongSavedTextProgress.advancedOffset(in: source, from: 0, typed: attempt.typed)
    XCTAssertEqual(offset, 101)
    let remainder = LongSavedTextProgress.remainingText(in: source, after: offset)
    XCTAssertEqual(remainder.count, 9_900)
    var resumed = TestSessionFactory.make(configuration: configuration,
      customText: remainder, finiteTextSource: remainder)
    resumed.insertBatch(remainder, at: start)
    XCTAssertEqual(resumed.outcome, .completed)
    XCTAssertEqual(resumed.errors, 0)
  }

  @MainActor
  func testLongBlankProgressSurvivesInMemoryStorageAndFormalArchiveWithoutChangingTheSource() throws {
    let source = String(repeating: "\n", count: 10_001)
    let container = try ModelContainer(for: SavedCustomTextRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let record = SavedCustomTextRecord(title: "Owned blank chapter", text: source, longProgress: 3)
    container.mainContext.insert(record)
    try container.mainContext.save()
    let restored = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<SavedCustomTextRecord>()).first)
    XCTAssertEqual(restored.selection.text, source)
    XCTAssertEqual(restored.selection.longProgress, 3)
    let saved = NamedSavedText(id: restored.id, title: restored.title, text: restored.text, longProgress: 3)
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [], presets: [], savedTexts: [saved], at: start))
    XCTAssertEqual(archive.savedTexts, [saved])
    XCTAssertEqual(TypebarArchiveMerge.savedTextsToInsert(from: archive, existing: []), [saved])
    XCTAssertTrue(TypebarArchiveMerge.savedTextsToInsert(from: archive, existing: [saved]).isEmpty)
    XCTAssertTrue(TypebarArchiveMerge.savedTextsToInsert(from: archive, existing: [], deletedIDs: [record.id]).isEmpty)
  }
}
