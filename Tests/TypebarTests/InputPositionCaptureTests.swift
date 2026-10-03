import XCTest
@testable import Typebar

final class InputPositionCaptureTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 909_100_000)

  private func attempt(_ source: String, rules: InputRules = .init()) -> TypingSession {
    TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: rules, modifiers: [.noSpaces]), customText: source)
  }

  private func events(_ session: TypingSession) throws -> [TypingReplayEvent] {
    var snapshot = session
    snapshot.bailOut(at: start.addingTimeInterval(10))
    return try XCTUnwrap(snapshot.result()).replayEvents
  }

  private func objects(_ session: TypingSession) throws -> [[String: Any]] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(events(session))) as? [[String: Any]])
  }

  private func positions(_ session: TypingSession) throws -> [[String: Any]] {
    try objects(session).map { try XCTUnwrap($0["inputPosition"] as? [String: Any]) }
  }

  func testImplicitCommitCapturesBeforeNavigationAndMarksTheActualLastWord() throws {
    var session = attempt("ab cd")
    session.insertBatch("abcd", at: start)
    XCTAssertEqual(session.outcome, .completed)
    let captured = try positions(session)
    XCTAssertEqual(captured.compactMap { $0["charIndex"] as? Int }, [0,1,0,1])
    XCTAssertEqual(captured.compactMap { $0["lastWord"] as? Bool }, [false,false,true,true])
    XCTAssertEqual(try events(session).map { $0.inputField?.index }, [0,0,1,1])
  }

  func testStoppedLowSurrogateUsesItsPreAttemptPositionNotTheRetainedLength() throws {
    var session = attempt("🙂x tail", rules: .init(stopOnErrorMode: .letter))
    session.insertBatch("🙃", at: start)
    session.insert("🙂", at: start.addingTimeInterval(1))
    let captured = try positions(session)
    XCTAssertEqual(captured.compactMap { $0["charIndex"] as? Int }, [0,1,1,1])
    XCTAssertEqual(captured.compactMap { $0["lastWord"] as? Bool }, [false,false,false,false])
    XCTAssertEqual(try events(session).map(\.inputStopped), [nil,true,true,nil])
    XCTAssertEqual(try events(session).map { $0.inputField?.valueUTF16?.count }, [1,1,1,2])
  }

  func testFusedDisplayStillStartsTheSecondSourceFieldAtZero() throws {
    var session = attempt("a \u{301}b tail")
    session.insertBatch("a\u{301}b", at: start)
    XCTAssertEqual(session.typed.count, 2)
    XCTAssertEqual(try positions(session).compactMap { $0["charIndex"] as? Int }, [0,0,1])
    XCTAssertEqual(try events(session).map { $0.inputField?.index }, [0,1,1])
  }

  func testWordStopExtrasAndInputCapDoNotResetOrInventPositions() throws {
    var session = attempt("ab cd", rules: .init(stopOnErrorMode: .word))
    session.insertBatch("xb" + String(repeating: "x", count: 30), at: start)
    XCTAssertEqual(try events(session).count, 22)
    XCTAssertEqual(try positions(session).compactMap { $0["charIndex"] as? Int }, Array(0..<22))
    XCTAssertEqual(try positions(session).compactMap { $0["lastWord"] as? Bool }, Array(repeating: false, count: 22))
  }

  func testStrictFinalNewlineRecordsLastWordEvenWithoutNavigation() throws {
    var session = TypingSession(configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(strictSpace: true), modifiers: [.noSpaces]),
      prompt: "a\n", noSpaceTargetWords: ["a","\n"])
    session.insertBatch("a\n", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(try positions(session).compactMap { $0["charIndex"] as? Int }, [0,0])
    XCTAssertEqual(try positions(session).compactMap { $0["lastWord"] as? Bool }, [false,true])
    XCTAssertEqual(try events(session).last?.commitsWord, false)
  }

  func testDeletesDoNotLeakThePreviousInsertionPosition() throws {
    var session = attempt("🙂x tail", rules: .init(freedomMode: true))
    session.insertBatch("🙂", at: start)
    session.deleteWordBackward(at: start.addingTimeInterval(1))
    session.insert("🙂", at: start.addingTimeInterval(2))
    let encoded = try objects(session)
    XCTAssertTrue(encoded.filter { $0["kind"] as? String == "delete" }.allSatisfy { $0["inputPosition"] == nil })
    XCTAssertEqual(encoded.filter { $0["kind"] as? String == "insert" }
      .compactMap { ($0["inputPosition"] as? [String: Any])?["charIndex"] as? Int }, [0,1,0,1])
  }

  func testUnknownNoSpaceBoundariesAndLegacyASCIIHaveNoInventedWordPosition() throws {
    var unknown = TypingSession(configuration: .words(2).with(modifiers: [.noSpaces]), prompt: "abcd")
    unknown.insert("ab", at: start)
    var ascii = TypingSession(configuration: .words(2), prompt: "ab cd")
    ascii.insert("a", at: start)
    for session in [unknown, ascii] { XCTAssertTrue(try objects(session).allSatisfy { $0["inputPosition"] == nil }) }
  }

  func testLastWordDescribesTheCatalogBeforeTimedRefillNotTheFinalDirectory() throws {
    var session = TypingSession(configuration: .timed(seconds: 5).with(modifiers: [.noSpaces]),
      prompt: "ab", repeatingPrompt: "ab", noSpaceTargetWords: ["a","b"],
      repeatingNoSpaceTargetWords: ["a","b"])
    session.insertBatch("ab", at: start)
    let captured = try positions(session)
    XCTAssertEqual(captured.compactMap { $0["charIndex"] as? Int }, [0,0])
    XCTAssertEqual(captured.compactMap { $0["lastWord"] as? Bool }, [false,true])
    session.tick(at: start.addingTimeInterval(5))
    XCTAssertEqual(session.result()?.targetWordDirectory?.words, ["a","b","a","b"])
    XCTAssertEqual(session.outcome, .completed)
  }

  func testLegacyEventRoundTripDoesNotBackfillPositionOrAlterPrimitiveReplay() throws {
    let legacy = try JSONDecoder().decode(TypingReplayEvent.self,
      from: Data(#"{"offset":0,"kind":"insert","text":"🙂","inputField":{"index":0,"value":"🙂"}}"#.utf8))
    let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
    XCTAssertNil(encoded["inputPosition"])
    XCTAssertEqual(TypingReplay.typedText(events: [legacy], through: 0), "🙂")
  }

  func testMalformedPositionAndDeletionPositionAreRejectedRatherThanIgnored() throws {
    let base: [String: Any] = ["offset": 0, "kind": "insert", "text": "a",
      "inputField": ["index": 0, "value": "a"]]
    for position: [String: Any] in [["charIndex": -1,"lastWord": true], ["charIndex": 0],
      ["charIndex": 0,"lastWord": 1], ["charIndex": "0","lastWord": false]] {
      var invalid = base; invalid["inputPosition"] = position
      XCTAssertThrowsError(try JSONDecoder().decode(TypingReplayEvent.self,
        from: JSONSerialization.data(withJSONObject: invalid)))
    }
    for kind in ["insert", "delete"] {
      var invalid = base
      invalid["kind"] = kind
      if kind == "insert" { invalid.removeValue(forKey: "inputField") }
      invalid["inputPosition"] = ["charIndex": 0,"lastWord": true]
      XCTAssertThrowsError(try JSONDecoder().decode(TypingReplayEvent.self,
        from: JSONSerialization.data(withJSONObject: invalid)))
    }
  }
}
