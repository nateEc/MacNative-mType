import XCTest
@testable import Typebar

@MainActor final class WebsitePseudolangTests: XCTestCase {
  private func configuration(_ count: Int = 3) -> TestConfiguration {
    var config = TestConfiguration.words(count).with(modifiers: [.pseudolangStream])
    config.websiteTextAlterationOrder = []
    return config
  }
  private func entropy() -> () -> Double {
    var state: UInt32 = 42
    return { state = state &* 1_664_525 &+ 1_013_904_223; return Double(state) / 4_294_967_296 }
  }

  func testCandidateDrawsCharactersFromOwnedCorpusRatherThanSelectingIndexedWords() {
    var cursor = GeneratedCandidateContinuation(configuration: configuration(), batchTokenCount: 3,
      sourceWords: ["ab", "ac", "ba"])
    var ranks = 0, units = 0
    let chunk = cursor.nextChunk(nextRandomWordIndex: { ranks += 1; return ranks },
      nextRandomContentUnit: { units += 1; return 0 })
    XCTAssertEqual(chunk.source, "ab ab ab")
    XCTAssertEqual(ranks, 0)
    XCTAssertGreaterThan(units, 0)
    XCTAssertEqual(cursor.replayHistory.count, 3)
  }

  func testWebsitePseudolangUsesActualCandidateHistoryInsteadOfFixedSyllables() async throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(
      #"{"mode":"words","words":3,"funbox":["pseudolang"]}"#, pointsPerRem: 16,
      context: .init(authenticated: true))
    var entropy: UInt32 = 42
    let ready = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: .init(),
      random: .init(contentUnit: {
        entropy = entropy &* 1_664_525 &+ 1_013_904_223
        return Double(entropy) / 4_294_967_296
      }))
    XCTAssertEqual(ready.session.generatedWordReplayHistory?.count, 3)
    XCTAssertNotEqual(ready.session.prompt, TypebarStreamContent.prompt(configuration: ready.session.configuration, wordCount: 3))
  }

  func testPinnedGeneratorOnOwnedCorporaIncludingNumericKeysAndUTF16Prefixes() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Word: Decodable { let word: String; let draws: Int }
    struct Fixture: Decodable { let corpus: [String]; let samples: [Double]; let words: [Word] }
    struct LongWord: Decodable { let length, draws: Int }
    struct Output: Decodable { let fixtures: [Fixture]; let longWord: LongWord }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-pseudolang.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures.count, 160)
    for fixture in output.fixtures {
      let model = WebsitePseudolangModel(words: fixture.corpus)
      var draws = 0
      XCTAssertEqual(fixture.words.count, 20)
      for expected in fixture.words {
        let before = draws
        let word = try XCTUnwrap(model.word {
          defer { draws += 1 }; return fixture.samples[draws % fixture.samples.count]
        })
        XCTAssertEqual(Array(word.utf16), Array(expected.word.utf16))
        XCTAssertEqual(draws - before, expected.draws)
      }
    }
    var draws = 0
    let long = try XCTUnwrap(WebsitePseudolangModel(words: ["aaa"]).word {
      draws += 1; return draws < 10000 ? 0 : 0.99
    })
    XCTAssertEqual(long.count, output.longWord.length)
    XCTAssertEqual(draws, output.longWord.draws)
    XCTAssertEqual(long, String(repeating: "a", count: 9999))
  }

  func testInvalidEntropyAndEmptyTrainingDoNotFallBackToOrdinaryWords() {
    let model = WebsitePseudolangModel(words: ["ab", "ac"])
    for invalid in [-1, 1, Double.nan, Double.infinity] {
      XCTAssertNil(model.word(randomUnit: { invalid }))
    }
    XCTAssertNil(WebsitePseudolangModel(words: [String]()).word(randomUnit: { 0 }))
    var cursor = GeneratedCandidateContinuation(configuration: configuration(), batchTokenCount: 3,
      sourceWords: ["ab", "ac"])
    XCTAssertEqual(cursor.nextChunk(nextRandomContentUnit: { .nan }).source, "")
    XCTAssertTrue(cursor.sourceGenerationFailed)
  }

  func testLegacyNativePseudolangRetainsItsIndexedSyllables() {
    let config = TestConfiguration.words(3).with(modifiers: [.pseudolangStream])
    XCTAssertFalse(WebsitePseudolangModel.isSelected(config))
    XCTAssertEqual(TestSessionFactory.make(configuration: config).prompt,
      TypebarStreamContent.prompt(configuration: config, wordCount: 3))
  }

  func testReverseTrainingOrderUsesCharacterDrawsAndZipfCombinationStaysRejected() {
    XCTAssertFalse(WebsiteFunboxAdmission.areCompatible(["pseudolang", "zipf"]))
    var config = configuration(1).with(modifiers: [.pseudolangStream, .backwards])
    config.websiteTextAlterationOrder = [.backwards]
    XCTAssertTrue(WebsitePseudolangModel.isSelected(config))
    var cursor = GeneratedCandidateContinuation(configuration: config, batchTokenCount: 1, sourceWords: ["ab", "ac", "ba"])
    let chunk = cursor.nextChunk(nextRandomWordIndex: { XCTFail("Pseudolang draws characters, not indexes"); return 0 },
      nextRandomContentUnit: { 0 })
    XCTAssertEqual(chunk.source, "ba")
    XCTAssertEqual(chunk.transformed, "ab")
  }

  func testBritishConversionOccursAfterTrainingNotInsideTheCharacterModel() async throws {
    var american = configuration(1); american.language = .english1k
    var british = american; british.englishVariant = .british
    let preparedA = try await WebsitePseudolangModel.preparing(configuration: american)
    let preparedB = try await WebsitePseudolangModel.preparing(configuration: british)
    let a = try XCTUnwrap(preparedA), b = try XCTUnwrap(preparedB)
    let ar = entropy(), br = entropy()
    for _ in 0..<100 { XCTAssertEqual(a.word(randomUnit: ar), b.word(randomUnit: br)) }
    british.language = .english
    var cursor = GeneratedCandidateContinuation(configuration: british, batchTokenCount: 1, sourceWords: ["color"])
    var calls = 0
    XCTAssertEqual(cursor.nextChunk(nextRandomContentUnit: { calls += 1; return 0 }).source, "colour")
    XCTAssertEqual(calls, 6)
  }

  func testTrainingCancellationStopsAtTheNextQuantumWithoutPublishingModel() async {
    var config = configuration(); config.language = .english1k
    var trained = 0
    await Task { @MainActor in
      do {
        _ = try await WebsitePseudolangModel.preparing(configuration: config, didTrain: { count in
          trained = count; withUnsafeCurrentTask { $0?.cancel() }
        })
        XCTFail("Cancelled training returned a model")
      } catch is CancellationError {} catch { XCTFail("Unexpected: \(error)") }
    }.value
    XCTAssertEqual(trained, 128)
  }

  func testWholePreviewAndRepeatedHistoryKeepActualPseudowordsWithoutDrawingAgain() async throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(
      #"{"mode":"words","words":1001,"showAllLines":true,"funbox":["pseudolang"]}"#,
      pointsPerRem: 16, context: .init(authenticated: true))
    let ready = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: .init(),
      random: .init(wordIndex: { XCTFail("No base index draw"); return 0 }, contentUnit: entropy()))
    let history = try XCTUnwrap(ready.session.generatedWordReplayHistory)
    XCTAssertEqual(history.count, 1001)
    let repeated = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: ready.scope,
      attemptSource: .repeatedWords(history, repeatedPace: false),
      random: .init(wordIndex: { XCTFail("No repeated index draw"); return 0 },
        contentUnit: { XCTFail("No repeated character draw"); return 0 }))
    XCTAssertEqual(repeated.session.prompt, ready.session.prompt)
    XCTAssertEqual(repeated.session.generatedWordReplayHistory?.count, 1001)
  }

  func testTimedContinuationRetainsTheModelAndPrefetchedActualTargets() async throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(
      #"{"mode":"time","time":60,"funbox":["pseudolang"]}"#, pointsPerRem: 16,
      context: .init(authenticated: true))
    let ready = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: .init(),
      random: .init(contentUnit: entropy()))
    var session = ready.session
    let opening = try XCTUnwrap(session.generatedWordReplayHistory?.count)
    let first = try XCTUnwrap(session.prompt.split(separator: " ").first)
    session.insertBatch(String(first) + " ")
    XCTAssertEqual(session.outcome, .active)
    let history = try XCTUnwrap(session.generatedWordReplayHistory)
    XCTAssertGreaterThan(history.count, opening)
    let repeated = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: ready.scope,
      attemptSource: .repeatedWords(history, repeatedPace: false),
      random: .init(contentUnit: { XCTFail("Prefetched history must not draw again"); return 0 }))
    XCTAssertEqual(repeated.session.generatedWordReplayHistory?.word(at: history.count - 1)?.target,
      history.word(at: history.count - 1)?.target)
  }
}
