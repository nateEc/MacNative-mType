import XCTest
@testable import Typebar

final class ShowAllLinesGenerationTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

  private func binary(_ index: Int) -> String {
    let value = String(index % 256, radix: 2)
    return String(repeating: "0", count: 8 - value.count) + value
  }

  func testFiniteWordPreviewIsNotTruncatedAtTheNativeFiveHundredWordCap() {
    let config = TestConfiguration.words(701).with(modifiers: [.binaryStream])
    let session = TestSessionFactory.make(configuration: config, showAllLines: true)
    XCTAssertEqual(session.prompt, (0..<701).map(binary).joined(separator: " "))
    XCTAssertEqual(session.prompt.split(separator: " ").count, 701)
    XCTAssertEqual(GeneratedPromptChunkPolicy.wordCount(for: config, showAllLines: true), 701)
  }

  func testWholePreviewOmitsOnlyTheRealFinalUnderscoreAndPreservesTheResult() throws {
    let config = TestConfiguration.words(701).with(modifiers: [.binaryStream, .underscoreSeparators])
    var session = TestSessionFactory.make(configuration: config, showAllLines: true)
    let target = (0..<701).map { binary($0) + ($0 == 700 ? "" : "_") }.joined()
    XCTAssertEqual(session.prompt, target)
    session.insertBatch(String(target.dropLast()), at: start)
    XCTAssertFalse(session.isFinished)
    session.insertBatch(String(target.suffix(1)), at: start.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 701)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.wordReviews.count, 701)
    XCTAssertEqual(session.wordReviews.last?.target, binary(700))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 2), target)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from:
      TypebarDataTransfer.exportArchive(settings: .init(), results: [result], presets: [], at: start)).results,
      [result])
  }

  func testOrdinaryWordSourcePreviewsTheWholeFiniteBudget() {
    let config = TestConfiguration.words(701)
    let session = TestSessionFactory.make(configuration: config, showAllLines: true)
    XCTAssertEqual(session.prompt.split(separator: " ").count, 701)
    XCTAssertEqual(session.configuration, config, "呈现选项不新增计分配置字段")
  }

  func testLongQuoteUsesItsWholeWordCountForTheAlterationBound() {
    let source = (0..<101).map { "w\($0)" }.joined(separator: " ")
    let quote = OfflineQuote(id: "authored-whole-quote", title: "Probe", text: source,
      language: .english, length: .long)
    let config = TestConfiguration(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.underscoreSeparators])
    var session = TestSessionFactory.make(configuration: config, quote: quote, showAllLines: true)
    let target = (0..<101).map { "w\($0)" + ($0 == 100 ? "" : "_") }.joined()
    XCTAssertEqual(session.prompt, target)
    session.insertBatch(target, at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 101)
    XCTAssertEqual(session.errors, 0)
  }

  func testCodePreviewIncludesAllWordsInItsOpeningInsteadOfOnlyOneHundred() {
    let plain = TestConfiguration.words(101, language: .codeSwift)
    var source = GeneratedCodeContinuation(configuration: plain, batchTokenCount: 100)
    var words: [String] = []
    while source.hasRemaining { words += source.nextChunk(nextRandomWordIndex: { 0 }).source.split(whereSeparator: \.isWhitespace).map(String.init) }
    let session = TestSessionFactory.make(configuration: plain.with(modifiers: [.underscoreSeparators]),
      showAllLines: true, nextRandomWordIndex: { 0 })
    let target = words.enumerated().map { $0.element + ($0.offset == 100 ? "" : "_") }.joined()
    XCTAssertEqual(session.prompt, target)
  }

  func testInfiniteWordPreviewKeepsTheReferenceHundredWordOpening() {
    let config = TestConfiguration.words(0).with(modifiers: [.binaryStream, .underscoreSeparators])
    var session = TestSessionFactory.make(configuration: config, showAllLines: true)
    let opening = (0..<100).map { binary($0) + ($0 == 99 ? "" : "_") }.joined()
    XCTAssertEqual(session.prompt, opening)
    session.insertBatch(opening, at: start)
    XCTAssertFalse(session.isFinished)
    XCTAssertEqual(session.completedWordCount, 100)
    XCTAssertEqual(session.prompt, opening + (100..<200).map { binary($0) + "_" }.joined())
  }

  func testGenerationBoundsRespectOverridesRatherThanTheDisplayHeight() {
    XCTAssertEqual(GeneratedWordBoundPolicy.bound(for: .words(701), wordOffset: 0,
      sourceWordCount: 701, showAllLines: true), 701)
    let quote = TestConfiguration(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init())
    XCTAssertEqual(GeneratedWordBoundPolicy.bound(for: quote, wordOffset: 0,
      sourceWordCount: 151, showAllLines: true), 151)
    let custom = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextPipeDelimiter: false)
    XCTAssertEqual(GeneratedWordBoundPolicy.bound(for: custom, wordOffset: 0,
      sourceWordCount: 151, showAllLines: true), 100)
    XCTAssertEqual(GeneratedWordBoundPolicy.bound(for: .words(0), wordOffset: 0,
      sourceWordCount: 100, showAllLines: true), 100)
    XCTAssertEqual(GeneratedWordBoundPolicy.bound(for: .timed(seconds: 120), wordOffset: 0,
      sourceWordCount: 500, showAllLines: true), 100)
  }

  func testTimedCustomLineDisplayStillSupportsAllGeneratedLines() {
    XCTAssertTrue(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .off, testMode: .custom, hasTimeLimit: true))
    XCTAssertFalse(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .off, testMode: .time, hasTimeLimit: true))
  }

  @MainActor
  private func withSettings(_ body: (AppSettings) -> Void) throws {
    let suiteName = "TypebarTests.WholeLineSettings.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    body(AppSettings(defaults: defaults))
  }

  @MainActor
  func testTapeModeRejectsTheEnableCommandWithoutChangingTheExistingSetting() throws {
    try withSettings { settings in
      settings.practiceTapeMode = .letter
      settings.showAllPracticeLines = false
      XCTAssertFalse(AppearanceCommandTarget.showAllLines(true).apply(to: settings))
      XCTAssertFalse(settings.showAllPracticeLines)
      XCTAssertEqual(settings.practiceTapeMode, .letter)
      XCTAssertTrue(AppearanceCommandTarget.showAllLines(false).apply(to: settings))
    }
  }

  @MainActor
  func testEnablingTapeDisablesWholeLinesAndTurningTapeOffDoesNotReenableThem() throws {
    try withSettings { settings in
      settings.showAllPracticeLines = true
      XCTAssertTrue(AppearanceCommandTarget.tape(.word).apply(to: settings))
      XCTAssertFalse(settings.showAllPracticeLines)
      XCTAssertTrue(AppearanceCommandTarget.tape(.off).apply(to: settings))
      XCTAssertFalse(settings.showAllPracticeLines)
      XCTAssertTrue(AppearanceCommandTarget.showAllLines(true).apply(to: settings))
      XCTAssertTrue(settings.showAllPracticeLines)
    }
  }

  func testOversizeWholePreviewKeepsTheOriginalPlayableBudgetWithAnExplicitNotice() throws {
    for limit in [100_001, OfficialTestLimitInput.maximumValue] {
      let config = TestConfiguration.words(limit).with(modifiers: [.binaryStream])
      let session = TestSessionFactory.make(configuration: config, showAllLines: true)
      XCTAssertEqual(session.configuration, config)
      XCTAssertEqual(session.prompt.split(separator: " ").count, 100)
      XCTAssertTrue(try XCTUnwrap(session.generationNotice).contains("分批"))
      XCTAssertEqual(session.repeatedAttempt().generationNotice, session.generationNotice)
      XCTAssertFalse(session.isFinished)
      XCTAssertEqual(try JSONDecoder().decode(TestConfiguration.self,
        from: JSONEncoder().encode(session.configuration)), config)
    }
  }

  func testHundredThousandWordWholePreviewIsActuallyGeneratedWithoutTypingOrGUI() {
    let config = TestConfiguration.words(100_000).with(modifiers: [.binaryStream])
    let session = TestSessionFactory.make(configuration: config, showAllLines: true)
    XCTAssertEqual(session.prompt.split(separator: " ").count, 100_000)
    XCTAssertTrue(session.prompt.hasSuffix(binary(99_999)))
    XCTAssertNil(session.generationNotice)
    XCTAssertEqual(session.configuration, config)
    XCTAssertFalse(session.hasStarted)
    XCTAssertTrue(session.repeatedAttempt().prompt == session.prompt)
  }

  func testDisabledPreviewAndTimedModeKeepTheirExistingBoundedGeneration() {
    let finite = TestConfiguration.words(701).with(modifiers: [.binaryStream])
    let session = TestSessionFactory.make(configuration: finite, showAllLines: false)
    XCTAssertEqual(session.prompt.split(separator: " ").count, 100)
    XCTAssertNil(session.generationNotice)
    let timed = TestConfiguration.timed(seconds: 120).with(modifiers: [.binaryStream])
    XCTAssertEqual(TestSessionFactory.make(configuration: timed, showAllLines: true).prompt,
      TestSessionFactory.make(configuration: timed, showAllLines: false).prompt)
  }

  func testCustomCompletionOverridesTheFullPreviewRequest() {
    let source = (0..<151).map { "w\($0)" }.joined(separator: " ")
    let config = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextPipeDelimiter: false,
      modifiers: [.underscoreSeparators])
    let enabled = TestSessionFactory.make(configuration: config, customText: source, showAllLines: true)
    let disabled = TestSessionFactory.make(configuration: config, customText: source, showAllLines: false)
    XCTAssertEqual(enabled.prompt, disabled.prompt)
    XCTAssertNil(enabled.generationNotice)
  }

  @MainActor
  func testSettingChangePreservesTheRunningPromptAndOnlyAffectsTheNextAttempt() throws {
    try withSettings { settings in
      let config = TestConfiguration.words(701).with(modifiers: [.binaryStream, .underscoreSeparators])
      var running = TestSessionFactory.make(configuration: config, showAllLines: settings.showAllPracticeLines)
      running.insertBatch(binary(0) + "_", at: start)
      let prompt = running.prompt
      let typed = running.typed
      XCTAssertTrue(AppearanceCommandTarget.showAllLines(true).apply(to: settings))
      XCTAssertFalse(AppearanceCommandTarget.showAllLines(true).requiresRestart)
      XCTAssertEqual(running.prompt, prompt)
      XCTAssertEqual(running.typed, typed)
      XCTAssertEqual(running.completedWordCount, 1)
      let next = TestSessionFactory.make(configuration: config, showAllLines: settings.showAllPracticeLines)
      XCTAssertNotEqual(next.prompt, prompt)
      XCTAssertEqual(next.configuration, running.configuration)
      XCTAssertTrue(next.repeatedAttempt().prompt == next.prompt)
    }
  }

  func testEveryNativeCodeLanguagePreviewsItsWholeFiniteTarget() {
    let languages = TypingLanguage.allCases.filter(\.isCodeLanguage)
    XCTAssertEqual(languages.count, 70)
    for language in languages {
      let config = TestConfiguration.words(101, language: language)
      var source = GeneratedCodeContinuation(configuration: config, batchTokenCount: 100)
      var words: [String] = []
      while source.hasRemaining {
        words += source.nextChunk(nextRandomWordIndex: { 0 }).source.split(whereSeparator: \.isWhitespace).map(String.init)
      }
      XCTAssertEqual(words.count, 101, language.rawValue)
      let target = words.enumerated().map { $0.element + ($0.offset == 100 ? "" : "_") }.joined()
      let preview = TestSessionFactory.make(configuration: config.with(modifiers: [.underscoreSeparators]),
        showAllLines: true, nextRandomWordIndex: { 0 })
      XCTAssertEqual(preview.prompt, target, language.rawValue)
      XCTAssertNil(preview.generationNotice, language.rawValue)
    }
  }

  func testIncompleteExternalPreviewPreservesPlayableContinuationAndDisclosesTheGap() throws {
    let source = "probe cue mark"
    for modifiers: [TestModifier] in [[.underscoreSeparators], [.noSpaces]] {
      for limit in [4, 25, 501] {
        let config = TestConfiguration.words(limit).with(modifiers: modifiers)
        var session = TestSessionFactory.make(configuration: config, streamPrompt: source, showAllLines: true)
        XCTAssertNotNil(session.generationNotice)
        XCTAssertEqual(session.configuration, config)
        let opening = session.prompt
        session.insertBatch(opening, at: start)
        XCTAssertFalse(session.isFinished)
        XCTAssertGreaterThan(session.prompt.count, opening.count)
        for attempt in 1...170 where !session.isFinished {
          let remainder = String(session.prompt.dropFirst(session.typed.count))
          guard !remainder.isEmpty else { break }
          // This probes physical typing, not one composition crossing the
          // budget: the pinned input handler finishes only on the final
          // character of a multi-character input event.
          for character in remainder where !session.isFinished {
            session.insertBatch(String(character), at: start.addingTimeInterval(Double(attempt)))
          }
        }
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.completedWordCount, limit)
        XCTAssertEqual(session.errors, 0)
        if session.isFinished {
          let result = try XCTUnwrap(session.result())
          XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
        }
      }
    }
  }

  func testCompleteExternalSourceKeepsItsWholeGenerationBoundWithoutWarning() {
    let source = (0..<501).map(binary).joined(separator: " ")
    let config = TestConfiguration.words(501).with(modifiers: [.underscoreSeparators])
    let session = TestSessionFactory.make(configuration: config, streamPrompt: source, showAllLines: true)
    XCTAssertEqual(session.prompt, (0..<501).map { binary($0) + ($0 == 500 ? "" : "_") }.joined())
    XCTAssertNil(session.generationNotice)
  }
}
