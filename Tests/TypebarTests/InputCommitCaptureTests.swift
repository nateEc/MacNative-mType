import XCTest
@testable import Typebar

final class InputCommitCaptureTests: XCTestCase {
  private struct Event: Decodable {
    let offset: Double
    let payload, value: [UInt16]
    let field, charIndex: Int
    let correct, stopped, commit, last: Bool
  }
  private struct Fixture: Decodable {
    let words: [String]
    let suffix, stop: String
    let finished, failed, noSpace: Bool
    let wpm, raw: [Double]
    let events: [Event]
  }
  private struct Output: Decodable { let fixtures: [Fixture] }

  func testFreshCommitEvidenceAgainstCompletePinnedInputHandlersAndStatistics() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-input-position.mjs").path,
      reference, "--commit-capture-fixtures"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 48)
    for (index, fixture) in fixtures.enumerated() {
      let stop: StopOnErrorMode = fixture.stop == "word" ? .word : fixture.stop == "letter" ? .letter : .off
      let config = TestConfiguration.words(fixture.words.count, rules: .init(stopOnErrorMode: stop))
        .with(modifiers: fixture.noSpace ? [.noSpaces] : [])
      var session = fixture.noSpace
        ? TypingSession(configuration: config, prompt: fixture.words.joined(), noSpaceTargetWords: fixture.words)
        : TypingSession(configuration: config, prompt: fixture.words.joined(), sourceFields: fixture.words)
      let start = Date(timeIntervalSinceReferenceDate: 919_000_000)
      session.insertBatch("a", at: start)
      session.insertBatch(fixture.suffix, at: start.addingTimeInterval(2.5))
      XCTAssertEqual(session.outcome == .completed, fixture.finished, "completion \(index)")
      XCTAssertEqual(session.outcome == .failed, fixture.failed, "failure \(index)")
      session.bailOut(at: start.addingTimeInterval(2.5))
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.replayEvents.count, fixture.events.count, "event count \(index)")
      for (event, source) in zip(result.replayEvents, fixture.events) {
        XCTAssertEqual(event.offset, source.offset, "time \(index)")
        XCTAssertEqual(event.inputUnits, source.payload, "payload \(index)")
        XCTAssertEqual(event.inputField?.index, source.field, "field \(index)")
        XCTAssertEqual(event.inputField?.units, source.value, "snapshot \(index)")
        XCTAssertEqual(event.inputPosition?.charIndex, source.charIndex, "position \(index)")
        XCTAssertEqual(event.inputPosition?.lastWord, source.last, "last \(index)")
        XCTAssertEqual(event.inputCorrectness, [source.correct], "judgment \(index)")
        XCTAssertEqual(event.isStoppedInsertion, source.stopped, "stop \(index)")
        XCTAssertEqual(event.commitsWord == true, source.commit, "commit \(index)")
      }
      let points = ResultPerformanceTrace.points(prompt: result.prompt, events: result.replayEvents,
        duration: 2.5, configuration: config, targetWordDirectory: result.targetWordDirectory)
      XCTAssertEqual(points.map { Double($0.wpm) }, fixture.wpm, "WPM \(index)")
      XCTAssertEqual(points.map { Double($0.rawWpm) }, fixture.raw, "Raw \(index)")
    }
  }

  func testFreshTrueAndLegacyMissingCommitEvidenceSurviveArchiveAndModelConversion() throws {
    let start = Date(timeIntervalSinceReferenceDate: 919_100_000)
    var session = TypingSession(configuration: .words(1), prompt: "ab", sourceFields: ["ab"])
    session.insertBatch("a", at: start)
    session.insertBatch("b ", at: start.addingTimeInterval(2.5))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.replayEvents.last?.commitsWord, true)
    let data = try JSONEncoder().encode(result)
    let json = try JSONDecoder().decode(CompletedTestResult.self, from: data)
    let model = try XCTUnwrap(TestResultRecord(result: result).portableResult)
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    XCTAssertEqual(archive.version, TypebarArchive.currentVersion)
    for restored in [json, model, try XCTUnwrap(archive.results.first)] {
      XCTAssertEqual(restored, result)
      XCTAssertEqual(restored.replayEvents.last?.inputField?.units, Array("ab ".utf16))
      let points = ResultPerformanceTrace.points(prompt: restored.prompt, events: restored.replayEvents,
        duration: restored.chartDuration, configuration: restored.configuration, targetWordDirectory: restored.targetWordDirectory)
      XCTAssertEqual(points.map(\.wpm), [12, 6, 10]); XCTAssertEqual(points.map(\.rawWpm), [12, 6, 10])
    }
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var events = try XCTUnwrap(object["replayEvents"] as? [[String: Any]])
    for index in events.indices { events[index].removeValue(forKey: "commitsWord") }
    object["replayEvents"] = events
    let legacy = try JSONDecoder().decode(CompletedTestResult.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertTrue(legacy.replayEvents.allSatisfy { $0.commitsWord == nil })
    XCTAssertEqual(legacy.wpm, result.wpm); XCTAssertEqual(legacy.rawWpm, result.rawWpm)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: legacy).portableResult), legacy)
  }
}
