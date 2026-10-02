import Foundation
import CryptoKit
import XCTest

@testable import Typebar

final class CustomFiniteStreamingTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  func testUserOwnedLongTextStreamsInOneFiniteAttemptWithoutEarlyCompletion() {
    let source = String(repeating: "amber  harbor\n", count: 800) + "final word"
    XCTAssertGreaterThan(source.count, CustomTextPolicy.maximumLength)
    let first = LongSavedTextProgress.nextChunk(in: source, after: 0)
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .finish)
    var session = TestSessionFactory.make(
      configuration: configuration, customText: first, finiteTextSource: source)
    XCTAssertEqual(session.prompt, first)
    session.insert(first, at: start)
    XCTAssertFalse(session.isFinished)
    XCTAssertGreaterThan(session.prompt.count, first.count)
    session.insert(String(source.dropFirst(first.count)), at: start)
    XCTAssertEqual(session.result()?.outcome, .completed)
    XCTAssertEqual(session.prompt, source)
  }

  func testFiniteLongTextRepeatStartsAgainFromTheBeginning() {
    let source = String(repeating: "amber harbor ", count: 800) + "end"
    let first = LongSavedTextProgress.nextChunk(in: source, after: 0)
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .finish)
    var session = TestSessionFactory.make(
      configuration: configuration, customText: first, finiteTextSource: source)
    session.insert(first, at: start)
    var repeated = session.repeatedAttempt()
    XCTAssertEqual(repeated.prompt, first)
    XCTAssertFalse(repeated.isFinished)
    repeated.insert(first, at: start)
    XCTAssertFalse(repeated.isFinished)
    XCTAssertGreaterThan(repeated.prompt.count, first.count)
  }

  func testOrdinaryCustomFiniteTextCollapsesRepeatedASCIISpacesBeforeTyping() {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .finish)
    var session = TestSessionFactory.make(
      configuration: configuration, customText: "amber  harbor")
    XCTAssertEqual(session.prompt, "amber harbor")
    session.insert("amber harbor", at: start)
    XCTAssertEqual(session.typed, "amber harbor")
    XCTAssertEqual(session.completedWordCount, 2)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.result()?.outcome, .completed)
  }

  func testIncorrectLeadingSpaceIsStillIgnored() {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .finish)
    var session = TestSessionFactory.make(configuration: configuration, customText: "amber harbor")
    session.insert(" amber", at: start)
    XCTAssertEqual(session.typed, "amber")
    XCTAssertFalse(session.isFinished)
  }

  func testLongFiniteTextBailoutAdvancesOnlyThroughCompletedWords() {
    let source = String(repeating: "amber harbor ", count: 800) + "end"
    let first = LongSavedTextProgress.nextChunk(in: source, after: 0)
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .finish)
    var session = TestSessionFactory.make(
      configuration: configuration, customText: first, finiteTextSource: source)
    session.insert(first + "amber har", at: start)
    XCTAssertFalse(session.isFinished)
    session.bailOut(at: start)
    XCTAssertEqual(session.result()?.outcome, .bailedOut)
    let offset = LongSavedTextProgress.advancedOffset(in: source, from: 0, typed: session.typed)
    XCTAssertEqual(offset, first.count + "amber ".count)
  }

  func testLegacyRemainderStartingWithWhitespaceStillStreamsToTheEnd() {
    let source = "  " + String(repeating: "amber harbor ", count: 800) + "end"
    let first = LongSavedTextProgress.nextChunk(in: source, after: 0)
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .finish)
    var session = TestSessionFactory.make(
      configuration: configuration, customText: first, finiteTextSource: source)
    session.insert(first, at: start)
    XCTAssertFalse(session.isFinished)
    XCTAssertGreaterThan(session.prompt.count, first.count)
    session.insert(String(source.dropFirst(first.count)), at: start)
    XCTAssertEqual(session.prompt, source)
    XCTAssertEqual(session.result()?.outcome, .completed)
  }

  func testVerifiedReferenceScriptStreamsBeyondSavedTextLimitInOneAttempt() throws {
    let source = String(repeating: "amber harbor ", count: 46_200) + "end"
    XCTAssertGreaterThan(source.count, 600_000)
    XCTAssertNil(CustomFiniteTextStream(source: source))
    let digest = SHA256.hash(data: Data(source.utf8))
      .map { String(format: "%02x", $0) }.joined()
    let specification = ReferenceScriptChallengePolicy.Specification(
      legacyName: "synthetic", fileName: "synthetic.txt", byteCount: source.utf8.count,
      normalizedCharacterCount: source.count, normalizedSHA256: digest)
    let verified = try ReferenceScriptChallengePolicy.verifiedScript(
      Data(source.utf8), for: specification)
    let first = LongSavedTextProgress.nextChunk(in: source, after: 0)
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .finish)
    var session = TestSessionFactory.make(
      configuration: configuration, customText: first, verifiedScript: verified)
    XCTAssertEqual(session.prompt, first)
    session.insert(first, at: start)
    XCTAssertFalse(session.isFinished)
    session.insert(String(source.dropFirst(first.count)), at: start.addingTimeInterval(1))
    let completed = try XCTUnwrap(session.result())
    XCTAssertEqual(completed.outcome, .completed)
    XCTAssertEqual(session.prompt, source)
    let restored = try XCTUnwrap(TestResultRecord(result: completed).portableResult)
    XCTAssertEqual(restored.prompt, source)
    XCTAssertEqual(restored.outcome, .completed)
  }
}
