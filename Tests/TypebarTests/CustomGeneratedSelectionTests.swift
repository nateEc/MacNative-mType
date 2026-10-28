import XCTest
@testable import Typebar

@MainActor final class CustomGeneratedSelectionTests: XCTestCase {
  func testFreshCustomSelectionAgainstCompletePinnedGeneratorWordsetAndContinuation() async throws {
    try await compareFreshSelection(focused: false)
  }
  func testFocusedCustomSelectionAgainstPinnedGeneratorAndContinuation() async throws {
    try await compareFreshSelection(focused: true)
  }
  private func compareFreshSelection(focused: Bool) async throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Fixture: Decodable {
      let text: [String], mode: String, limitMode: String, limitValue: String, pipe: Bool
      let focus: String?
      let fields: [String], sectionIndexes: [Int], allGenerated: Bool, drawsUsed: Int
      let finalFields: [String], finalSectionIndexes: [Int], tailRanks: [Int]
      let continuationCalls: Int, finalDrawsUsed: Int, continuationFailed: Bool
      let repeatedFields: [String], repeatedSectionIndexes: [Int], repeatedAllGenerated: Bool
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-generated-backwards-order.mjs").path, reference, focused ? "--custom-fresh-focus" : "--custom-fresh"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, focused ? 1152 : 288)
    for item in fixtures {
      let draft = try WebsiteConfigNativeProfile.prepareDraft(
        "{\"mode\":\"custom\",\"funbox\":\(item.focus.map { "[\"\($0)\"]" } ?? "[]")}",
        pointsPerRem: 16, context: .init())
      let limit = try XCTUnwrap(item.limitValue == "Infinity" ? .infinity : Double(item.limitValue))
      let custom = try WebsiteCustomTextSettings(value: .object([
        "text": .array(item.text.map(WebsiteConfigValue.string)), "mode": .string(item.mode),
        "limit": .object(["mode": .string(item.limitMode), "value": .number(limit)]), "pipeDelimiter": .bool(item.pipe)]))
      var draws = 0
      let ready = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: .init(websiteCustomText: custom),
        random: .init(wordIndex: { defer { draws += 1 }; return draws % item.text.count }))
      guard ready.session.prompt == item.fields.joined() else {
        XCTFail("Published prompt differs: \(ready.session.prompt) versus \(item.fields.joined()), \(item)"); return
      }
      let history = try XCTUnwrap(ready.session.generatedWordReplayHistory, "Fresh selection must own repeatable generated records")
      XCTAssertEqual((0..<history.count).map { history.word(at: $0)?.sectionIndex }, item.sectionIndexes.map(Optional.some))
      XCTAssertEqual(ready.session.usesIncrementalPromptExtension, !item.allGenerated)
      XCTAssertEqual(draws, item.drawsUsed)
      var cursor = GeneratedCandidateContinuation(configuration: ready.session.configuration, batchTokenCount: 100,
        sourceWords: item.text, customLimitValue: limit)
      var directDraws = 0
      var bound = limit == 0 || limit.isInfinite || item.limitMode == "time" ? 100 : min(100, Int(limit.rounded(.up)))
      if let visible = ready.session.configuration.visibleFutureWordCount {
        bound = item.limitMode == "word" && limit > 0 && limit.isFinite
          ? min(visible + 1, Int(limit.rounded(.up))) : visible + 1
      }
      let opening = cursor.nextChunk(maximumWordCount: item.pipe ? 100 : bound, initialPreparationWordBound: bound,
        nextRandomWordIndex: { defer { directDraws += 1 }; return directDraws % item.text.count })
      var fields = (cursor.hasRemaining ? .init(text: opening.transformed, sourceFields: opening.sourceFields)
        : FinitePromptCommitPolicy.finalized(.init(text: opening.transformed, sourceFields: opening.sourceFields))).sourceFields ?? []
      var tailIndex = 0
      for _ in 0..<item.continuationCalls {
        XCTAssertTrue(cursor.hasRemaining)
        let chunk = cursor.nextChunk(maximumWordCount: 1, nextRandomWordIndex: {
          defer { tailIndex += 1; directDraws += 1 }
          return item.tailRanks.indices.contains(tailIndex) ? item.tailRanks[tailIndex] : 0
        })
        if cursor.sourceGenerationFailed || cursor.replayExhausted { break }
        let batch = TransformedPromptBatch(text: chunk.transformed, sourceFields: chunk.sourceFields)
        fields += (cursor.hasRemaining ? batch : FinitePromptCommitPolicy.finalized(batch)).sourceFields ?? []
      }
      XCTAssertEqual(fields, item.finalFields, "\(item)")
      XCTAssertEqual((0..<fields.count).map { cursor.replayHistory.word(at: $0)?.sectionIndex }, item.finalSectionIndexes.map(Optional.some))
      XCTAssertEqual(cursor.sourceGenerationFailed || cursor.replayExhausted, item.continuationFailed)
      XCTAssertEqual(directDraws, item.finalDrawsUsed)
      let repeated = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: .init(websiteCustomText: custom),
        attemptSource: .repeatedWords(cursor.replayHistory, repeatedPace: false),
        random: .init(wordIndex: { XCTFail("Cached repeat consumed a draw"); return 0 }))
      XCTAssertEqual(repeated.session.prompt, item.repeatedFields.joined(), "\(item)")
      XCTAssertEqual(repeated.session.usesIncrementalPromptExtension, !item.repeatedAllGenerated)
      let repeatedHistory = try XCTUnwrap(repeated.session.generatedWordReplayHistory)
      XCTAssertEqual((0..<item.repeatedFields.count).map { repeatedHistory.word(at: $0)?.sectionIndex },
        item.repeatedSectionIndexes.map(Optional.some))
    }
  }

  private func settings(_ text: [String], mode: String = "repeat", limitMode: String = "word",
    limit: Double, pipe: Bool = false) throws -> WebsiteCustomTextSettings {
    try .init(value: .object(["text": .array(text.map(WebsiteConfigValue.string)), "mode": .string(mode),
      "limit": .object(["mode": .string(limitMode), "value": .number(limit)]), "pipeDelimiter": .bool(pipe)]))
  }
  private let start = Date(timeIntervalSince1970: 100)
  private func finish(_ session: inout TypingSession) {
    for _ in 0..<1000 where !session.isFinished {
      session.insertBatch(session.nextExpectedCharacter.map(String.init) ?? " ", at: start.addingTimeInterval(1))
    }
  }

  func testPipeWordBudgetFinishesAllPublishedFieldsWithBothInputStyles() async throws {
    for noSpace in [false, true] {
      let draft = try WebsiteConfigNativeProfile.prepareDraft(
        "{\"mode\":\"custom\",\"funbox\":\(noSpace ? "[\"nospace\"]" : "[]")}", pointsPerRem: 16, context: .init())
      var session = try await WebsiteConfigSessionBuilder.prepare(draft: draft,
        scope: .init(websiteCustomText: settings(["aa bb cc dd", "ee"], limit: 2, pipe: true))).session
      session.insertBatch(noSpace ? "aabb" : "aa bb", at: start)
      XCTAssertFalse(session.isFinished, "Pipe generation publishes whole sections beyond the word budget")
      finish(&session)
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.completedWordCount, 5)
      XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(session.preciseAccuracy, 100)
    }
  }

  func testLiveGrowthFramingAgainstPinnedGeneratorAndInputHelpers() async throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Output: Decodable {
      struct Event: Decodable { let data: String, correct: Bool, advances: Bool }
      let fields: [String], tape: String, events: [Event]
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-generated-backwards-order.mjs").path, reference, "--custom-live-framing"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let source = try JSONDecoder().decode(Output.self, from: data)
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"custom","funbox":["no_quit"]}"#,
      pointsPerRem: 16, context: .init())
    var session = try await WebsiteConfigSessionBuilder.prepare(draft: draft,
      scope: .init(websiteCustomText: settings(["aa bb cc dd ee ff gg hh ii", "jj"], limit: 2))).session
    session.insertBatch("a", at: start)
    let before = session.generationState, prompt = session.prompt
    XCTAssertTrue(try session.synchronizeWebsiteCustomText(settings(["replacement"], limit: 7.5)))
    XCTAssertEqual(session.automaticInputAttemptID, before.attempt)
    XCTAssertEqual(session.promptTargetID, before.target)
    XCTAssertEqual(session.typed, before.typed); XCTAssertEqual(session.prompt, prompt)
    finish(&session)
    XCTAssertEqual(session.outcome, .completed); XCTAssertEqual(session.completedWordCount, 8)
    XCTAssertEqual(session.errors, 0)
    let expectedAccuracy = (Double(source.events.filter(\.correct).count) / Double(source.events.count) * 10000).rounded() / 100
    XCTAssertEqual(session.preciseAccuracy, expectedAccuracy)
    XCTAssertEqual(session.typed, source.tape)
    let history = try XCTUnwrap(session.generatedWordReplayHistory)
    XCTAssertEqual((0..<history.count).map { history.word(at: $0)?.source },
      ["aa", "bb", "cc", "dd", "ee", "ff", "gg", "hh"].map(Optional.some))
  }

  func testLiveShrinkKeepsPublishedQueueAndSwitchToTimedLimitKeepsStart() async throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"custom"}"#, pointsPerRem: 16, context: .init())
    let initial = try settings(["aa bb cc dd ee"], limit: 5)
    var shrinking = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: .init(websiteCustomText: initial)).session
    shrinking.insertBatch("aa ", at: start)
    XCTAssertTrue(try shrinking.synchronizeWebsiteCustomText(settings(["replacement"], limit: 2)))
    shrinking.insertBatch("bb", at: start)
    XCTAssertFalse(shrinking.isFinished)
    finish(&shrinking)
    XCTAssertEqual(shrinking.outcome, .completed); XCTAssertEqual(shrinking.completedWordCount, 5)
    var timed = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: .init(websiteCustomText: initial)).session
    timed.insertBatch("a", at: start)
    XCTAssertTrue(try timed.synchronizeWebsiteCustomText(settings(["replacement"], limitMode: "time", limit: 2.5)))
    timed.tick(at: start.addingTimeInterval(2.49)); XCTAssertFalse(timed.isFinished)
    timed.tick(at: start.addingTimeInterval(2.5)); XCTAssertEqual(timed.outcome, .completed)
  }

  func testFreshMultiwordSectionsUseStoredSectionCounterAcrossBothInputStyles() async throws {
    for noSpace in [false, true] {
      let draft = try WebsiteConfigNativeProfile.prepareDraft(
        "{\"mode\":\"custom\",\"funbox\":\(noSpace ? "[\"nospace\"]" : "[]")}", pointsPerRem: 16, context: .init())
      let text = noSpace ? ["🇺 🇸", "e\u{301} 界"] : ["Aa Bb", "Cc"]
      var session = try await WebsiteConfigSessionBuilder.prepare(draft: draft,
        scope: .init(websiteCustomText: settings(text, limitMode: "section", limit: 2))).session
      XCTAssertEqual(session.progressText(at: start), "0/2")
      session.insertBatch(noSpace ? "🇺" : "Aa ", at: start)
      XCTAssertEqual(session.progressText(at: start), "0/2")
      session.insertBatch(noSpace ? "🇸" : "Bb ", at: start)
      XCTAssertEqual(session.progressText(at: start), "1/2")
      finish(&session)
      XCTAssertEqual(session.outcome, .completed); XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(session.progressText(at: start), "1/2")
      XCTAssertEqual(session.progressFraction(at: start), 1)
    }
  }

  func testDirectZeroLimitRepeatFailsAtCacheEndInsteadOfBecomingFreshGeneration() {
    for completion in [CustomTextCompletion.words, .sections] {
      var configuration = TestConfiguration.words(0)
      configuration.mode = .custom; configuration.customTextCompletion = completion
      configuration.customTextSectionLimit = 0
      var cursor = GeneratedCandidateContinuation(configuration: configuration, batchTokenCount: 3,
        sourceWords: ["aa", "bb"], customLimitValue: 0)
      _ = cursor.nextChunk(nextRandomWordIndex: { 0 })
      var repeated = cursor.replayingContinuation()
      let extra = repeated.nextChunk(maximumWordCount: 1, nextRandomWordIndex: { 0 })
      XCTAssertTrue(repeated.replayExhausted)
      XCTAssertTrue(extra.source.isEmpty)
    }
  }
}
