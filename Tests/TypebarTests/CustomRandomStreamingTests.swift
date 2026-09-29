import Foundation
import XCTest

@testable import Typebar

final class CustomRandomStreamingTests: XCTestCase {
  private let source = "amber harbor quiet lake"
  private let start = Date(timeIntervalSince1970: 100)

  func testTimedRandomCustomTextDrawsFreshWordsAfterInitialChunk() {
    let configuration = TestConfiguration(
      mode: .custom, duration: 120, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .time, customTextOrdering: .random)
    var session = TestSessionFactory.make(configuration: configuration, customText: source)
    let initial = session.prompt
    XCTAssertEqual(initial.split(separator: " ").count, 64)
    XCTAssertTrue(session.usesIncrementalPromptExtension)

    session.insert(initial + " ", at: start)
    let words = session.prompt.split(separator: " ").map(String.init)
    XCTAssertGreaterThanOrEqual(words.count, 128)
    XCTAssertNotEqual(Array(words[..<64]), Array(words[64..<128]))
    for index in 64..<128 {
      XCTAssertNotEqual(words[index], words[index - 1])
      XCTAssertNotEqual(words[index], words[index - 2])
    }
    let secondChunk = Array(words[64..<128]).joined(separator: " ")
    session.insert(secondChunk + " ", at: start.addingTimeInterval(1))
    let extendedWords = session.prompt.split(separator: " ").map(String.init)
    XCTAssertGreaterThanOrEqual(extendedWords.count, 192)
    for index in 128..<192 {
      XCTAssertNotEqual(extendedWords[index], extendedWords[index - 1])
      XCTAssertNotEqual(extendedWords[index], extendedWords[index - 2])
    }
    XCTAssertFalse(session.isFinished)
    let restarted = session.repeatedAttempt()
    XCTAssertEqual(restarted.prompt, initial)
    XCTAssertTrue(restarted.usesIncrementalPromptExtension)
  }

  func testInfiniteRandomCustomWordsKeepExtendingWithoutCycling() {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: 0, difficulty: .normal,
      rules: .init(), customTextCompletion: .words, customTextOrdering: .random)
    var session = TestSessionFactory.make(configuration: configuration, customText: source)
    let initial = session.prompt
    XCTAssertEqual(initial.split(separator: " ").count, 64)
    session.insert(initial + " ", at: start)
    XCTAssertGreaterThan(session.prompt.split(separator: " ").count, 64)
    XCTAssertFalse(session.isFinished)
  }

  func testTimedRandomCustomTextKeepsInitialChunkBoundedForLargeSource() {
    let configuration = TestConfiguration(
      mode: .custom, duration: 120, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .time, customTextOrdering: .random)
    let largeSource = (0..<80).map { "word\($0)" }.joined(separator: " ")
    let session = TestSessionFactory.make(configuration: configuration, customText: largeSource)
    XCTAssertEqual(session.prompt.split(separator: " ").count, 64)
  }

  func testRandomCustomStreamPreservesNoSpaceWordBoundaries() {
    let configuration = TestConfiguration(
      mode: .custom, duration: 120, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .time, customTextOrdering: .random)
      .with(modifiers: [.noSpaces])
    var session = TestSessionFactory.make(configuration: configuration, customText: source)
    let initial = session.prompt
    XCTAssertFalse(initial.contains(" "))
    session.insert(initial, at: start)
    XCTAssertEqual(session.typed.count, initial.count)
    XCTAssertEqual(session.typed, initial)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertGreaterThan(session.prompt.count, initial.count)
    XCTAssertEqual(session.completedWordCount, 64)
    let secondChunk = String(session.prompt.dropFirst(initial.count))
    session.insert(secondChunk, at: start.addingTimeInterval(1))
    XCTAssertEqual(session.completedWordCount, 128)
    XCTAssertGreaterThan(session.prompt.count, initial.count + secondChunk.count)
    XCTAssertFalse(session.isFinished)
  }

  func testLargeFiniteRandomCustomWordsStreamInsteadOfAllocatingWholeTarget() {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: 1_001, difficulty: .normal,
      rules: .init(), customTextCompletion: .words, customTextOrdering: .random)
    var session = TestSessionFactory.make(configuration: configuration, customText: source)
    let initial = session.prompt
    XCTAssertEqual(initial.split(separator: " ").count, 64)
    session.insert(initial + " ", at: start)
    XCTAssertGreaterThan(session.prompt.split(separator: " ").count, 64)
    XCTAssertFalse(session.isFinished)
  }
}
