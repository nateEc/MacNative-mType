import XCTest
@testable import Typebar

final class DeletionPositionCaptureTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 909_600_000)
  private func session(_ words: [String]) -> TypingSession {
    .init(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(freedomMode: true), modifiers: [.noSpaces]),
      prompt: words.joined(), noSpaceTargetWords: words)
  }
  private func result(_ input: TypingSession) throws -> CompletedTestResult {
    var copy = input; copy.bailOut(at: start.addingTimeInterval(3))
    return try XCTUnwrap(copy.result())
  }
  private func deletions(_ input: TypingSession) throws -> [[String: Any]] {
    let events = try result(input).replayEvents.filter { $0.kind == .delete }
    return try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(events)) as? [[String: Any]])
  }

  func testWithinFieldUsesBeforeLengthForEachRawSurrogateDeletion() throws {
    var input = session(["🙂x", "tail"]); input.insertBatch("🙂", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    input.deleteBackward(at: start.addingTimeInterval(2))
    let saved = try deletions(input)
    XCTAssertEqual(saved.compactMap { $0["deletionCharIndex"] as? Int }, [2,1])
    XCTAssertTrue(saved.allSatisfy { $0["inputPosition"] == nil })
    XCTAssertEqual(try result(input).replayEvents.filter { $0.kind == .delete }.map { $0.inputField?.units }, [[0xd83d],[]])
  }

  func testRegressionAndClearedTerminalUseDestinationLengthInsteadOfBeforeLength() throws {
    for text in ["ab", "abcd "] {
      var input = session(["ab", "cd"]); input.insertBatch(text, at: start)
      input.deleteBackward(at: start.addingTimeInterval(1))
      XCTAssertEqual(try deletions(input).compactMap { $0["deletionCharIndex"] as? Int }, [1])
      XCTAssertEqual(try result(input).replayEvents.last?.inputField?.units, [97])
    }
  }

  func testWholeWordActionStoresOneBeforePositionOnItsFinalPrimitive() throws {
    var input = session(["abcd", "tail"]); input.insertBatch("abc", at: start)
    input.deleteWordBackward(at: start.addingTimeInterval(1))
    let saved = try deletions(input)
    XCTAssertEqual(saved.count, 3)
    XCTAssertEqual(saved.compactMap { $0["deletionCharIndex"] as? Int }, [3])
    XCTAssertEqual(saved.last?["deletionCharIndex"] as? Int, 3)
    XCTAssertTrue(saved.dropLast().allSatisfy { $0["deletionCharIndex"] == nil })
    XCTAssertEqual(saved.first?["wordDeletionCount"] as? Int, 3)
  }

  func testCodeUnindentHasTwoPositionsAndFirstFieldDestinationNoOpIsZero() throws {
    for text in ["ab\n\t\tx", "\t\tx"] {
      var input = TypingSession(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
        difficulty: .normal, rules: .init(freedomMode: true, codeUnindentOnBackspace: true), language: .codeSwift), prompt: text)
      let entered = text == "\t\tx" ? "\t\t" : "ab\n\t\t"
      // Match the source probe's two-tab fixture, without draining queued
      // indentation and accidentally appending a third automatic tab.
      input.insertBatch(entered, at: start, defersAutomaticInput: true)
      XCTAssertEqual(input.typed, entered)
      input.deleteBackward(at: start.addingTimeInterval(1))
      XCTAssertEqual(try deletions(input).compactMap { $0["deletionCharIndex"] as? Int }, text == "\t\tx" ? [2,0] : [2,2])
    }
  }

  func testASCIIPositionDoesNotConvertItsLegacyPrimitiveIntoAUnitDeletion() throws {
    var input = TypingSession(configuration: .words(2), prompt: "abcd tail")
    input.insertBatch("ab", at: start); input.deleteBackward(at: start.addingTimeInterval(1))
    let saved = try result(input); let event = try XCTUnwrap(saved.replayEvents.last)
    XCTAssertEqual(event.validatedDeletionCharIndex, 2)
    XCTAssertFalse(event.deletesUTF16Unit)
    XCTAssertNil(event.textUTF16)
    XCTAssertEqual(TypingReplay.typedText(events: saved.replayEvents, through: 1), "a")
  }

  func testWholeWordRegressionStoresOnlyTheFinalDestinationZero() throws {
    var input = session(["ab", "cd"]); input.insertBatch("ab", at: start)
    input.deleteWordBackward(at: start.addingTimeInterval(1))
    let events = try result(input).replayEvents.filter { $0.kind == .delete }
    XCTAssertEqual(events.count, 2)
    XCTAssertEqual(events.map(\.deletionCharIndex), [nil,0])
    XCTAssertEqual(events.first?.wordDeletionCount, 2)
    XCTAssertEqual(events.last?.inputField?.units, [])
  }

  func testCombiningWordBoundaryUsesFieldUnitsNotFlattenedGlyphCount() throws {
    var input = session(["a", "\u{301}b", "tail"])
    input.insertBatch("a\u{301}b", at: start); input.deleteBackward(at: start.addingTimeInterval(1))
    let event = try XCTUnwrap(result(input).replayEvents.last)
    XCTAssertEqual(event.validatedDeletionCharIndex, 1)
    XCTAssertEqual(event.inputField?.index, 1)
    XCTAssertEqual(event.inputField?.units, [769])
    XCTAssertEqual(input.typed.count, 1)
  }

  func testBlockedAndUnknownOrAutomaticPathsNeverInventPositions() throws {
    var blocked = TypingSession(configuration: .words(2, rules: .init(confidenceMode: .maximum)), prompt: "abcd tail")
    blocked.insertBatch("ab", at: start); blocked.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertTrue(try result(blocked).replayEvents.allSatisfy { $0.kind != .delete })
    var unknown = TypingSession(configuration: .words(2).with(modifiers: [.noSpaces]), prompt: "abcdtail")
    unknown.insertBatch("ab", at: start); unknown.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertNil(try result(unknown).replayEvents.last?.deletionCharIndex)
    var automatic = TypingSession(configuration: .words(2, rules: .init(deleteOnErrorMode: .word)).with(modifiers: [.noSpaces]),
      prompt: "abcdtail", noSpaceTargetWords: ["abcd", "tail"])
    automatic.insertBatch("ax", at: start)
    let recovery = try result(automatic).replayEvents.filter { $0.kind == .delete }
    XCTAssertFalse(recovery.isEmpty)
    XCTAssertTrue(recovery.allSatisfy { $0.automatic && $0.deletionCharIndex == nil })
  }

  func testDeletionThenNewInsertionKeepsPositionKindsSeparate() throws {
    var input = session(["abcd", "tail"]); input.insertBatch("ab", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1)); input.insertBatch("b", at: start.addingTimeInterval(2))
    let events = try result(input).replayEvents
    XCTAssertEqual(events.map(\.deletionCharIndex), [nil,nil,2,nil])
    XCTAssertEqual(events.map { $0.inputPosition?.charIndex }, [0,1,nil,1])
  }

  func testCodeWordUnindentKeepsBothActionMarkersAndFinalPositions() throws {
    var input = TypingSession(configuration: .words(4, rules: .init(codeUnindentOnBackspace: true), language: .codeSwift),
      prompt: "seed ab\n\tgo()\ntail")
    input.insertBatch("seed ab\n\t\t", at: start); input.deleteWordBackward(at: start.addingTimeInterval(1))
    let saved = try result(input)
    let actions = TypingReplay.actions(events: saved.replayEvents).filter { $0.kind != .insert }
    XCTAssertEqual(actions.map(\.kind), [.deleteWord,.deleteCharacter])
    XCTAssertEqual(actions.map { $0.primitives.last?.deletionCharIndex }, [3,0])
    XCTAssertTrue(actions.allSatisfy { $0.primitives.dropLast().allSatisfy { $0.deletionCharIndex == nil } })
    XCTAssertEqual(input.typed, "seed ")
  }
}
