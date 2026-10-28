import XCTest
@testable import Typebar

@MainActor final class CustomRawWordBoundTests: XCTestCase {
  func testRawBoundsAgainstPinnedGeneratorPunctuationAlterationsAndContinuation() async throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Fixture: Decodable {
      let boxes: [String], punctuation: Bool, limitMode: String, limit: String, pipe: Bool, bound: Double, unit: Double
      let fields: [String], allGenerated: Bool, calls: Int, finalFields: [String], repeatedFields: [String]
    }
    struct Reconfigured: Decodable {
      let unit: Double, boxes: [String], punctuation: Bool, limitMode: String, limit: Double, opening: [String], fields: [String]
    }
    struct Output: Decodable { let text: [String], fixtures: [Fixture], reconfigured: [Reconfigured] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-generated-backwards-order.mjs").path, reference, "--custom-raw-bound"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures.count, 2304); XCTAssertEqual(output.reconfigured.count, 96)
    for item in output.fixtures {
      let limit = try XCTUnwrap(item.limit == "Infinity" ? .infinity : Double(item.limit))
      let custom = try WebsiteCustomTextSettings(value: .object([
        "text": .array(output.text.map(WebsiteConfigValue.string)), "mode": .string("repeat"),
        "limit": .object(["mode": .string(item.limitMode), "value": .number(limit)]), "pipeDelimiter": .bool(item.pipe)]))
      let boxes = WebsiteConfigJSONWriter.write(.array(item.boxes.map(WebsiteConfigValue.string)), asciiOnly: false)
      let draft = try WebsiteConfigNativeProfile.prepareDraft(
        "{\"mode\":\"custom\",\"punctuation\":\(item.punctuation),\"funbox\":\(boxes)}", pointsPerRem: 16, context: .init())
      let random = WebsiteConfigSessionBuilder.Random(wordIndex: { 0 }, contentUnit: { item.unit })
      let ready = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: .init(websiteCustomText: custom), random: random)
      guard ready.session.prompt == item.fields.joined() else {
        XCTFail("Initial raw bound differs: \(ready.session.prompt) versus \(item.fields.joined()), \(item)"); return
      }
      XCTAssertEqual(ready.session.usesIncrementalPromptExtension, !item.allGenerated)
      var cursor = GeneratedCandidateContinuation(configuration: ready.session.configuration, batchTokenCount: 100,
        sourceWords: output.text, customLimitValue: limit)
      let bound = Int(item.bound.rounded(.up))
      let opening = cursor.nextChunk(maximumWordCount: item.pipe ? 100 : bound,
        initialPreparationWordBound: bound, nextRandomWordIndex: { 0 }, nextRandomContentUnit: { item.unit })
      var batch = TransformedPromptBatch(text: opening.transformed,
        noSpaceTargetWords: opening.noSpaceTargetWords, sourceFields: opening.sourceFields)
      if !cursor.hasRemaining { batch = FinitePromptCommitPolicy.finalized(batch) }
      var fields = batch.sourceFields ?? []
      for _ in 0..<item.calls {
        XCTAssertTrue(cursor.hasRemaining)
        let chunk = cursor.nextChunk(maximumWordCount: 1, nextRandomWordIndex: { 0 }, nextRandomContentUnit: { item.unit })
        let next = TransformedPromptBatch(text: chunk.transformed,
          noSpaceTargetWords: chunk.noSpaceTargetWords, sourceFields: chunk.sourceFields)
        fields += (cursor.hasRemaining ? next : FinitePromptCommitPolicy.finalized(next)).sourceFields ?? []
      }
      XCTAssertEqual(fields, item.finalFields, "\(item)")
      let repeated = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: .init(websiteCustomText: custom),
        attemptSource: .repeatedWords(cursor.replayHistory, repeatedPace: false), random: random)
      XCTAssertEqual(repeated.session.prompt, item.repeatedFields.joined(), "\(item)")
    }
    for item in output.reconfigured {
      var history = GeneratedWordReplayHistory(noSpace: false)
      item.opening.forEach { history.append(source: String($0.dropLast()), target: String($0.dropLast()), committedText: $0) }
      let custom = try WebsiteCustomTextSettings(value: .object([
        "text": .array(output.text.map(WebsiteConfigValue.string)), "mode": .string("repeat"),
        "limit": .object(["mode": .string(item.limitMode), "value": .number(item.limit)]), "pipeDelimiter": .bool(false)]))
      let boxes = WebsiteConfigJSONWriter.write(.array(item.boxes.map(WebsiteConfigValue.string)), asciiOnly: false)
      let draft = try WebsiteConfigNativeProfile.prepareDraft(
        "{\"mode\":\"custom\",\"punctuation\":\(item.punctuation),\"funbox\":\(boxes)}", pointsPerRem: 16, context: .init())
      let ready = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: .init(websiteCustomText: custom),
        attemptSource: .repeatedWords(history, repeatedPace: false),
        random: .init(wordIndex: { 0 }, contentUnit: { item.unit }))
      XCTAssertEqual(ready.session.prompt, item.fields.joined(), "\(item)")
    }
  }

  func testFractionalUnderscoreQueueRequiresFinalSuffixAndPipeConsumesEveryPublishedWord() async throws {
    for pipe in [false, true] {
      for limit in [1.5, 4.5] {
        let custom = try WebsiteCustomTextSettings(value: .object([
          "text": .array([.string("ab cd"), .string("ef gh"), .string("ij kl")]), "mode": .string("repeat"),
          "limit": .object(["mode": .string("word"), "value": .number(limit)]), "pipeDelimiter": .bool(pipe)]))
        let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"custom","funbox":["underscore_spaces"]}"#,
          pointsPerRem: 16, context: .init())
        var session = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: .init(websiteCustomText: custom)).session
        let prompt = session.prompt, start = Date(timeIntervalSince1970: 100)
        XCTAssertTrue(prompt.hasSuffix("_"))
        session.insertBatch(String(prompt.dropLast()), at: start)
        XCTAssertEqual(session.outcome, .active)
        session.insertBatch("_", at: start.addingTimeInterval(1))
        XCTAssertEqual(session.outcome, .completed); XCTAssertEqual(session.preciseAccuracy, 100)
        XCTAssertEqual(session.completedWordCount, Int(limit.rounded(.up)) * (pipe ? 2 : 1))
      }
    }
  }
}
