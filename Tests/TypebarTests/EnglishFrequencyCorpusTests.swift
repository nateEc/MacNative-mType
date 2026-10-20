import XCTest
@testable import Typebar

final class EnglishFrequencyCorpusTests: XCTestCase {
  func testEnglishFrequencyChoicesUseRealNestedRankedWordsInPractice() {
    let cases: [(TypingLanguage, Int)] = [(.english1k, 1_000), (.english5k, 5_000), (.english10k, 9_944)]
    var previous: [String] = []
    for (language, count) in cases {
      let words = language.ownedPracticeWords()
      XCTAssertEqual(language.zipfFrequencySupport, .supported)
      XCTAssertEqual(language.speechLocaleIdentifier, "en-US")
      XCTAssertEqual(LivePracticeContentService.wikipediaLanguageCode(for: language), "en")
      XCTAssertEqual(words.count, count)
      XCTAssertEqual(Set(words).count, count)
      XCTAssertEqual(Array(words.prefix(7)), ["the", "to", "and", "of", "a", "in", "I"])
      XCTAssertTrue(Array(words.prefix(previous.count)) == previous, "Smaller choices must be frequency prefixes")
      XCTAssertTrue(words.contains("people"))
      XCTAssertTrue(words.contains("time"))
      let prompt = OfflineContent.generatedPrompt(wordCount: 100, language: language)
      let tokens = prompt.split(separator: " ").map(String.init)
      XCTAssertEqual(tokens.count, 100)
      XCTAssertTrue(tokens.allSatisfy(Set(words).contains), "The real corpus must reach actual offline practice")
      previous = words
    }
  }

  func testChoiceIDsAndConfigurationLinksDoNotChangeWithCorpusCutover() throws {
    for language in [TypingLanguage.english1k, .english5k, .english10k] {
      let configuration = TestConfiguration.words(25, language: language)
      XCTAssertEqual(try JSONDecoder().decode(TestConfiguration.self,
        from: JSONEncoder().encode(configuration)), configuration)
      let preset = SavedTestPreset(configuration: configuration, quoteID: nil, customText: nil)
      XCTAssertEqual(try TestConfigurationShare.preset(from: TestConfigurationShare.link(for: preset)), preset)
      XCTAssertEqual(OfflineContent.quotes(for: language, length: .short).first?.language, language)
    }
  }

  func testRankSamplingReadsTheSelectedDictionaryEntries() {
    let lexicon = TypingLanguage.english10k.ownedPracticeLexicon()
    var index = 0
    let prompt = StarterLexicon.prompt(
      tokens: 3, lexicon: lexicon, separator: " ", punctuation: ["."],
      contentOptions: ContentOptions(), usesZipfFrequency: false, wordRandom: {
        defer { index += 1 }
        return (Double(index) + 0.5) / Double(lexicon.count)
      })
    XCTAssertEqual(prompt, "the to and")
  }

  func testFactoryContinuationAndRepeatKeepTheRealSourceAndCapturedTarget() {
    for language in [TypingLanguage.english1k, .english5k, .english10k] {
      var rank = 0
      var session = TestSessionFactory.make(configuration: .words(0, language: language),
        nextRandomWordIndex: { defer { rank += 1 }; return rank % 1000 })
      let initial = session.prompt
      XCTAssertEqual(Array(initial.split(separator: " ").prefix(3)), ["the", "to", "and"])
      session.insert(initial + " ", at: Date(timeIntervalSince1970: 10))
      XCTAssertEqual(session.completedWordCount, 100)
      XCTAssertGreaterThan(session.prompt.count, initial.count)
      let words = Set(language.ownedPracticeWords().map { $0.lowercased() })
      XCTAssertTrue(session.prompt.split(separator: " ").allSatisfy { words.contains(String($0)) })
      XCTAssertEqual(session.repeatedAttempt().prompt, initial)
    }
  }

  func testActualSessionPreservesTheExistingPunctuationCasePolicy() {
    for language in [TypingLanguage.english1k, .english5k, .english10k] {
      let ordinary = TestSessionFactory.make(configuration: .words(1, language: language),
        nextRandomWordIndex: { 6 })
      XCTAssertEqual(ordinary.prompt, "i")
      let punctuated = TestSessionFactory.make(configuration: .words(1, language: language,
        contentOptions: .init(includePunctuation: true)), nextRandomWordIndex: { 6 },
        nextRandomContentUnit: { XCTFail("A one-word opening should not draw punctuation"); return 0 })
      XCTAssertEqual(punctuated.prompt, "I")
    }
  }

  func testStoredSyntheticPromptAndReplayRemainIndependentOfNewDictionary() throws {
    let prompt = "qambera qbirchb"
    let configuration = TestConfiguration.words(2, language: .english1k)
    let result = CompletedTestResult(
      id: UUID(), configuration: configuration, outcome: .completed,
      startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 5),
      typedCharacterCount: prompt.count, correctCharacterCount: prompt.count,
      errorCount: 0, wpm: 30, rawWpm: 30, accuracy: 100, prompt: prompt,
      replayEvents: [.init(offset: 1, kind: .insert, text: prompt)])
    let restored = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result))
    XCTAssertEqual(restored.prompt, prompt)
    XCTAssertEqual(restored.configuration, configuration)
    XCTAssertEqual(restored.replayEvents, result.replayEvents)
    XCTAssertEqual(TypingReplay.replayTargetFields(prompt: restored.prompt,
      configuration: restored.configuration, targetWordDirectory: nil), ["qambera ", "qbirchb"])
    XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 1), prompt)
    XCTAssertEqual(restored.wpm, result.wpm)
  }
}
