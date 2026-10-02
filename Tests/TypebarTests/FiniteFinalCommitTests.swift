import CryptoKit
import Foundation
import XCTest
@testable import Typebar

final class FiniteFinalCommitTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 870_000_000)
  private func attempt(_ source: String, difficulty: Difficulty = .normal,
    rules: InputRules = .init(), modifiers: [TestModifier] = []) -> TypingSession {
    TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: difficulty, rules: rules, customTextCompletion: .finish,
      customTextOrdering: .inOrder, customTextPipeDelimiter: false, modifiers: modifiers),
      customText: LongSavedTextProgress.nextChunk(in: source, after: 0), finiteTextSource: source)
  }

  func testCompleteOwnedNonblankFinalWordDropsItsCommitInEveryDifficulty() {
    for source in ["ab\n", "ab "] {
      for difficulty in Difficulty.allCases {
        var session = attempt(source, difficulty: difficulty, rules: .init(quickEnd: false))
        XCTAssertEqual(session.prompt, "ab")
        session.insertBatch("ab", at: start)
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.typed, "ab")
        XCTAssertEqual(session.errors, 0)
      }
    }
  }

  func testInternalLFIsRequiredButTheFinalNonblankLFIsNot() {
    var session = attempt("seed\nab\n", rules: .init(quickEnd: false))
    XCTAssertEqual(session.prompt, "seed\nab")
    session.insertBatch("seed", at: start)
    XCTAssertEqual(session.outcome, .active)
    session.insertBatch("\nab", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
  }

  func testFinalBlankSlotKeepsItsOnlyRequiredLF() {
    for source in ["\n", "\n\n", "ab\n\n"] {
      var session = attempt(source, rules: .init(quickEnd: false))
      XCTAssertEqual(session.prompt, source)
      session.insertBatch(String(source.dropLast()), at: start)
      XCTAssertEqual(session.outcome, .active)
      session.insert("\n", at: start.addingTimeInterval(1))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
    }
  }

  func testWrongFinalWordProgressUsesTheTrimmedDisplayAndOriginalSourceOffset() {
    for source in ["ab\n", "ab "] {
      var session = attempt(source, rules: .init(quickEnd: false))
      session.insertBatch("ax", at: start)
      XCTAssertEqual(session.outcome, .active)
      session.bailOut(at: start.addingTimeInterval(1))
      XCTAssertEqual(LongSavedTextProgress.advancedOffset(in: source, from: 0, session: session), source.count)
      XCTAssertEqual(session.repeatedAttempt().prompt, "ab")
    }
  }

  func testCompleteFinalChunkTrimsOnlyItsCommitAndDoesNotMutateTheCursorSource() throws {
    let source = String(repeating: "ab\n", count: 3_340)
    var cursor = try XCTUnwrap(CustomFiniteTextStream(source: source))
    let opening = cursor.nextChunk()
    XCTAssertEqual(opening.count, 9_999)
    XCTAssertTrue(cursor.hasRemaining)
    let tail = cursor.nextChunk()
    XCTAssertFalse(cursor.hasRemaining)
    XCTAssertEqual(opening + tail, source)
    var session = attempt(source, rules: .init(quickEnd: false))
    XCTAssertEqual(session.prompt, opening)
    session.insertBatch(opening, at: start)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertTrue(session.prompt == String(source.dropLast()), "仅最终块的非空末词提交被裁去")
    session.insertBatch(String(tail.dropLast()), at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.repeatedAttempt().prompt, opening)
  }

  func testSeparatelySelectedBookChunkHasAFinalWordWithoutChangingItsRawBoundary() {
    let source = String(repeating: "ab\n", count: 3_340)
    let chunk = LongSavedTextProgress.nextChunk(in: source, after: 0)
    var session = attempt(chunk, rules: .init(quickEnd: false))
    XCTAssertTrue(session.prompt == String(chunk.dropLast()), "单独选择的块是一个完整有限练习")
    session.insertBatch(String(chunk.dropLast()), at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(LongSavedTextProgress.offsetAfterCompletingChunk(in: source, from: 0), chunk.count)
    XCTAssertEqual(LongSavedTextProgress.remainingText(in: source, after: chunk.count), String(source.dropFirst(chunk.count)))
  }

  func testNoSpaceTargetsAndUppercaseAreFinalizedAfterTextTransformation() {
    for (modifiers, target) in [([TestModifier.noSpaces], "ab"), ([.uppercase], "AB")] {
      var session = attempt("ab\n", rules: .init(quickEnd: false), modifiers: modifiers)
      XCTAssertEqual(session.prompt, target)
      session.insertBatch(target, at: start)
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.completedWordCount, 1)
      XCTAssertEqual(session.wordReviews.map(\.target), [target])
      XCTAssertEqual(session.errors, 0)
    }
  }

  func testVerifiedScriptNormalizationAlreadyFinishesWithoutChangingItsDigestOrPortablePrompt() throws {
    let source = "seed ab\n"
    let normalized = ReferenceScriptChallengePolicy.normalizedText(source)
    XCTAssertEqual(normalized, "seed ab")
    let digest = SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    let specification = ReferenceScriptChallengePolicy.Specification(legacyName: "owned-eof",
      fileName: "owned-eof.txt", byteCount: source.utf8.count,
      normalizedCharacterCount: normalized.count, normalizedSHA256: digest)
    let verified = try ReferenceScriptChallengePolicy.verifiedScript(Data(source.utf8), for: specification)
    XCTAssertEqual(verified.text, normalized)
    let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(quickEnd: false), customTextCompletion: .finish,
      customTextOrdering: .inOrder, customTextPipeDelimiter: false)
    var session = TestSessionFactory.make(configuration: configuration,
      customText: source, verifiedScript: verified)
    XCTAssertEqual(session.prompt, String(source.dropLast()))
    session.insertBatch(String(source.dropLast()), at: start)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(result.prompt, String(source.dropLast()))
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), result.prompt)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start)).results, [result])
    XCTAssertEqual(verified.text, normalized)
  }

  func testCapturedNoSpaceBlankTargetIsNotConfusedWithThePreviousWordsLetter() {
    // The word list, not the joined prompt, establishes whether the final
    // word is empty. This is a policy-level boundary, not full Funbox proof.
    let batch = TransformedPromptBatch(text: "ab\n", noSpaceTargetWords: ["ab", "\n"])
    let finalized = FinitePromptCommitPolicy.finalized(batch)
    XCTAssertEqual(finalized.text, batch.text)
    XCTAssertEqual(finalized.noSpaceTargetWords, batch.noSpaceTargetWords)
    XCTAssertEqual(finalized.noSpaceWordLengths, [2, 1])
  }
}
