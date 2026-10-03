import XCTest
@testable import Typebar

final class RawUTF16ReplayTests: XCTestCase {
  private func event(_ json: String) throws -> TypingReplayEvent {
    try JSONDecoder().decode(TypingReplayEvent.self, from: Data(json.utf8))
  }

  func testLoneSurrogateMetadataSurvivesCodecWithSafeDisplayProjection() throws {
    let original = try event(#"{"offset":0,"kind":"insert","text":"�","textUTF16":[55357],"inputCorrectness":[true],"inputField":{"index":0,"value":"�","valueUTF16":[55357]}}"#)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    XCTAssertEqual(object["textUTF16"] as? [Int], [55357])
    let field = try XCTUnwrap(object["inputField"] as? [String: Any])
    XCTAssertEqual(field["valueUTF16"] as? [Int], [55357])
    XCTAssertEqual(original.text, "�")
  }

  func testSeparateSurrogatesRejoinForAcceptedTextRatherThanTwoReplacements() throws {
    let events = try [
      event(#"{"offset":0,"kind":"insert","text":"�","textUTF16":[55357],"inputCorrectness":[true],"inputField":{"index":0,"value":"�","valueUTF16":[55357]}}"#),
      event(#"{"offset":1,"kind":"insert","text":"�","textUTF16":[56898],"inputCorrectness":[true],"inputField":{"index":0,"value":"🙂","valueUTF16":[55357,56898]}}"#)]
    XCTAssertEqual(TypingReplay.typedText(events: events, through: 0), "�")
    XCTAssertEqual(TypingReplay.typedText(events: events, through: 1), "🙂")
  }

  func testRawSurrogateCannotSubmitAsTheLiteralReplacementCharacter() throws {
    let events = try [
      event(#"{"offset":0,"kind":"insert","text":"�","textUTF16":[55357],"inputCorrectness":[false],"inputField":{"index":0,"value":"�","valueUTF16":[55357]}}"#),
      event(#"{"offset":1,"kind":"insert","text":" ","textUTF16":[32],"inputCorrectness":[true],"inputField":{"index":0,"value":"� ","valueUTF16":[55357,32]}}"#),
      event(#"{"offset":2,"kind":"insert","text":"b","textUTF16":[98],"inputCorrectness":[true],"inputField":{"index":1,"value":"b","valueUTF16":[98]}}"#)]
    let actions = try XCTUnwrap(TypingReplay.fieldActions(prompt: "� b", events: events))
    XCTAssertEqual(actions.map(\.kind), [.input(text: "�", correct: false), .input(text: " ", correct: true),
      .advance(correct: false), .input(text: "b", correct: true)])
  }

  private func insert(_ units: [UInt16], snapshot: [UInt16], at offset: Double = 0,
    correct: [Bool]? = nil, stopped: Bool = false, field: Int = 0) -> TypingReplayEvent {
    .init(offset: offset, kind: .insert, units: units, inputStopped: stopped ? true : nil,
      inputField: .init(index: field, units: snapshot), inputCorrectness: correct)
  }

  func testAcceptedHighSurrogateSurvivesStoppedLowWithoutAnExtraReplayAction() throws {
    let events = [insert([55357], snapshot: [55357], correct: [true]),
      insert([56899], snapshot: [55357], correct: [false], stopped: true)]
    XCTAssertEqual(TypingReplay.typedUTF16(events: events, through: 0), [55357])
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: "🙂x", events: events).map(\.cue), [.click])
    let frame = try XCTUnwrap(FieldReplayPlan.make(prompt: "🙂x", events: events)).frame(through: 0)
    XCTAssertEqual(frame.position, 1)
    XCTAssertEqual(frame.presentation.glyphs.map(\.state), [.correct, .pending])
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFieldUTF16(events: events), [[55357]])
  }

  func testDeletionRemovesOnlyTheLowSurrogateAndResizesTheSourceField() throws {
    let events = [insert([55357], snapshot: [55357], correct: [true]),
      insert([56898], snapshot: [55357,56898], correct: [true]),
      TypingReplayEvent(offset: 1, kind: .delete, units: [], inputField: .init(index: 0, units: [55357]))]
    XCTAssertEqual(TypingReplay.typedUTF16(events: events, through: 0), [55357,56898])
    XCTAssertEqual(TypingReplay.typedUTF16(events: events, through: 1), [55357])
    XCTAssertEqual(TypingReplay.typedText(events: events, through: 1), "�")
    XCTAssertEqual(TypingReplay.fieldActions(prompt: "🙂x", events: events)?.last?.kind, .resize(1))
    let frame = try XCTUnwrap(FieldReplayPlan.make(prompt: "🙂x", events: events)).frame(through: 1)
    XCTAssertEqual(frame.position, 1)
    XCTAssertEqual(frame.presentation.glyphs.map(\.state), [.correct, .pending])
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: "🙂x", events: events).map(\.cue), [.click, .click, .click])
  }

  func testExplicitUnitDeletionWorksWithoutAFieldCatalog() {
    let events = [TypingReplayEvent(offset: 0, kind: .insert, units: [55357,56898]),
      .init(offset: 1, kind: .delete, units: [])]
    XCTAssertEqual(TypingReplay.typedUTF16(events: events, through: 1), [55357])
    XCTAssertEqual(TypingReplay.typedText(events: events, through: 1), "�")
    XCTAssertNil(FieldReplayPlan.make(prompt: "🙂", events: events))
  }

  func testFieldRawSnapshotAlsoMarksAUnitDeletionWithoutAnEmptyPayloadSupplement() {
    let events = [insert([55357,56898], snapshot: [55357,56898]),
      TypingReplayEvent(offset: 1, kind: .delete, text: "", inputField: .init(index: 0, units: [55357]))]
    XCTAssertEqual(TypingReplay.typedUTF16(events: events, through: 1), [55357])
  }

  func testCombiningMarkUnitDeletionKeepsItsBaseRatherThanTheWholeGrapheme() {
    let events = [insert([101,769], snapshot: [101,769], correct: [true,true]),
      TypingReplayEvent(offset: 1, kind: .delete, units: [], inputField: .init(index: 0, units: [101]))]
    XCTAssertEqual(TypingReplay.typedUTF16(events: events, through: 1), [101])
    XCTAssertEqual(TypingReplay.typedText(events: events, through: 1), "e")
  }

  func testMissingLegacyDeletionMetadataRetainsTheWholeGraphemeContract() {
    for text in ["e\u{301}", "🙂", "🇦🇧", "\r\n"] {
      let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, text: "a"),
        .init(offset: 1, kind: .insert, text: text), .init(offset: 2, kind: .delete, text: "")]
      XCTAssertEqual(TypingReplay.typedText(events: events, through: 2), "a")
    }
  }

  func testMixedUnitAndLegacyDeletionApplyTheirOwnRecordedContracts() {
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, text: "ae\u{301}"),
      .init(offset: 1, kind: .delete, units: []),
      .init(offset: 2, kind: .insert, units: [769]), .init(offset: 3, kind: .delete, text: "")]
    XCTAssertEqual(TypingReplay.typedText(events: events, through: 1), "ae")
    XCTAssertEqual(TypingReplay.typedText(events: events, through: 3), "a")
  }

  func testUnpairedSurrogatesAndNoncharactersRemainRawRatherThanNormalized() throws {
    for units: [UInt16] in [[55357], [56898], [55357,55358,56898], [0,65535], [56898,55357]] {
      let original = insert(units, snapshot: units)
      let decoded = try JSONDecoder().decode(TypingReplayEvent.self, from: JSONEncoder().encode(original))
      XCTAssertEqual(decoded, original)
      XCTAssertEqual(decoded.inputUnits, units)
      XCTAssertEqual(decoded.inputField?.units, units)
      XCTAssertEqual(TypingReplay.typedUTF16(events: [decoded], through: 0), units)
    }
  }

  func testRawInputWithoutJudgmentsDerivesEachUnitAgainstCapturedFieldPosition() throws {
    let events = [insert([55357,56899], snapshot: [55357,56899])]
    XCTAssertEqual(TypingReplay.fieldActions(prompt: "🙂x", events: events)?.map(\.kind),
      [.input(text: "�", correct: true), .input(text: "�", correct: false)])
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: "🙂x", events: events).map(\.cue), [.click, .error])
  }

  func testRawExactIdentityDoesNotCanonicalizeComposedAndDecomposedFieldSubmissions() {
    let events = [insert([101,769,32], snapshot: [101,769,32]),
      insert([98], snapshot: [98], at: 1, field: 1)]
    XCTAssertTrue(TypingReplay.fieldActions(prompt: "é b", events: events)?.contains {
      $0.kind == .advance(correct: false)
    } == true)
  }

  func testRecordedRawFieldsKeepChronologicalSnapshotsAndStableEqualTimeOrder() {
    let events = [insert([98], snapshot: [98], at: 2, field: 1),
      insert([55357], snapshot: [55357], at: 0),
      insert([56898], snapshot: [55357,56898], at: 0),
      TypingReplayEvent(offset: 1, kind: .delete, units: [], inputField: .init(index: 0, units: [55357]))]
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFieldUTF16(events: events), [[55357], [98]])
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: events), ["�", "b"])
    XCTAssertEqual(TypingReplay.typedUTF16(events: events, through: 0), [55357,56898])
  }

  func testEmptyRawFieldIsValidButEmptyRawInsertionIsRejected() throws {
    let empty = TypingReplayInputField(index: 0, units: [])
    XCTAssertEqual(try JSONDecoder().decode(TypingReplayInputField.self, from: JSONEncoder().encode(empty)), empty)
    XCTAssertEqual(empty.validatedValueUTF16, [])
    XCTAssertThrowsError(try event(#"{"offset":0,"kind":"insert","text":"","textUTF16":[]}"#))
  }

  func testMalformedRawPayloadsTypesRangesAndNonemptyDeletesAreRejected() {
    for payload in ["[-1]", "[65536]", "[1.5]", "[true]", "[\"55357\"]", "{}", "\"x\""] {
      XCTAssertThrowsError(try event("{\"offset\":0,\"kind\":\"insert\",\"text\":\"�\",\"textUTF16\":\(payload)}"))
    }
    for json in [
      #"{"offset":0,"kind":"insert","text":"a","textUTF16":[55357]}"#,
      #"{"offset":0,"kind":"insert","text":"é","textUTF16":[101,769]}"#,
      #"{"offset":0,"kind":"delete","text":"a","textUTF16":[97]}"#,
      #"{"offset":0,"kind":"delete","text":"a","textUTF16":[]}"#,
      #"{"offset":0,"kind":"insert","text":"a","inputField":{"index":0,"value":"a","valueUTF16":[55357]}}"#,
      #"{"offset":0,"kind":"insert","text":"a","inputField":{"index":0,"value":"é","valueUTF16":[101,769]}}"#,
      #"{"offset":0,"kind":"insert","text":"a","inputField":{"index":-1,"value":"","valueUTF16":[]}}"#,
      #"{"offset":0,"kind":"insert","text":"�","textUTF16":[55357],"inputCorrectness":[true,false]}"#
    ] { XCTAssertThrowsError(try event(json)) }
  }

  func testMissingAndNullRawMetadataStayAbsentNotGuessedFromReplacementText() throws {
    let old = try event(#"{"offset":0,"kind":"insert","text":"�","textUTF16":null,"inputField":{"index":0,"value":"�","valueUTF16":null}}"#)
    XCTAssertNil(old.textUTF16)
    XCTAssertNil(old.inputField?.valueUTF16)
    XCTAssertEqual(old.inputUnits, [65533])
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
    XCTAssertNil(object["textUTF16"])
    XCTAssertNil((object["inputField"] as? [String: Any])?["valueUTF16"])
  }

  func testInvalidDirectMetadataFallsBackWithoutOverridingLegacyText() {
    let malformed = TypingReplayEvent(offset: 0, kind: .insert, text: "a",
      inputField: .init(index: 0, value: "a", valueUTF16: [55357]), textUTF16: [55357])
    XCTAssertNil(malformed.validatedTextUTF16)
    XCTAssertNil(malformed.inputField?.validatedValueUTF16)
    XCTAssertEqual(TypingReplay.typedUTF16(events: [malformed], through: 0), [97])
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: "a", events: [malformed]).map(\.cue), [.click])
    XCTAssertThrowsError(try JSONDecoder().decode(TypingReplayEvent.self, from: JSONEncoder().encode(malformed)))
  }

  func testSameTimeRawUnitSeekResumesTheTailOnce() throws {
    let events = [insert([55357], snapshot: [55357], correct: [true]),
      insert([56899], snapshot: [55357,56899], correct: [false])]
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "🙂x", events: events))
    var frame = try XCTUnwrap(plan.seek(.init(word: 0, position: 1))).frame
    XCTAssertEqual(frame.nextActionIndex, 1)
    XCTAssertEqual(plan.advance(&frame, through: 0), [.error])
    XCTAssertEqual(plan.advance(&frame, through: 0), [])
  }

  private let start = Date(timeIntervalSinceReferenceDate: 908_000_000.125)
  private func result(events: [TypingReplayEvent]) throws -> CompletedTestResult {
    // Independent owned codec fixture. New sessions carry newer source stats
    // and must never be stripped to masquerade as a version-13/14 producer.
    CompletedTestResult(id: UUID(), configuration: .words(1), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(1), typedCharacterCount: 2,
      correctCharacterCount: 2, errorCount: 0, wpm: 17, rawWpm: 29, accuracy: 77,
      inputMetrics: .init(version: 1, correctAttempts: 2, totalAttempts: 2, creditedUnits: 2, retainedUnits: 2),
      prompt: "ab", replayEvents: events)
  }

  func testPortableAndArchiveFourteenPreserveRawUnitsDatesAndStoredScores() throws {
    let original = try result(events: [insert([55357], snapshot: [55357], correct: [true]),
      insert([56899], snapshot: [55357], correct: [false], stopped: true)])
    let portable = try XCTUnwrap(TestResultRecord(result: original).portableResult)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let archive = try TypebarDataTransfer.importArchive(from: encoder.encode(
      TypebarArchive(version: 14, exportedAt: start, settings: .init(), results: [original], presets: [])))
    XCTAssertEqual(archive.version, 14)
    for restored in [portable, archive.results[0]] {
      XCTAssertEqual(restored, original)
      XCTAssertEqual(restored.inputMetrics, original.inputMetrics)
      XCTAssertEqual(restored.startedAt, start)
      XCTAssertEqual(TypingReplay.typedUTF16(events: restored.replayEvents, through: 1), [55357])
    }
  }

  func testArchiveConstructionRaisesRawPayloadOrRawFieldToFourteenWithoutJudgments() throws {
    let payloadOnly = try result(events: [.init(offset: 0, kind: .insert, units: [55357])])
    let fieldOnly = try result(events: [.init(offset: 0, kind: .insert, text: "�",
      inputField: .init(index: 0, units: [55357]))])
    for original in [payloadOnly, fieldOnly] {
      for version in 1...13 {
        XCTAssertEqual(TypebarArchive(version: version, exportedAt: start, settings: .init(), results: [original], presets: []).version, 14)
      }
    }
  }

  func testForgedArchiveOneThroughThirteenCannotDiscardRawTextOrRawFields() throws {
    for events in [[TypingReplayEvent(offset: 0, kind: .insert, units: [55357])],
      [.init(offset: 0, kind: .insert, text: "�", inputField: .init(index: 0, units: [55357]))]] {
      let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [result(events: events)], presets: [], at: start)
      var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
      for version in 1...13 {
        object["version"] = version
        XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: object))) {
          XCTAssertEqual($0 as? DataTransferError, .unsupportedVersion(version))
        }
      }
    }
  }

  func testGenuineArchiveThirteenRetainsItsOriginalJudgmentsAndNoRawBackfill() throws {
    let original = try result(events: [.init(offset: 0, kind: .insert, text: "🙂",
      inputField: .init(index: 0, value: "🙂"), inputCorrectness: [true,true])])
    let archive = TypebarArchive(version: 13, exportedAt: start, settings: .init(), results: [original], presets: [])
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let decoded = try TypebarDataTransfer.importArchive(from: encoder.encode(archive))
    XCTAssertEqual(decoded.version, 13)
    XCTAssertEqual(decoded.results[0], original)
    XCTAssertNil(decoded.results[0].replayEvents[0].textUTF16)
    XCTAssertNil(decoded.results[0].replayEvents[0].inputField?.valueUTF16)
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: "🙂x", events: decoded.results[0].replayEvents).map(\.cue), [.click,.click])
  }

  func testGroupedUnitDeletionKeepsOneActionAndUsesItsFinalFieldLength() {
    let events = [insert([55357,56898,120], snapshot: [55357,56898,120], correct: [true,true,true]),
      TypingReplayEvent(offset: 1, kind: .delete, units: [], wordDeletionCount: 2,
        inputField: .init(index: 0, units: [55357,56898])),
      TypingReplayEvent(offset: 1, kind: .delete, units: [], inputField: .init(index: 0, units: [55357]))]
    XCTAssertEqual(TypingReplay.typedUTF16(events: events, through: 1), [55357])
    XCTAssertEqual(TypingReplay.actions(events: events).map(\.kind), [.insert, .deleteWord])
    XCTAssertEqual(TypingReplay.fieldActions(prompt: "🙂x", events: events)?.last?.kind, .resize(1))
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: "🙂x", events: events).map(\.cue), [.click,.click,.click,.click])
  }

  func testThousandRawUnitPairsRejoinAndRetainEveryInputAction() throws {
    var events: [TypingReplayEvent] = []
    for index in 0..<1_000 {
      events.append(insert([55357], snapshot: [55357], at: Double(index), correct: [true], field: index))
      events.append(insert([56898], snapshot: [55357,56898], at: Double(index), correct: [true], field: index))
      if index < 999 { events.append(insert([32], snapshot: [55357,56898,32], at: Double(index), correct: [true], field: index)) }
    }
    let prompt = Array(repeating: "🙂", count: 1_000).joined(separator: " ")
    XCTAssertEqual(TypingReplay.typedText(events: events, through: 999), prompt)
    XCTAssertEqual(TypingReplay.typedUTF16(events: events, through: 999).count, 2_999)
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: prompt, events: events).count, 3_998)
    XCTAssertEqual(try XCTUnwrap(FieldReplayPlan.make(prompt: prompt, events: events)).actions.count, 3_998)
  }

  func testUnsegmentedRawUnitSoundDoesNotJudgeTheDisplayReplacementAsCorrectInput() {
    let events = [TypingReplayEvent(offset: 0, kind: .insert, units: [55357])]
    XCTAssertNil(FieldReplayPlan.make(prompt: "�", events: events))
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: "�", events: events).map(\.cue), [.error])
  }

  func testUnsegmentedRawSoundTracksSeparateSurrogatesAndUnitDeletion() {
    let events = [TypingReplayEvent(offset: 0, kind: .insert, units: [55357]),
      .init(offset: 0, kind: .insert, units: [56899]), .init(offset: 1, kind: .delete, units: []),
      .init(offset: 2, kind: .insert, units: [56898])]
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: "🙂", events: events).map(\.cue), [.click,.error,.click,.click])
    XCTAssertEqual(TypingReplay.typedText(events: events, through: 2), "🙂")
  }

  func testNoSpaceRawSoundUsesFlattenedKnownTargetWithoutInventingHiddenWords() {
    let events = [insert([55357,56898], snapshot: [55357,56898]),
      insert([120], snapshot: [55357,56898,120], at: 1)]
    let configuration = TestConfiguration.words(2).with(modifiers: [.noSpaces])
    XCTAssertNil(FieldReplayPlan.make(prompt: "🙂x", events: events, configuration: configuration))
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: "🙂x", events: events, configuration: configuration).map(\.cue), [.click,.click,.click])
  }

  func testMixedSoundKeepsLegacyPayloadAsOneCueAndUsesRecordedJudgmentsForNewUnits() {
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, text: "e\u{301}"),
      .init(offset: 1, kind: .insert, units: [55357,56898], forceError: true, inputCorrectness: [true,false])]
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: "e\u{301}🙂", events: events).map(\.cue), [.click,.click,.error])
  }

  func testRawSubmissionBeforeStoppedNextWordEmitsOneErrorNotALiteralReplacementMatch() {
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, units: [55357]),
      .init(offset: 1, kind: .insert, units: [32]),
      .init(offset: 2, kind: .insert, units: [120], inputStopped: true),
      .init(offset: 3, kind: .insert, units: [98])]
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: "� b", events: events).map(\.cue), [.error,.click,.error,.click])
  }

  func testRawZenSoundUsesRecordedTruthAndDoesNotPlayStoppedOrEmptyInput() {
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, units: [55357], inputStopped: true, inputCorrectness: [true]),
      .init(offset: 1, kind: .insert, text: ""), .init(offset: 2, kind: .insert, units: [97])]
    let configuration = TestConfiguration(mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: "", events: events, configuration: configuration).map(\.cue), [.click])
  }

  func testGroupedUnsegmentedUnitDeletesKeepOneCueAndDoNotRemovePriorBase() {
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, units: [97,101,769]),
      .init(offset: 1, kind: .delete, units: [], wordDeletionCount: 2),
      .init(offset: 1, kind: .delete, units: [])]
    XCTAssertEqual(TypingReplay.typedText(events: events, through: 1), "a")
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: "ae\u{301}", events: events).map(\.cue), [.click,.click,.click,.click])
  }

  func testPrimitiveRawHistoryRejoinsPairsAndKeepsUnpairedIdentityAfterDeletion() {
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, units: [55357]),
      .init(offset: 1, kind: .insert, units: [56898]), .init(offset: 2, kind: .delete, units: [])]
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFieldUTF16(events: Array(events.prefix(2))), [[55357,56898]])
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: Array(events.prefix(2))), ["🙂"])
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFieldUTF16(events: events), [[55357]])
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: events), ["�"])
  }

  func testPrimitiveRawHistoryRetainsEmptyFutureFieldAndStoppedFirstField() {
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, units: [55357,56898,32]),
      .init(offset: 1, kind: .insert, units: [98]), .init(offset: 2, kind: .delete, units: []),
      .init(offset: 3, kind: .delete, units: [])]
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFieldUTF16(events: events), [[55357,56898], []])
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFieldUTF16(events: [
      .init(offset: 0, kind: .insert, units: [55357], inputStopped: true)]), [[]])
  }

  func testPrimitiveRawProgressTrimsOnlyTheIncorrectFinalSpaceCommit() {
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, units: [55357,32])]
    XCTAssertEqual(SavedTextInputHistoryPolicy.progressWordCount(displays: ["🙂"], events: events), 0)
    XCTAssertEqual(SavedTextInputHistoryPolicy.progressWordCount(displays: ["🙂"], events: [
      .init(offset: 0, kind: .insert, units: [55357,56898,32])]), 1)
  }

  func testLegacyLargeDeletionTapePreservesGraphemesAndAcceptedTextAtScale() {
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert,
      text: "prefix" + String(repeating: "e\u{301}", count: 12_000))]
      + Array(repeating: .init(offset: 1, kind: .delete, text: ""), count: 12_000)
    let started = ProcessInfo.processInfo.systemUptime
    XCTAssertEqual(TypingReplay.typedText(events: events, through: 1), "prefix")
    XCTAssertEqual(TypingReplay.typedUTF16(events: events, through: 1), Array("prefix".utf16))
    // A reproducible before/after sample, not a flaky wall-time test budget.
    print(String(format: "Legacy replay 12000 combining-grapheme deletes, both projections: %.6f seconds",
      ProcessInfo.processInfo.systemUptime - started))
  }
}
