import XCTest
@testable import Typebar

@MainActor final class CustomGeneratedReplayTests: XCTestCase {
  func testCustomReplayAgainstPinnedGeneratorWordsetAndContinuation() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? env["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Fixture: Decodable {
      let text: [String], mode: String, limitMode: String, limitValue: String, pipe: Bool
      let fields: [String], allGenerated: Bool, drawsUsed: Int, error: String?
      let finalFields: [String], finalDrawsUsed: Int, continuationFailed: Bool
      let tailRanks: [Int]
      let sectionIndexes: [Int]?, finalSectionIndexes: [Int]
      let continuationCalls: Int
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-generated-backwards-order.mjs").path, reference, "--custom-replay"]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 288)
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"custom"}"#, pointsPerRem: 16, context: .init())
    for item in fixtures {
      let limit: Double
      if item.limitValue == "Infinity" { limit = .infinity }
      else { limit = try XCTUnwrap(Double(item.limitValue)) }
      var history = GeneratedWordReplayHistory(noSpace: false)
      ["ab", "cd", "ef"].forEach { history.append(source: $0, target: $0) }
      let custom = try WebsiteCustomTextSettings(value: .object([
        "text": .array(item.text.map(WebsiteConfigValue.string)), "mode": .string(item.mode),
        "limit": .object(["mode": .string(item.limitMode), "value": .number(limit)]),
        "pipeDelimiter": .bool(item.pipe)]))
      var draws = 0
      do {
        let ready = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: .init(websiteCustomText: custom),
          attemptSource: .repeatedWords(history, repeatedPace: false),
          random: .init(wordIndex: { defer { draws += 1 }; return draws % item.text.count }))
        XCTAssertNil(item.error, "\(item)")
        XCTAssertEqual(ready.session.prompt, item.fields.joined(), "\(item)")
        let initialHistory = try XCTUnwrap(ready.session.generatedWordReplayHistory)
        XCTAssertEqual((0..<item.fields.count).map { initialHistory.word(at: $0)?.sectionIndex },
          item.sectionIndexes?.map(Optional.some), "\(item)")
        XCTAssertEqual(ready.session.usesIncrementalPromptExtension, !item.allGenerated, "\(item)")
        if item.limitMode != "time" {
          var cursor = GeneratedCandidateContinuation(configuration: ready.session.configuration,
            batchTokenCount: 100, sourceWords: item.text, replayHistory: history, customLimitValue: limit)
          var directDraws = 0
          func rank() -> Int { defer { directDraws += 1 }; return directDraws % item.text.count }
          let bound = limit == 0 || limit.isInfinite ? 100 : min(100, Int(limit.rounded(.up)))
          var chunk = cursor.nextChunk(maximumWordCount: item.pipe ? 100 : bound,
            initialPreparationWordBound: bound, nextRandomWordIndex: rank)
          var fields = chunk.sourceFields ?? []
          if !cursor.hasRemaining {
            fields = FinitePromptCommitPolicy.finalized(TransformedPromptBatch(text: chunk.transformed,
              sourceFields: fields)).sourceFields ?? []
          }
          var tailDrawIndex = 0
          func tailRank() -> Int {
            defer { directDraws += 1; tailDrawIndex += 1 }
            return item.tailRanks.indices.contains(tailDrawIndex) ? item.tailRanks[tailDrawIndex] : 0
          }
          for _ in 0..<item.continuationCalls {
            guard cursor.hasRemaining else { XCTFail("Native continuation ended early: \(item)"); break }
            chunk = cursor.nextChunk(maximumWordCount: 1, nextRandomWordIndex: tailRank)
            if cursor.replayExhausted || cursor.sourceGenerationFailed { break }
            let batch = TransformedPromptBatch(text: chunk.transformed, sourceFields: chunk.sourceFields)
            fields += (cursor.hasRemaining ? batch : FinitePromptCommitPolicy.finalized(batch)).sourceFields ?? []
          }
          XCTAssertEqual(fields, item.finalFields, "\(item)")
          XCTAssertEqual((0..<fields.count).map { cursor.replayHistory.word(at: $0)?.sectionIndex },
            item.finalSectionIndexes.map(Optional.some), "\(item)")
          XCTAssertEqual(cursor.replayExhausted, item.continuationFailed, "\(item)")
          XCTAssertEqual(directDraws, item.finalDrawsUsed, "\(item)")
        }
      } catch WebsiteConfigSessionBuildError.generationFailed {
        XCTAssertEqual(item.error, "Repeated word is undefined", "\(item)")
      }
      XCTAssertEqual(draws, item.drawsUsed, "\(item)")
    }
  }

  func testWordsToCustomRepeatKeepsCachedPrefixAndStartsFreshCustomCursorAtZero() async throws {
    var history = GeneratedWordReplayHistory(noSpace: false)
    ["ab", "cd", "ef"].forEach { history.append(source: $0, target: $0) }
    let custom = try WebsiteCustomTextSettings(value: .object([
      "text": .array([.string("Aa Bb"), .string("Cc"), .string("I"), .string("x2"), .string("Ω")]),
      "mode": .string("repeat"), "limit": .object(["mode": .string("word"), "value": .number(5)]),
      "pipeDelimiter": .bool(false)]))
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"custom"}"#, pointsPerRem: 16, context: .init())
    let ready = try await WebsiteConfigSessionBuilder.prepare(draft: draft,
      scope: .init(websiteCustomText: custom), attemptSource: .repeatedWords(history, repeatedPace: true),
      random: .init(wordIndex: { 0 }))
    var session = ready.session
    XCTAssertEqual(session.prompt, "ab cd ef Aa Bb")
    XCTAssertEqual(ready.repetition, .sameWordset(repeatedPace: true))
    session.insertBatch(session.prompt)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 5)
    XCTAssertEqual(session.errors, 0)
  }

  func testSectionReplayContinuesItsRealQuotaOrFailsOnAnUnadmittedPendingTail() async throws {
    for quota in [4, 5] {
      var history = GeneratedWordReplayHistory(noSpace: false)
      ["ab", "cd", "ef"].forEach { history.append(source: $0, target: $0) }
      let custom = try WebsiteCustomTextSettings(value: .object([
        "text": .array([.string("Aa Bb"), .string("Cc")]), "mode": .string("repeat"),
        "limit": .object(["mode": .string("section"), "value": .number(Double(quota))]),
        "pipeDelimiter": .bool(false)]))
      let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"custom"}"#, pointsPerRem: 16, context: .init())
      var session = try await WebsiteConfigSessionBuilder.prepare(draft: draft,
        scope: .init(websiteCustomText: custom), attemptSource: .repeatedWords(history, repeatedPace: false),
        random: .init(wordIndex: { 0 })).session
      XCTAssertTrue(session.usesIncrementalPromptExtension)
      let opening = session.prompt
      session.insertBatch(opening + (quota == 5 ? "Cc" : "Bb"))
      if quota == 4 {
        XCTAssertEqual(session.outcome, .failed)
        XCTAssertEqual(session.failureReason, .wordGeneration)
        XCTAssertEqual(session.prompt, opening)
      } else {
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.completedWordCount, 6)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.prompt, "ab cd ef Aa Bb Cc")
      }
    }
  }

  func testMixedCommitRulesCompleteCustomWordsAndTimedReplayRefillsPastOpening() async throws {
    let start = Date(timeIntervalSince1970: 100)
    for oldNoSpace in [false, true] { for newNoSpace in [false, true] {
      for timed in [false, true] {
        var history = GeneratedWordReplayHistory(noSpace: oldNoSpace)
        ["ab", "cd", "ef"].forEach { history.append(source: $0, target: $0) }
        let custom = try WebsiteCustomTextSettings(value: .object([
          "text": .array([.string("Aa Bb")]), "mode": .string("repeat"),
          "limit": .object(["mode": .string(timed ? "time" : "word"), "value": .number(timed ? 15 : 5)]),
          "pipeDelimiter": .bool(false)]))
        let draft = try WebsiteConfigNativeProfile.prepareDraft(
          "{\"mode\":\"custom\",\"funbox\":\(newNoSpace ? "[\"nospace\"]" : "[]")}", pointsPerRem: 16, context: .init())
        var session = try await WebsiteConfigSessionBuilder.prepare(draft: draft,
          scope: .init(websiteCustomText: custom), attemptSource: .repeatedWords(history, repeatedPace: false),
          random: .init(wordIndex: { 0 })).session
        let opening = session.prompt
        let count = timed ? 100 : 5
        let tape = (0..<count).map { index -> String in
          let word = index < 3 ? ["ab", "cd", "ef"][index] : (index - 3).isMultiple(of: 2) ? "Aa" : "Bb"
          if !timed && index == count - 1 { return word }
          if newNoSpace { return word + (index < 3 && !oldNoSpace ? "x" : "") }
          return word + " "
        }.joined()
        session.insertBatch(tape, at: start)
        XCTAssertEqual(session.completedWordCount, count)
        XCTAssertEqual(session.errors, oldNoSpace == newNoSpace ? 0 : 3)
        if timed {
          XCTAssertFalse(session.isFinished)
          XCTAssertGreaterThan(session.prompt.utf16.count, opening.utf16.count)
          session.insertBatch("Bb" + (newNoSpace ? "" : " "), at: start.addingTimeInterval(14.9))
          XCTAssertEqual(session.completedWordCount, 101)
          session.tick(at: start.addingTimeInterval(15))
        }
        XCTAssertEqual(session.outcome, .completed)
      }
    }}
  }
}
