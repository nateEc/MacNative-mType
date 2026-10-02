import XCTest
@testable import Typebar

final class WordDeletionActionTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 873_400_000)
  private func attempt(_ rules: InputRules = .init(), source: String = "ab cd tail",
    modifiers: [TestModifier] = []) -> TypingSession {
    TestSessionFactory.make(configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: rules, modifiers: modifiers),
      quote: .init(id: "owned-delete-action", title: "Action probe", text: source,
        language: .english, length: .short))
  }
  private func result(_ attempt: TypingSession) throws -> CompletedTestResult {
    var ended = attempt
    ended.bailOut(at: start.addingTimeInterval(3))
    return try XCTUnwrap(ended.result())
  }
  private func deletionCues(_ result: CompletedTestResult) -> [TypingReplaySoundCue] {
    TypingReplay.soundCues(prompt: result.prompt, events: result.replayEvents, after: 0.5, through: 1.5)
  }

  func testCurrentWordDeletionPlaysOneClickNotOnePerRemovedCharacter() throws {
    var session = attempt()
    session.insertBatch("ab cx", at: start)
    session.deleteWordBackward(at: start.addingTimeInterval(1))
    let ended = try result(session)
    XCTAssertEqual(session.typed, "ab ")
    XCTAssertEqual(deletionCues(ended), [.click])
    XCTAssertEqual(TypingReplay.typedText(events: ended.replayEvents, through: 1), "ab ")
  }

  func testPreviousWordDeletionIsOneActionIncludingItsSeparator() throws {
    var session = attempt(.init(freedomMode: true))
    session.insertBatch("ab cd ", at: start)
    session.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "ab ")
    XCTAssertEqual(deletionCues(try result(session)), [.click])
  }

  func testNoSpaceDeletionIsOneActionAndKeepsEarlierWords() throws {
    for input in ["abc", "abcx"] {
      var session = attempt(modifiers: [.noSpaces])
      session.insertBatch(input, at: start)
      session.deleteWordBackward(at: start.addingTimeInterval(1))
      XCTAssertEqual(session.typed, "ab")
      XCTAssertEqual(deletionCues(try result(session)), [.click])
    }
  }

  func testProtectedWordHasNeitherDeletionNorClick() throws {
    var session = attempt()
    session.insertBatch("ab ", at: start)
    session.deleteWordBackward(at: start.addingTimeInterval(1))
    let ended = try result(session)
    XCTAssertEqual(deletionCues(ended), [])
    XCTAssertFalse(ended.replayEvents.contains { $0.kind == .delete })
  }

  func testSeparateCharacterDeletionsAtTheSameTimestampRemainSeparateActions() throws {
    var session = attempt()
    session.insertBatch("ab cx", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "ab ")
    XCTAssertEqual(deletionCues(try result(session)), [.click, .click])
  }

  func testWordDeleteCanIncludeTabAndRequiredNewlineWithoutSeveralClicks() throws {
    var session = attempt(.init(freedomMode: true), source: "ab\n\tcd\ntail")
    session.insertBatch("ab\n\tcd\n", at: start)
    session.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "ab\n")
    XCTAssertEqual(deletionCues(try result(session)), [.click])
  }

  func testUnicodeWholeWordDeletionPreservesThePrimitiveReplayAndOneClick() throws {
    var session = attempt(source: "seed 🙂e\u{301} tail")
    session.insertBatch("seed 🙂e\u{301}", at: start)
    session.deleteWordBackward(at: start.addingTimeInterval(1))
    let ended = try result(session)
    XCTAssertEqual(session.typed, "seed ")
    XCTAssertEqual(deletionCues(ended), [.click])
    XCTAssertEqual(TypingReplay.typedText(events: ended.replayEvents, through: 0.9), "seed 🙂e\u{301}")
    XCTAssertEqual(TypingReplay.typedText(events: ended.replayEvents, through: 1), "seed ")
  }

  func testPortableResultAndArchiveRetainOneWordDeleteAction() throws {
    var session = attempt()
    session.insertBatch("ab cx", at: start)
    session.deleteWordBackward(at: start.addingTimeInterval(1))
    session.insertBatch("cd tail", at: start.addingTimeInterval(2))
    let ended = try XCTUnwrap(session.result())
    let portable = try XCTUnwrap(TestResultRecord(result: ended).portableResult)
    let imported = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [ended], presets: [], at: start))
    for restored in [ended, portable, imported.results[0]] {
      XCTAssertEqual(deletionCues(restored), [.click])
      let actions = TypingReplay.actions(events: restored.replayEvents).filter { $0.kind == .deleteWord }
      XCTAssertEqual(actions.count, 1)
      XCTAssertEqual(actions.first?.primitiveRange.count, 2)
      XCTAssertEqual(actions.first?.primitives.first?.wordDeletionCount, 2)
      XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents,
        through: restored.elapsedDuration), "ab cd tail")
    }
  }

  func testReplayClassifiesCanonicalAliasAsAnErrorInsteadOfAnImplicitMatch() {
    let events = [TypingReplayEvent(offset: 0, kind: .insert, text: "é")]
    XCTAssertEqual(TypingReplay.inputGlyphs(prompt: "e\u{301}", events: events, through: 0)[0].state, .incorrect)
    XCTAssertEqual(TypingReplay.soundCues(prompt: "e\u{301}", events: events, after: -1, through: 0), [.error])
  }

  func testActionProjectionRetainsEveryPrimitiveWithoutInferringSameTimeBackspaces() throws {
    var session = attempt()
    session.insertBatch("ab cx", at: start)
    session.deleteWordBackward(at: start.addingTimeInterval(1))
    let events = try result(session).replayEvents
    let actions = TypingReplay.actions(events: events)
    let deletion = try XCTUnwrap(actions.last)
    XCTAssertEqual(deletion.kind, .deleteWord)
    XCTAssertEqual(deletion.primitiveRange.count, 2)
    XCTAssertEqual(deletion.primitives.map(\.wordDeletionCount), [2, nil])
    XCTAssertEqual(Array(actions.flatMap(\.primitives)), TypingReplay.chronologicalEvents(events))
    let legacy = withoutMarkers(events)
    XCTAssertEqual(TypingReplay.actions(events: legacy).suffix(2).map(\.kind),
      [.deleteCharacter, .deleteCharacter])
  }

  func testAutomaticWordAndWordHardDeletionKeepTheirSourceActionBoundaries() throws {
    var normal = attempt(.init(deleteOnErrorMode: .word))
    normal.insertBatch("ab c", at: start)
    normal.insertBatch("x", at: start.addingTimeInterval(1))
    let normalResult = try result(normal)
    let normalDeletes = TypingReplay.actions(events: normalResult.replayEvents).filter { $0.kind == .deleteWord }
    XCTAssertEqual(normal.typed, "ab ")
    XCTAssertEqual(normalDeletes.map { $0.primitiveRange.count }, [2])
    XCTAssertTrue(normalDeletes.flatMap(\.primitives).allSatisfy(\.automatic))

    var hard = attempt(.init(deleteOnErrorMode: .wordHard))
    hard.insertBatch("ab ", at: start)
    hard.insertBatch("x", at: start.addingTimeInterval(1))
    let hardResult = try result(hard)
    let hardDeletes = TypingReplay.actions(events: hardResult.replayEvents).filter { $0.kind == .deleteWord }
    XCTAssertEqual(hard.typed, "")
    XCTAssertEqual(hardDeletes.map { $0.primitiveRange.count }, [1, 3])
    XCTAssertTrue(hardDeletes.flatMap(\.primitives).allSatisfy(\.automatic))
    // The attempted incorrect key remains audible; automatic removal does not add clicks.
    XCTAssertEqual(deletionCues(normalResult), [.error])
    XCTAssertEqual(deletionCues(hardResult), [.error])
  }

  func testCodeUnindentProjectsTabsAndPriorNewlineAsDistinctActions() throws {
    var session = TypingSession(configuration: .words(5,
      rules: .init(codeUnindentOnBackspace: true), language: .codeSwift),
      prompt: "if ready {\n\tgo()\n}")
    session.insertBatch("if ready {\n\t", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    let actions = TypingReplay.actions(events: try result(session).replayEvents)
      .filter { $0.kind != .insert }
    XCTAssertEqual(session.typed, "if ready {")
    XCTAssertEqual(actions.map(\.kind), [.deleteWord, .deleteCharacter])
    XCTAssertEqual(actions.map { $0.primitiveRange.count }, [2, 1])
    // Both logged actions belong to the manual deletion, not automatic indentation.
    XCTAssertTrue(actions.flatMap(\.primitives).allSatisfy { !$0.automatic })
  }

  func testLegacyRecordsDoNotAcquireInventedWordActionsOrNewJSONKeys() throws {
    let data = Data("""
      [{"offset":0,"kind":"insert","text":"cx"},
       {"offset":1,"kind":"delete","text":""},
       {"offset":1,"kind":"delete","text":""}]
      """.utf8)
    let events = try JSONDecoder().decode([TypingReplayEvent].self, from: data)
    XCTAssertTrue(events.allSatisfy { $0.wordDeletionCount == nil })
    XCTAssertEqual(TypingReplay.actions(events: events).map(\.kind), [.insert, .deleteCharacter, .deleteCharacter])
    XCTAssertEqual(TypingReplay.soundCues(prompt: "cd", events: events, after: 0.5, through: 1), [.click, .click])
    let encoded = try JSONEncoder().encode(events)
    XCTAssertFalse(try XCTUnwrap(String(data: encoded, encoding: .utf8)).contains("wordDeletionCount"))
  }

  func testReaderWithoutNewFieldCanStillRecoverTheEntireInput() throws {
    // Simulates only the old event decoder, not a separately installed old application.
    struct LegacyEvent: Decodable {
      let offset: TimeInterval
      let kind: TypingReplayEventKind
      let text: String
      let forceError: Bool
      let automatic: Bool
      let commitsWord: Bool?
    }
    var session = attempt(.init(freedomMode: true))
    session.insertBatch("ab cx ", at: start)
    session.deleteWordBackward(at: start.addingTimeInterval(1))
    let events = try result(session).replayEvents
    let decoded = try JSONDecoder().decode([LegacyEvent].self, from: JSONEncoder().encode(events))
    let oldTape = decoded.map { TypingReplayEvent(offset: $0.offset, kind: $0.kind, text: $0.text,
      forceError: $0.forceError, automatic: $0.automatic, commitsWord: $0.commitsWord) }
    XCTAssertEqual(oldTape, withoutMarkers(events))
    XCTAssertEqual(TypingReplay.typedText(events: oldTape, through: 1), session.typed)
    XCTAssertEqual(TypingReplay.soundCues(prompt: session.prompt, events: oldTape, after: 0.5, through: 1),
      [.click, .click, .click])
    XCTAssertEqual(TypingReplay.soundCues(prompt: session.prompt, events: events, after: 0.5, through: 1), [.click])
  }

  func testWordMarkersDoNotChangeSeekGlyphsGraphsOrSavedProgress() throws {
    var session = attempt()
    session.insertBatch("ab cx", at: start)
    session.deleteWordBackward(at: start.addingTimeInterval(1))
    session.insertBatch("cd tail", at: start.addingTimeInterval(2))
    let ended = try XCTUnwrap(session.result())
    let events = ended.replayEvents
    let legacy = withoutMarkers(events)
    for offset in [0.0, 0.9, 1.0, 1.1, 2.0] {
      XCTAssertEqual(TypingReplay.typedText(events: events, through: offset),
        TypingReplay.typedText(events: legacy, through: offset))
      XCTAssertEqual(TypingReplay.inputGlyphs(prompt: ended.prompt, events: events, through: offset),
        TypingReplay.inputGlyphs(prompt: ended.prompt, events: legacy, through: offset))
    }
    XCTAssertEqual(TypingReplay.characterSeekOffsets(prompt: ended.prompt, events: events),
      TypingReplay.characterSeekOffsets(prompt: ended.prompt, events: legacy))
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: ended.prompt, events: events, duration: 3),
      ResultPerformanceTrace.points(prompt: ended.prompt, events: legacy, duration: 3))
    let displays = SavedTextInputHistoryPolicy.displayWords(in: ended.prompt)
    XCTAssertEqual(SavedTextInputHistoryPolicy.progressWordCount(displays: displays, events: events),
      SavedTextInputHistoryPolicy.progressWordCount(displays: displays, events: legacy))
  }

  func testInvalidWordSpansFallBackWithoutLosingPrimitiveEventsOrSound() {
    let insert = TypingReplayEvent(offset: 0, kind: .insert, text: "cx")
    let delete = TypingReplayEvent(offset: 1, kind: .delete, text: "")
    let badPairs: [[TypingReplayEvent]] = [-1, 0, 3, Int.max].map {
      [.init(offset: 1, kind: .delete, text: "", wordDeletionCount: $0), delete]
    } + [
      [.init(offset: 1, kind: .delete, text: "", wordDeletionCount: 2),
       .init(offset: 1.1, kind: .delete, text: "")],
      [.init(offset: 1, kind: .delete, text: "", wordDeletionCount: 2),
       .init(offset: 1, kind: .delete, text: "", automatic: true)],
      [.init(offset: 1, kind: .delete, text: "unexpected", wordDeletionCount: 2), delete],
      [.init(offset: 1, kind: .delete, text: "", forceError: true, wordDeletionCount: 2), delete],
      [.init(offset: 1, kind: .delete, text: "", commitsWord: false, wordDeletionCount: 2), delete],
      [.init(offset: 1, kind: .delete, text: "", wordDeletionCount: 2),
       .init(offset: 1, kind: .insert, text: "c")],
      [.init(offset: 1, kind: .delete, text: "", wordDeletionCount: 2),
       .init(offset: 1, kind: .delete, text: "", wordDeletionCount: 1)]
    ]
    for pair in badPairs {
      let events = [insert] + pair
      let actions = TypingReplay.actions(events: events)
      XCTAssertEqual(actions[1].kind, .deleteCharacter)
      XCTAssertEqual(Array(actions.flatMap(\.primitives)), TypingReplay.chronologicalEvents(events))
      XCTAssertEqual(TypingReplay.typedText(events: events, through: 2),
        TypingReplay.typedText(events: withoutMarkers(events), through: 2))
      XCTAssertEqual(TypingReplay.soundCues(prompt: "cd", events: events, after: 0.5, through: 2),
        TypingReplay.soundCues(prompt: "cd", events: withoutMarkers(events), after: 0.5, through: 2))
    }
  }

  private func withoutMarkers(_ events: [TypingReplayEvent]) -> [TypingReplayEvent] {
    events.map { .init(offset: $0.offset, kind: $0.kind, text: $0.text, forceError: $0.forceError,
      automatic: $0.automatic, commitsWord: $0.commitsWord) }
  }
}
