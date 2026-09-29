import Foundation
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

  func testCustomFiniteTextAcceptsWhitespacePresentInItsExactTarget() {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .finish)
    var session = TestSessionFactory.make(
      configuration: configuration, customText: "amber  harbor")
    session.insert("amber  harbor", at: start)
    XCTAssertEqual(session.typed, "amber  harbor")
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
}
