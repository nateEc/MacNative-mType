import XCTest
@testable import Typebar

final class PoetrySourceCleaningTests: XCTestCase {
  func testOnlyFirstPoemIsDecodedWithoutValidatingUnconsumedItems() throws {
    for tail in ["null", "42", #"{"lines":4}"#, #"{"title":"Other"}"#] {
      let payload = #"[{"title":"Owned","author":"Fixture","lines":["north south"]},"# + tail + "]"
      let content = try XCTUnwrap(LivePracticeContentService.poetry(from: Data(payload.utf8)))
      XCTAssertEqual(content.text, "north south")
      XCTAssertEqual(content.title, "Owned")
      XCTAssertEqual(content.byline, "Fixture")
    }
  }

  func testInvalidOrEmptyFirstPoemNeverSelectsLaterValidPoem() {
    let later = #"{"title":"Later","author":"Fixture","lines":["ignored"]}"#
    for first in ["null", "42", #"{"lines":4}"#] {
      XCTAssertNil(LivePracticeContentService.poetry(from: Data(("[" + first + "," + later + "]").utf8)))
    }
    let empty = #"[{"title":"Owned","author":"Fixture","lines":["— _"]},"# + later + "]"
    XCTAssertEqual(LivePracticeContentService.poetry(from: Data(empty.utf8))?.text, "")
    XCTAssertNil(LivePracticeContentService.poetry(from: Data(
      #"[{"title":"Owned","author":"Fixture","lines":["north"]}, invalid]"#.utf8)))
  }

  func testSuccessfullyDecodedEmptyPoemRemainsDistinctFromProviderFailure() throws {
    let value = try content(lines: ["— ___ —_", "   "], title: " Empty ", author: " Writer ")
    XCTAssertEqual(value.text, "")
    XCTAssertEqual(value.title, " Empty ")
    XCTAssertEqual(value.byline, " Writer ")
    XCTAssertEqual(value.sectionDescriptor.text, "")
    XCTAssertNil(LivePracticeContentService.poetry(from: Data("[]".utf8)))
    XCTAssertNil(LivePracticeContentService.poetry(from: Data("invalid".utf8)))
  }

  @MainActor func testInitialFillReportsEmptyGenerationWithoutSilentlyFetchingAgain() async throws {
    let empty = LivePracticeContent(source: .poetry, title: "Empty", byline: nil,
      tokens: [], separator: " ")
    let valid = LivePracticeContent(source: .poetry, title: "Owned", byline: nil,
      tokens: ["north", "harbor"], separator: " ")
    let configuration = TestConfiguration.words(4).with(modifiers: [.poetryStream])
    var calls = 0
    let first = await empty.fillingInitialPrompt(for: configuration, showAllLines: true) {
      calls += 1
      return nil
    }
    XCTAssertEqual(first?.text, "")
    XCTAssertEqual(calls, 0, "Initialization owns its bounded reattempt, not the fill helper")
    let later = await valid.fillingInitialPrompt(for: configuration, showAllLines: true) {
      calls += 1
      return empty
    }
    XCTAssertEqual(later?.text, "")
    XCTAssertEqual(calls, 1)
  }

  func testParsedFactorySideSectionPreservesFieldsOversupplyAndRequiresFreshRepeatGeneration() throws {
    let opening = try content(lines: ["north\nsouth"] + (1..<100).map { "owned\($0)" })
    let next = try content(lines: ["third\nfourth tail ignored"])
    let began = Date(timeIntervalSinceReferenceDate: 917_000_000)
    for stop in [StopOnErrorMode.off, .word, .letter] {
      let configuration = TestConfiguration.words(102, rules: .init(stopOnErrorMode: stop))
        .with(modifiers: [.poetryStream])
      var session = TestSessionFactory.make(configuration: configuration,
        streamPrompt: opening.prompt(for: configuration), streamsLiveContent: true)
      XCTAssertTrue(session.appendLiveContent(next.sectionDescriptor))
      XCTAssertTrue(session.prompt.contains("ignored"), "The side caller caps section size, not the remaining global budget")
      XCTAssertFalse(session.needsLiveContentPrefetch)
      let first = stop == .off ? "north\n" : "north\nsouth "
      let last = stop == .off ? "third\ntail" : "third\nfourth tail"
      let openingInput = first + (1..<100).map { "owned\($0) " }.joined()
      let entered = openingInput + last + " ignored"
      session.insertBatch(String(entered.dropLast()), at: began)
      XCTAssertFalse(session.isFinished)
      session.insertBatch("d", at: began.addingTimeInterval(2))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.completedWordCount, 103)
      XCTAssertEqual(session.wordReviews.count, 103)
      if stop != .off { XCTAssertEqual(session.errors, 0) }
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
        through: result.elapsedDuration), entered)
      var repeated = session.repeatedAttempt()
      repeated.insertBatch(openingInput, at: began.addingTimeInterval(5))
      XCTAssertTrue(repeated.needsLiveContentGeneration)
      XCTAssertFalse(repeated.prompt.contains("ignored"), "The side caller did not save generator returns")
      XCTAssertTrue(repeated.acceptGeneratedLiveContent(next.sectionDescriptor))
      repeated.insertBatch(last, at: began.addingTimeInterval(6))
      XCTAssertEqual(repeated.outcome, .completed)
      XCTAssertEqual(repeated.completedWordCount, 102)
    }
  }

