import XCTest
@testable import Typebar

final class CustomSectionStreamTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  private func configuration(_ limit: Int, language: TypingLanguage = .english,
    ordering: CustomTextOrdering = .inOrder, rules: InputRules = .init(),
    modifiers: [TestModifier] = []) -> TestConfiguration {
    .init(mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal,
      rules: rules, language: language, customTextCompletion: .sections,
      customTextSectionLimit: limit, customTextOrdering: ordering, modifiers: modifiers)
  }

  func testEveryCodeChoiceKeepsACommitBetweenCustomSections() {
    for language in TypingLanguage.allCases.filter(\.isCodeLanguage) {
      var session = TestSessionFactory.make(configuration: configuration(2, language: language),
        customText: "let vessel | seed()")
      XCTAssertEqual(session.prompt, "let vessel seed()", language.displayName)
      session.insertBatch("let vessel seed()", at: start)
      XCTAssertEqual(session.outcome, .completed, language.displayName)
      XCTAssertEqual(session.errors, 0, language.displayName)
    }
  }

  func testFiniteSectionLimitCanRepeatBeyondTheSourcePool() {
    var session = TestSessionFactory.make(configuration: configuration(5),
      customText: "amber harbor | bay cedar")
    let target = "amber harbor bay cedar amber harbor bay cedar amber harbor"
    XCTAssertEqual(session.prompt, target)
    XCTAssertEqual(session.sectionProgress?.total, 5)
    session.insertBatch("amber harbor ", at: start)
    XCTAssertEqual(session.sectionProgress?.completed, 1)
    session.insertBatch("bay cedar amber harbor bay cedar amber harbor", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.sectionProgress?.completed, 5)
    XCTAssertEqual(session.typed, target)
  }

  func testALargeSectionIsBoundedTo100WordsThenContinuesWithoutTruncation() {
    let words = (0..<140).map { "item\($0)" }
    let source = words.joined(separator: " ") + " | cabin"
    let target = words.joined(separator: " ") + " cabin"
    var session = TestSessionFactory.make(configuration: configuration(2), customText: source)
    XCTAssertEqual(session.prompt, words.prefix(100).joined(separator: " ") + " ")
    XCTAssertTrue(session.usesIncrementalPromptExtension)
    session.insertBatch(words.prefix(100).joined(separator: " ") + " ", at: start)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.sectionProgress?.completed, 0)
    session.insertBatch(words.dropFirst(100).joined(separator: " ") + " cabin",
      at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.prompt, target)
    XCTAssertEqual(session.typed, target)
    XCTAssertEqual(session.sectionProgress?.completed, 2)
  }

  func testRepeatedAttemptRestoresTheSectionRemainderAndOriginalBoundaries() {
    let words = (0..<120).map { "token\($0)" }
    var session = TestSessionFactory.make(configuration: configuration(3),
      customText: words.joined(separator: " ") + " | bay")
    let opening = session.prompt
    session.insertBatch(words.joined(separator: " ") + " bay ", at: start)
    XCTAssertFalse(session.isFinished)
    XCTAssertGreaterThan(session.prompt.count, opening.count)
    var repeated = session.repeatedAttempt()
    XCTAssertEqual(repeated.prompt, opening)
    XCTAssertEqual(repeated.sectionProgress?.completed, 0)
    XCTAssertEqual(repeated.sectionProgress?.total, 3)
    XCTAssertFalse(repeated.hasStarted)
    repeated.insertBatch(words.joined(separator: " ") + " bay " + words.joined(separator: " "), at: start)
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(repeated.sectionProgress?.completed, 3)
  }

  func testZeroSectionLimitIsInfiniteWithCountProgressAndExplicitBailout() throws {
    let config = configuration(0)
    XCTAssertTrue(config.isInfinite)
    var session = TestSessionFactory.make(configuration: config, customText: "amber harbor | bay cedar")
    XCTAssertEqual(session.prompt.split(whereSeparator: \.isWhitespace).count, 100)
    XCTAssertTrue(session.usesIncrementalPromptExtension)
    session.insertBatch(String(repeating: "amber harbor bay cedar ", count: 50), at: start)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.sectionProgress?.completed, 100)
    XCTAssertEqual(session.sectionProgress?.total, 0)
    XCTAssertEqual(session.progressText(at: start), "100")
    XCTAssertEqual(session.progressFraction(at: start), 0)
    session.bailOut(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .bailedOut)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), session.typed)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
  }

  func testShufflingKeepsWholeSectionsAndConsumesEachPoolOncePerCycle() {
    let session = TestSessionFactory.make(configuration: configuration(6, ordering: .shuffled),
      customText: "amber one | bay two | cedar three")
    let words = session.prompt.split(separator: " ").map(String.init)
    XCTAssertEqual(words.count, 12)
    guard words.count == 12 else { return }
    let sections = stride(from: 0, to: words.count, by: 2).map { words[$0] + " " + words[$0 + 1] }
    XCTAssertEqual(Set(sections.prefix(3)), ["amber one", "bay two", "cedar three"])
    XCTAssertEqual(Set(sections.suffix(3)), ["amber one", "bay two", "cedar three"])
  }

  func testRandomDrawsKeepSectionContentsTogetherAndRespectTheRequestedCount() {
    let session = TestSessionFactory.make(configuration: configuration(12, ordering: .random),
      customText: "amber one | bay two | cedar three")
    let words = session.prompt.split(separator: " ").map(String.init)
    XCTAssertEqual(words.count, 24)
    guard words.count == 24 else { return }
    for index in stride(from: 0, to: words.count, by: 2) {
      XCTAssertTrue(["amber one", "bay two", "cedar three"].contains(words[index] + " " + words[index + 1]))
    }
  }

  func testNoSpaceSectionsKeepHiddenWordAndSectionBoundariesAcrossChunks() {
    let words = (0..<120).map { "item\($0)" }
    var session = TestSessionFactory.make(configuration: configuration(2, language: .codeSwift,
      modifiers: [.noSpaces]), customText: words.joined(separator: " ") + " | bay")
    XCTAssertEqual(session.prompt, words.prefix(100).joined())
    session.insertBatch(words.joined(), at: start)
    XCTAssertEqual(session.sectionProgress?.completed, 1)
    XCTAssertEqual(session.completedWordCount, 120)
    XCTAssertFalse(session.isFinished)
    session.insertBatch("bay", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.sectionProgress?.completed, 2)
    XCTAssertEqual(session.wordReviews.count, 121)
  }

  func testAnExistingNewlineCommitsTheSectionWithoutAnInsertedSpace() {
    var session = TestSessionFactory.make(configuration: configuration(2, language: .codeSwift),
      customText: "amber\n|bay")
    XCTAssertEqual(session.prompt, "amber\nbay")
    session.insertBatch("amber\nbay", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
  }

  func testUnicodeLengthChangingModifiersKeepSectionProgressAttachedToRealCommits() {
    var session = TestSessionFactory.make(configuration: configuration(3, language: .codeSwift,
      modifiers: [.uppercase]), customText: "straße | bay")
    XCTAssertEqual(session.prompt, "STRASSE BAY STRASSE")
    session.insertBatch("STRASSE", at: start)
    XCTAssertEqual(session.sectionProgress?.completed, 0)
    session.insertBatch(" ", at: start.addingTimeInterval(0.1))
    XCTAssertEqual(session.sectionProgress?.completed, 1)
    session.insertBatch("BAY STRASSE", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.sectionProgress?.completed, 3)
  }

  func testQuickEndCannotFinishAtAPartialSectionChunk() {
    let words = (0..<120).map { "token\($0)" }
    var session = TestSessionFactory.make(configuration: configuration(1, rules: .init(quickEnd: true)),
      customText: words.joined(separator: " "))
    session.insertBatch(words.prefix(99).joined(separator: " ") + " xxxxxxx", at: start)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertTrue(session.usesIncrementalPromptExtension)
  }

  func testIncorrectFinalSectionStaysEditableAndWordStopDoesNotAdvanceProgress() {
    var session = TestSessionFactory.make(configuration: configuration(2, language: .codeSwift,
      rules: .init(stopOnErrorMode: .word, quickEnd: true)), customText: "seed | ab")
    session.insertBatch("seed xx ", at: start)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.typed, "seed xx ")
    XCTAssertEqual(session.sectionProgress?.completed, 1)
    session.deleteWordBackward(at: start.addingTimeInterval(0.1))
    XCTAssertEqual(session.typed, "seed ")
    session.insertBatch("ab", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.sectionProgress?.completed, 2)
  }

  func testSectionConfigurationLinksKeepZeroAndLimitsLargerThanTheSourcePool() throws {
    for limit in [0, 5, OfficialTestLimitInput.maximumValue] {
      let preset = SavedTestPreset(configuration: configuration(limit, language: .codeSwift,
        ordering: .shuffled), customText: "abc | bay")
      XCTAssertEqual(try TestConfigurationShare.preset(from: TestConfigurationShare.link(for: preset)), preset)
      let encoded = try JSONEncoder().encode(preset.configuration)
      XCTAssertEqual(try JSONDecoder().decode(TestConfiguration.self, from: encoded), preset.configuration)
    }
  }

  func testRandomSectionsAvoidThePreviousTwoWholeSectionsWithFourCandidates() throws {
    var stream = try XCTUnwrap(CustomSectionWordStream(source: "amber one | bay two | cedar three | dune four",
      configuration: configuration(3, ordering: .random)))
    var draws = [0, 0, 1, 0, 1, 2].makeIterator()
    let chunk = stream.nextChunk(random: { draws.next()! })
    XCTAssertEqual(chunk.text, "amber one bay two cedar three")
    XCTAssertEqual(chunk.sectionEndOffsets, [10, 18, 29])
    XCTAssertFalse(stream.hasRemaining)
  }

  func testRandomSectionsBoundRetriesForDuplicatesAndDoNotRetryTinyPools() throws {
    for (source, expectedDraws) in [("bay | bay | bay | bay", 102), ("bay | bay | bay", 2)] {
      var stream = try XCTUnwrap(CustomSectionWordStream(source: source,
        configuration: configuration(2, ordering: .random)))
      var count = 0
      let chunk = stream.nextChunk(random: { count += 1; return 0 })
      XCTAssertEqual(chunk.text, "bay bay")
      XCTAssertEqual(count, expectedDraws)
    }
  }

  func testShuffledSectionsConsumeDuplicateSourcePositionsInsteadOfDeduplicating() throws {
    var stream = try XCTUnwrap(CustomSectionWordStream(source: "bay | bay | cedar",
      configuration: configuration(6, ordering: .shuffled)))
    let chunk = stream.nextChunk(random: { 0 })
    let words = chunk.text.split(separator: " ").map(String.init)
    XCTAssertEqual(words.count, 6)
    XCTAssertEqual(words.prefix(3).filter { $0 == "bay" }.count, 2)
    XCTAssertEqual(words.suffix(3).filter { $0 == "bay" }.count, 2)
  }

  func testRandomAndShuffledRepeatPreserveFutureGenerationAcrossChunks() {
    for ordering in [CustomTextOrdering.random, .shuffled] {
      var original = TestSessionFactory.make(configuration: configuration(240, ordering: ordering),
        customText: "amber one | bay two | cedar three | dune four")
      var repeated = original.repeatedAttempt()
      for _ in 0..<3 {
        XCTAssertEqual(original.prompt, repeated.prompt)
        let nextInput = String(original.prompt.dropFirst(original.typed.count))
        original.insertBatch(nextInput, at: start)
        repeated.insertBatch(nextInput, at: start)
        XCTAssertEqual(original.sectionProgress?.completed, repeated.sectionProgress?.completed)
        // At a batch-ending commit, the next real key requests the next
        // chunk. Correct this synthetic wrong key before consuming it.
        original.insertBatch("!", at: start)
        repeated.insertBatch("!", at: start)
        original.deleteBackward(at: start)
        repeated.deleteBackward(at: start)
      }
      XCTAssertGreaterThan(original.prompt.split(separator: " ").count, 100)
      XCTAssertEqual(original.prompt, repeated.prompt)
      XCTAssertFalse(original.isFinished)
    }
  }

  func testMaximumSectionLimitDoesNotExpandAllSectionsIntoTheInitialPrompt() {
    let session = TestSessionFactory.make(configuration: configuration(OfficialTestLimitInput.maximumValue),
      customText: "bay | cedar")
    XCTAssertEqual(session.prompt.split(separator: " ").count, 100)
    XCTAssertEqual(session.sectionProgress?.total, OfficialTestLimitInput.maximumValue)
    XCTAssertTrue(session.usesIncrementalPromptExtension)
  }

  func testSectionSettingsAndArchiveKeepZeroAndLargeLimitsWithoutNewSchema() throws {
    for limit in [0, 5, OfficialTestLimitInput.maximumValue] {
      let preset = SavedTestPreset(configuration: configuration(limit, ordering: .shuffled),
        customText: "bay | cedar")
      let memory = TypebarTestParameterMemory(duration: 30, wordLimit: 25,
        customTextDuration: 30, customTextWordLimit: 25, customTextSectionLimit: limit)
      let settings = AppSettingsSnapshot()
      let json = try SettingsJSONCommandCodec.export(settings: settings,
        configuration: preset.configuration, layoutFluidLayouts: [.ansiQwerty], testParameterMemory: memory)
      let decoded = try SettingsJSONCommandCodec.decode(json)
      XCTAssertEqual(decoded.configuration, preset.configuration)
      XCTAssertEqual(decoded.testParameterMemory, memory)
      let selection = ActiveTestSelectionDocument(preset: preset, quoteSource: .community,
        testParameterMemory: memory)
      let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
        settings: settings, results: [], presets: [], activeTestSelection: selection, at: start))
      XCTAssertEqual(archive.activeTestSelection, selection)
      XCTAssertEqual(archive.version, TypebarArchive.currentVersion)
    }
  }

  func testInfiniteSectionsRequireShiftForQuickRestartLikeOtherInfiniteLimits() {
    XCTAssertTrue(QuickRestartSafetyPolicy.requiresShift(for: configuration(0)))
    XCTAssertFalse(QuickRestartSafetyPolicy.requiresShift(for: configuration(999)))
    XCTAssertTrue(QuickRestartSafetyPolicy.requiresShift(for: configuration(1_000)))
    XCTAssertTrue(CommandBailoutPolicy.isAvailable(for: configuration(0)))
    XCTAssertFalse(CommandBailoutPolicy.isAvailable(for: configuration(4_999)))
    XCTAssertTrue(CommandBailoutPolicy.isAvailable(for: configuration(5_000)))
  }

  func testModeOnlyLegacyLinksDoNotClampCurrentOrFallbackSectionLimits() throws {
    let link = "https://share.example.test/practice?testSettings=NoIgxgrgzgLg9gWxAGgHYQDYbZ76s4H566EYC6QA"
    for limit in [0, 5, OfficialTestLimitInput.maximumValue] {
      let current = SavedTestPreset(configuration: configuration(limit), customText: "bay | cedar")
      let retained = try LegacyTestSettingsLinkImporter.preset(from: link, current: current)
      XCTAssertEqual(retained.configuration.customTextSectionLimit, limit)
      let fallback = LegacyTestSettingsLinkImporter.CustomTextFallback(text: "bay | cedar",
        completion: .sections, duration: nil, wordLimit: nil, sectionLimit: limit, ordering: .shuffled)
      let imported = try LegacyTestSettingsLinkImporter.preset(from: link,
        current: .init(configuration: .words(25)), customTextFallback: fallback)
      XCTAssertEqual(imported.configuration.customTextSectionLimit, limit)
      XCTAssertEqual(imported.configuration.customTextOrdering, .shuffled)
    }
  }

  func testBackwardsTransformsEachSectionWordBeforeAppendingItsCommit() {
    for modifiers in [[TestModifier.backwards], [.backwards, .noSpaces]] {
      let separator = modifiers.contains(.noSpaces) ? "" : " "
      var session = TestSessionFactory.make(configuration: configuration(2, modifiers: modifiers),
        customText: "amber bay | cedar")
      let target = ["radec", "rebma", "yab"].joined(separator: separator)
      XCTAssertEqual(session.prompt, target)
      session.insertBatch(target, at: start)
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(session.sectionProgress?.completed, 2)
    }
  }
}
