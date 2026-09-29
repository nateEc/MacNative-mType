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
    XCTAssertEqual(initial.split(separator: " ").count, 100)
    XCTAssertTrue(session.usesIncrementalPromptExtension)

    session.insert(initial + " ", at: start)
    let words = session.prompt.split(separator: " ").map(String.init)
    XCTAssertGreaterThanOrEqual(words.count, 200)
    XCTAssertNotEqual(Array(words[..<100]), Array(words[100..<200]))
    for index in 100..<200 {
      XCTAssertNotEqual(words[index], words[index - 1])
      XCTAssertNotEqual(words[index], words[index - 2])
    }
    let secondChunk = Array(words[100..<200]).joined(separator: " ")
    session.insert(secondChunk + " ", at: start.addingTimeInterval(1))
    let extendedWords = session.prompt.split(separator: " ").map(String.init)
    XCTAssertGreaterThanOrEqual(extendedWords.count, 300)
    for index in 200..<300 {
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
    XCTAssertEqual(initial.split(separator: " ").count, 100)
    session.insert(initial + " ", at: start)
    XCTAssertGreaterThan(session.prompt.split(separator: " ").count, 100)
    XCTAssertFalse(session.isFinished)
  }

  func testTimedRandomCustomTextKeepsInitialChunkBoundedForLargeSource() {
    let configuration = TestConfiguration(
      mode: .custom, duration: 120, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .time, customTextOrdering: .random)
    let largeSource = (0..<150).map { "word\($0)" }.joined(separator: " ")
    let session = TestSessionFactory.make(configuration: configuration, customText: largeSource)
    XCTAssertEqual(session.prompt.split(separator: " ").count, 100)
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
    XCTAssertEqual(session.completedWordCount, 100)
    let secondChunk = String(session.prompt.dropFirst(initial.count))
    session.insert(secondChunk, at: start.addingTimeInterval(1))
    XCTAssertEqual(session.completedWordCount, 200)
    XCTAssertGreaterThan(session.prompt.count, initial.count + secondChunk.count)
    XCTAssertFalse(session.isFinished)
  }

  func testLargeFiniteRandomCustomWordsStreamInsteadOfAllocatingWholeTarget() {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: 1_001, difficulty: .normal,
      rules: .init(), customTextCompletion: .words, customTextOrdering: .random)
    var session = TestSessionFactory.make(configuration: configuration, customText: source)
    let initial = session.prompt
    XCTAssertEqual(initial.split(separator: " ").count, 100)
    session.insert(initial + " ", at: start)
    XCTAssertGreaterThan(session.prompt.split(separator: " ").count, 100)
    XCTAssertFalse(session.isFinished)
  }

  func testReferenceSizedRandomBatchesStreamAfterOneHundredWords() {
    let timed = TestConfiguration(
      mode: .custom, duration: 120, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .time, customTextOrdering: .random)
    let timedSession = TestSessionFactory.make(configuration: timed, customText: source)
    XCTAssertEqual(timedSession.prompt.split(separator: " ").count, 100)

    let finite = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: 101, difficulty: .normal,
      rules: .init(), customTextCompletion: .words, customTextOrdering: .random)
    var finiteSession = TestSessionFactory.make(configuration: finite, customText: source)
    XCTAssertEqual(finiteSession.prompt.split(separator: " ").count, 100)
    XCTAssertTrue(finiteSession.usesIncrementalPromptExtension)
    let firstBatch = finiteSession.prompt
    finiteSession.insert(firstBatch + " ", at: start)
    XCTAssertGreaterThan(finiteSession.prompt.count, firstBatch.count)
    XCTAssertEqual(finiteSession.completedWordCount, 100)
    XCTAssertFalse(finiteSession.isFinished)
    let finalWord = finiteSession.prompt.dropFirst(firstBatch.count)
      .split(separator: " ").first.map(String.init)
    XCTAssertNotNil(finalWord)
    finiteSession.insert(finalWord ?? "", at: start.addingTimeInterval(1))
    XCTAssertEqual(finiteSession.result()?.outcome, .completed)
    XCTAssertEqual(finiteSession.completedWordCount, 101)
  }

  func testCodeLanguageCustomRandomStreamRetainsSpaceBetweenBatches() {
    let configuration = TestConfiguration(
      mode: .custom, duration: 120, wordLimit: nil, difficulty: .normal,
      rules: .init(), language: .codeSwift,
      customTextCompletion: .time, customTextOrdering: .random)
    var session = TestSessionFactory.make(configuration: configuration, customText: source)
    let firstBatch = session.prompt
    XCTAssertTrue(firstBatch.contains(" "))
    session.insert(firstBatch, at: start)
    XCTAssertGreaterThan(session.prompt.count, firstBatch.count)
    XCTAssertEqual(session.prompt.dropFirst(firstBatch.count).first, " ")
  }

  func testCodeLanguageCustomRepeatRetainsSpaceBetweenBatches() {
    let configuration = TestConfiguration(
      mode: .custom, duration: 120, wordLimit: nil, difficulty: .normal,
      rules: .init(), language: .codeSwift,
      customTextCompletion: .time, customTextOrdering: .inOrder)
    var session = TestSessionFactory.make(configuration: configuration, customText: source)
    let firstBatch = session.prompt
    session.insert(firstBatch, at: start)
    XCTAssertGreaterThan(session.prompt.count, firstBatch.count)
    XCTAssertEqual(session.prompt.dropFirst(firstBatch.count).first, " ")
  }
}
