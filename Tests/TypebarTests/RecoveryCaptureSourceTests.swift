import XCTest
@testable import Typebar

final class RecoveryCaptureSourceTests: XCTestCase {
  private struct Event: Decodable {
    let inputType: String
    let field, charIndex: Int
    let value: [UInt16]
    let automatic: Bool
  }
  private struct Fixture: Decodable {
    let words: [String]
    let prefix, suffix, stop, recovery: String
    let noSpace: Bool
    let duration: Double
    let inputs: [[UInt16]]
    let burst, wpm, raw: [Double]
    let errors: [Int]
    let events: [Event]
  }
  private struct Output: Decodable { let fixtures: [Fixture] }

  func testAutomaticRecoveryActionsAndSeriesAgainstCompletePinnedHandlers() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-input-position.mjs").path,
      reference, "--recovery-capture-fixtures"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 72)
    for (index, fixture) in fixtures.enumerated() {
      let deletion: DeleteOnErrorMode = fixture.recovery == "word" ? .word : fixture.recovery == "letter_hard" ? .letterHard
        : fixture.recovery == "word_hard" ? .wordHard : fixture.recovery == "off" ? .off : .letter
      let rules = InputRules(stopOnErrorMode: fixture.stop == "word" ? .word : fixture.stop == "letter" ? .letter : .off,
        deleteOnErrorMode: deletion)
      let config = TestConfiguration.words(fixture.words.count, rules: rules).with(modifiers: fixture.noSpace ? [.noSpaces] : [])
      var session = fixture.noSpace
        ? TypingSession(configuration: config, prompt: fixture.words.joined(), noSpaceTargetWords: fixture.words)
        : TypingSession(configuration: config, prompt: fixture.words.joined(), sourceFields: fixture.words)
      let start = Date(timeIntervalSinceReferenceDate: 0)
      session.insertBatch(fixture.prefix, at: start)
      session.insertBatch(fixture.suffix, at: start.addingTimeInterval(fixture.duration))
      session.bailOut(at: start.addingTimeInterval(fixture.duration))
      let result = try XCTUnwrap(session.result())
      let actions = TypingReplay.actions(events: result.replayEvents).filter { $0.kind != .insert }
      let source = fixture.events.filter { $0.inputType.hasPrefix("delete") }
      XCTAssertEqual(actions.count, source.count, "actions \(index)")
      for (action, expected) in zip(actions, source) {
        let event = try XCTUnwrap(action.primitives.last)
        XCTAssertEqual(action.kind == .deleteWord, expected.inputType == "deleteWordBackward", "kind \(index)")
        XCTAssertEqual(event.inputField?.index, expected.field, "field \(index)")
        XCTAssertEqual(event.inputField?.units, expected.value, "value \(index)")
        XCTAssertEqual(event.validatedDeletionCharIndex, expected.charIndex, "position \(index)")
        XCTAssertEqual(event.automatic, expected.automatic, "automatic \(index)")
      }
      XCTAssertEqual(SavedTextInputHistoryPolicy.inputFieldUTF16(events: result.replayEvents), fixture.inputs, "history \(index)")
      let points = ResultPerformanceTrace.points(prompt: result.prompt, events: result.replayEvents, duration: fixture.duration,
        configuration: config, targetWordDirectory: result.targetWordDirectory, sourceScoringBasis: result.characterStats.sourceUnitBasis)
      XCTAssertEqual(points.map(\.burstWpm), fixture.burst, "burst \(index)")
      XCTAssertEqual(points.map(\.errorCount), fixture.errors, "errors \(index)")
      XCTAssertEqual(points.map { Double($0.wpm) }, fixture.wpm, "WPM \(index)")
      XCTAssertEqual(points.map { Double($0.rawWpm) }, fixture.raw, "Raw \(index)")
    }
  }

  func testAutomaticPositionsSurvivePersistenceAndLegacyAbsenceRemainsMissing() throws {
    let config = TestConfiguration.words(2, rules: .init(deleteOnErrorMode: .wordHard)).with(modifiers: [.noSpaces])
    var session = TypingSession(configuration: config, prompt: "🙂xtail", noSpaceTargetWords: ["🙂x","tail"])
    let start = Date(timeIntervalSinceReferenceDate: 0)
    session.insertBatch("🙂x", at: start)
    session.insertBatch("y", at: start.addingTimeInterval(2.5))
    session.bailOut(at: start.addingTimeInterval(3))
    let result = try XCTUnwrap(session.result())
    let actions = TypingReplay.actions(events: result.replayEvents).filter { $0.kind != .insert }
    XCTAssertEqual(actions.map(\.kind), [.deleteWord, .deleteWord])
    XCTAssertEqual(actions.map { $0.primitives.last?.deletionCharIndex }, [1,0])
    XCTAssertTrue(actions.allSatisfy { $0.primitives.dropLast().allSatisfy { $0.deletionCharIndex == nil } })
    let encoded = try JSONEncoder().encode(result)
    let json = try JSONDecoder().decode(CompletedTestResult.self, from: encoded)
    let model = try XCTUnwrap(TestResultRecord(result: result).portableResult)
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    XCTAssertEqual(archive.version, TypebarArchive.currentVersion)
    for restored in [json, model, try XCTUnwrap(archive.results.first)] {
      XCTAssertEqual(restored, result)
      XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 3), "")
      XCTAssertEqual(TypingReplay.actions(events: restored.replayEvents).filter { $0.kind != .insert }
        .map { $0.primitives.last?.deletionCharIndex }, [1,0])
    }
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var events = try XCTUnwrap(object["replayEvents"] as? [[String: Any]])
    for index in events.indices { events[index].removeValue(forKey: "deletionCharIndex") }
    object["replayEvents"] = events
    let legacy = try JSONDecoder().decode(CompletedTestResult.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertTrue(legacy.replayEvents.allSatisfy { $0.deletionCharIndex == nil })
    XCTAssertEqual(legacy.wpm, result.wpm); XCTAssertEqual(legacy.rawWpm, result.rawWpm)
    XCTAssertEqual(legacy.characterStats, result.characterStats)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: legacy).portableResult), legacy)
  }
}