  func testFactoryOmitsSpaceAfterLineFeedTerminatedProviderField() throws {
    let value = try content(lines: ["north\n harbor tail"])
    let configuration = TestConfiguration.words(3).with(modifiers: [.poetryStream])
    var session = TestSessionFactory.make(configuration: configuration,
      streamPrompt: value.prompt(for: configuration), streamsLiveContent: true)
    let expected = "north\nharbor tail"
    XCTAssertEqual(session.prompt, expected)
    let began = Date(timeIntervalSinceReferenceDate: 917_000_000)
    session.insertBatch(String(expected.dropLast()), at: began)
    XCTAssertFalse(session.isFinished)
    session.insertBatch("l", at: began.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 3)
    XCTAssertEqual(session.errors, 0)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
      through: result.elapsedDuration), expected)
    var repeated = session.repeatedAttempt()
    repeated.insertBatch(expected, at: began.addingTimeInterval(5))
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(repeated.completedWordCount, 3)
    XCTAssertEqual(repeated.errors, 0)
  }

  func testParsedPoemFactoryRetainsInternalLineFeedCommitRulesAndReplay() throws {
    let value = try content(lines: ["north\nsouth harbor tail"])
    let began = Date(timeIntervalSinceReferenceDate: 917_000_000)
    for stop in [StopOnErrorMode.off, .word, .letter] {
      let configuration = TestConfiguration.words(3, rules: .init(stopOnErrorMode: stop))
        .with(modifiers: [.poetryStream])
      var session = TestSessionFactory.make(configuration: configuration,
        streamPrompt: value.prompt(for: configuration), streamsLiveContent: true)
      session.insertBatch("north\n", at: began)
      XCTAssertEqual(session.completedWordCount, stop == .off ? 1 : 0)
      XCTAssertEqual(session.nextExpectedCharacter, stop == .off ? "h" : "s")
      let suffix = stop == .off ? "harbor tail" : "south harbor tail"
      session.insertBatch(String(suffix.dropLast()), at: began.addingTimeInterval(1))
      XCTAssertFalse(session.isFinished)
      session.insertBatch(String(suffix.suffix(1)), at: began.addingTimeInterval(2))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.completedWordCount, 3)
      let result = session.result()
      XCTAssertNotNil(result)
      XCTAssertEqual(result.map { TypingReplay.typedText(events: $0.replayEvents,
        through: $0.elapsedDuration) }, "north\n" + suffix)
      if stop != .off { XCTAssertEqual(session.errors, 0) }
      var repeated = session.repeatedAttempt()
      repeated.insertBatch("north\n" + suffix, at: began.addingTimeInterval(5))
      XCTAssertEqual(repeated.outcome, .completed)
      XCTAssertEqual(repeated.completedWordCount, 3)
    }
  }

  func testFactoryRetainedTailPreservesProviderFields() {
    let configuration = TestConfiguration.words(4).with(modifiers: [.poetryStream])
    var session = TestSessionFactory.make(configuration: configuration,
      streamPrompt: "north\nsouth harbor",
      streamContinuation: .init(text: "third\nfourth tail", noSpaceBoundarySource: nil),
      streamsLiveContent: true)
    session.insertBatch("north\nharbor third\ntai", at: Date(timeIntervalSinceReferenceDate: 917_000_000))
    XCTAssertFalse(session.isFinished)
    session.insertBatch("l", at: Date(timeIntervalSinceReferenceDate: 917_000_002))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 4)
    var repeated = session.repeatedAttempt()
    repeated.insertBatch("north\nharbor third\ntail", at: Date(timeIntervalSinceReferenceDate: 917_000_005))
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(repeated.completedWordCount, 4)
  }

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
