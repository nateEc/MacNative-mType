import XCTest
@testable import Typebar

final class PoetrySourceCleaningTests: XCTestCase {
  private func content(lines: [String], title: String = "Harbor", author: String = "Writer") throws -> LivePracticeContent {
    let data = try JSONSerialization.data(withJSONObject: [
      ["title": title, "author": author, "lines": lines],
      ["title": "Ignored", "author": "Other", "lines": ["never selected"]]
    ])
    return try XCTUnwrap(LivePracticeContentService.poetry(from: data))
  }

  func testPreservesPunctuationDigitsAndUnicodeWhileRemovingOnlyBannedCharacters() throws {
    let value = try content(lines: ["  Dawn,  2026! can't co-operate —under_score— ", "café… ‘quiet’ – harbor."])
    XCTAssertEqual(value.text, "Dawn, 2026! can't co-operate underscore café… ‘quiet’ – harbor.")
    XCTAssertEqual(value.sectionDescriptor.text, value.text)
    XCTAssertNil(value.sectionDescriptor.noSpaceBoundarySource)
  }

  func testOnlyASCIISpaceSplitsWordsAndEachLineStartsANewWordSequence() throws {
    let value = try content(lines: ["left\tright next\u{00A0}word", "joined\ninside", "tail"])
    XCTAssertEqual(value.text, "left\tright next\u{00A0}word joined\ninside tail")
  }

  func testLimitCountsCleanedNonemptyWordsAcrossAllLines() throws {
    let words = (1...105).map { "word\($0)!" }
    let value = try content(lines: ["— ___ —_", words.prefix(60).joined(separator: "  "),
      "__ —", words.dropFirst(60).joined(separator: " ")])
    XCTAssertEqual(value.text, words.prefix(100).joined(separator: " "))
    XCTAssertFalse(value.text.contains("word101!"))
  }

  func testEmbeddedTabsAndNonbreakingSpacesRemainContentThroughSessionAndReplay() throws {
    let value = try content(lines: ["left\tright next\u{00A0}word tail"])
    let configuration = TestConfiguration.words(3).with(modifiers: [.poetryStream])
    let expected = "left\tright next\u{00A0}word tail"
    var session = TestSessionFactory.make(configuration: configuration,
      streamPrompt: value.prompt(for: configuration))
    XCTAssertEqual(session.prompt, expected)
    let began = Date(timeIntervalSinceReferenceDate: 917_000_000)
    session.insertBatch(String(expected.dropLast()), at: began)
    XCTAssertFalse(session.isFinished)
    session.insertBatch(String(expected.suffix(1)), at: began.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 3)
    XCTAssertEqual(session.errors, 0)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
      through: result.elapsedDuration), expected)
    var repeated = session.repeatedAttempt()
    XCTAssertEqual(repeated.prompt, expected)
    repeated.insertBatch(expected, at: began.addingTimeInterval(5))
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(repeated.completedWordCount, 3)
    XCTAssertEqual(repeated.errors, 0)
  }

  func testSourceTitleAndAuthorAreNotTypographyNormalizedOrTrimmed() throws {
    let value = try content(lines: ["one"], title: "  Harbor —  ", author: " Writer ")
    XCTAssertEqual(value.title, "  Harbor —  ")
    XCTAssertEqual(value.byline, " Writer ")
  }

  func testParsedPoemCompletesThroughProductionSessionAndRetainsExactReplay() throws {
    let value = try content(lines: ["Dawn, 2026! can't co-operate —under_score—"])
    let configuration = TestConfiguration.words(5).with(modifiers: [.poetryStream])
    var session = TestSessionFactory.make(configuration: configuration,
      streamPrompt: value.prompt(for: configuration))
    let expected = "Dawn, 2026! can't co-operate underscore"
    XCTAssertEqual(session.prompt, expected)
    let began = Date(timeIntervalSinceReferenceDate: 917_000_000)
    session.insertBatch(String(expected.dropLast()), at: began)
    XCTAssertFalse(session.isFinished)
    session.insertBatch(String(expected.suffix(1)), at: began.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 5)
    XCTAssertEqual(session.errors, 0)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
      through: result.elapsedDuration), expected)
    XCTAssertEqual(session.repeatedAttempt().prompt, expected)
  }
}
