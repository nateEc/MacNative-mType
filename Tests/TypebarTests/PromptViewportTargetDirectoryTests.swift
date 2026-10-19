import XCTest
@testable import Typebar

final class PromptViewportTargetDirectoryTests: XCTestCase {
  func testWindowWordStatesMatchFullCompositionAcrossInputAndProviderBoundaries() throws {
    let prompt = "alpha beta gamma delta"
    var wrong = TypingSession(configuration: .words(4), prompt: prompt)
    wrong.insert("x", at: Date(timeIntervalSinceReferenceDate: 920_300_000))
    var committed = TypingSession(configuration: .words(4), prompt: prompt)
    committed.insertBatch("alxha ", at: Date(timeIntervalSinceReferenceDate: 920_300_001))
    var blind = TypingSession(configuration: .words(4, rules: .init(blindMode: true)), prompt: prompt)
    blind.insertBatch("alxha ", at: Date(timeIntervalSinceReferenceDate: 920_300_002))
    let source = ["north\nsouth ", "harbor ", "tail"]
    var provider = TypingSession(configuration: .words(4), prompt: source.joined(),
      sourceFields: source)
    provider.insert("n", at: Date(timeIntervalSinceReferenceDate: 920_300_003))
    let separated = [" north\nsouth ", "", " harbor  ", "tail"]
    let unusual = TypingSession(configuration: .words(5), prompt: separated.joined(),
      sourceFields: separated)
    for session in [TypingSession(configuration: .words(4), prompt: prompt),
      wrong, committed, blind, provider, unusual] {
      let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
      let presentation = try XCTUnwrap(PromptCompositionPresentation(session: session,
        composition: "", style: .replace))
      let full = presentation.words
      for range in [0..<min(2, directory.fieldCount),
        max(0, directory.fieldCount - 2)..<directory.fieldCount] {
        let window = try XCTUnwrap(directory.materializeWordStates(fields: range,
          session: session))
        XCTAssertEqual(window.activeWordIndex, full.firstIndex { $0.phase == .active })
        XCTAssertEqual(window.words.map(\.index), Array(range))
        XCTAssertEqual(window.words.map(\.value), Array(full[range]))
      }
    }
  }

  func testDistantWordOrdinalsUseLiteralSeparatorsAcrossProviderFields() throws {
    let fields = [" north\nsouth ", "", " harbor  ", "tail"]
    let prompt = fields.joined()
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session:
      TypingSession(configuration: .words(5), prompt: prompt, sourceFields: fields)))
    let units = Array(prompt.utf16)
    for index in 0..<directory.fieldCount {
      let slice = try XCTUnwrap(directory.materialize(fields: index..<(index + 1)))
      for cell in slice.cells {
        XCTAssertEqual(directory.fieldIndex(containingUTF16: cell.id), index)
        let expected = units[..<cell.id].filter { $0 == 32 || $0 == 10 }.count
        XCTAssertEqual(cell.wordOrdinal, expected, "field=\(index) id=\(cell.id)")
      }
    }
    XCTAssertNil(directory.fieldIndex(containingUTF16: -1))
    XCTAssertNil(directory.fieldIndex(containingUTF16: units.count))
    XCTAssertNil(directory.fieldIndex(containingUTF16: Int.max))
  }

  func testWindowStateAfterDistantCursorMatchesFullHighlighting() throws {
    var session = TypingSession(configuration: .words(10).with(modifiers: [.focusNextWord]),
      prompt: "one two three four five six seven eight nine ten")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    session.insertBatch("one two three four five six ",
      at: Date(timeIntervalSinceReferenceDate: 920_000_017))
    let full = session.promptGlyphs
    for range in [0..<2, 6..<10, 0..<2] {
      let cells = try XCTUnwrap(directory.materializeStates(fields: range, session: session))
      XCTAssertEqual(cells.map(\.glyph), cells.map { full[$0.id] })
    }
  }

  func testFirstDistantAndReturningFieldsKeepGlobalIdentityAndSourceText() throws {
    for prompt in ["alpha beta gamma delta", "one two\nthree four"] {
      let session = TypingSession(configuration: .words(4), prompt: prompt)
      let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
      let full = try XCTUnwrap(session.promptCompositionProjection(composition: "", style: .off))
      XCTAssertEqual(directory.attemptID, session.automaticInputAttemptID)
      XCTAssertEqual(directory.targetUTF16, Array(prompt.utf16))
      XCTAssertEqual(directory.fieldCount, full.fields.count)
      for range in [0..<2, 2..<4, 0..<2] {
        let slice = try XCTUnwrap(directory.materialize(fields: range))
        let expected = full.cells.filter { $0.sourceFieldIndex.map(range.contains) == true }
        XCTAssertEqual(slice.cells.map(\.id), expected.map(\.id))
        XCTAssertEqual(slice.cells.map(\.unit), expected.flatMap(\.displayUTF16))
        XCTAssertEqual(slice.cells.map(\.fieldIndex), expected.compactMap(\.sourceFieldIndex))
        XCTAssertEqual(slice.fields.map(\.index), Array(range))
        XCTAssertEqual(slice.fields.map(\.targetUTF16Range), full.fields[range].map(\.targetUTF16Range))
        XCTAssertEqual(slice.fields.map(\.structuralReturnCount),
          full.fields[range].map(\.structuralReturnCount))
      }
    }
  }

  func testNewInputSnapshotUpdatesStateWithoutChangingTargetIdentity() throws {
    var session = TypingSession(configuration: .words(4), prompt: "alpha beta gamma delta")
    let before = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    session.insert("a", at: Date(timeIntervalSinceReferenceDate: 920_000_000))
    let after = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    XCTAssertEqual(before.attemptID, after.attemptID)
    XCTAssertEqual(before.materialize(fields: 0..<2)?.cells.map(\.id),
      after.materialize(fields: 0..<2)?.cells.map(\.id))
    XCTAssertNotEqual(TypingSession(configuration: .words(4), prompt: session.prompt).promptGlyphs.first,
      session.promptGlyphs.first)
    XCTAssertEqual(before.materialize(fields: 0..<1), after.materialize(fields: 0..<1))
    XCTAssertNotEqual(after.attemptID, session.repeatedAttempt().automaticInputAttemptID)
  }

  func testPromptTargetIdentityKeepsInputWindowButRejectsSameAttemptAfterLiveGrowth() throws {
    let opening = ["north ", "harbor "]
    var session = TypingSession(configuration: .words(5).with(modifiers: [.poetryStream]),
      prompt: opening.joined(), sourceFields: opening, streamsLiveContent: true)
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let initialTargetID = session.promptTargetID
    XCTAssertNotNil(directory.materializeStates(fields: 0..<1, session: session))
    session.insert("n", at: Date(timeIntervalSinceReferenceDate: 920_000_016))
    XCTAssertEqual(session.promptTargetID, initialTargetID)
    XCTAssertNotNil(directory.materializeStates(fields: 0..<1, session: session))
    XCTAssertTrue(session.appendLiveContent(.init(text: "third fourth", noSpaceBoundarySource: nil)))
    XCTAssertNotEqual(session.promptTargetID, initialTargetID)
    XCTAssertNil(directory.materializeStates(fields: 0..<1, session: session))
    let refreshed = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    XCTAssertEqual(refreshed.attemptID, directory.attemptID)
    XCTAssertNotNil(refreshed.materializeStates(fields: 0..<1, session: session))
  }

  func testCopiedAttemptBranchesCannotReuseAnotherTargetsDirectory() throws {
    let opening = ["north ", "harbor "]
    let base = TypingSession(configuration: .words(5).with(modifiers: [.poetryStream]),
      prompt: opening.joined(), sourceFields: opening, streamsLiveContent: true)
    var left = base, right = base
    XCTAssertTrue(left.appendLiveContent(.init(text: "third fourth", noSpaceBoundarySource: nil)))
    XCTAssertTrue(right.appendLiveContent(.init(text: "other planet", noSpaceBoundarySource: nil)))
    XCTAssertEqual(left.prompt.utf16.count, right.prompt.utf16.count)
    XCTAssertNotEqual(left.promptTargetID, right.promptTargetID)
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: left))
    XCTAssertNotNil(directory.materializeStates(fields: 0..<1, session: left))
    XCTAssertNil(directory.materializeStates(fields: 0..<1, session: right),
      "Equal append counts do not prove the target bytes match across copied sessions")
  }

  func testVisibleStateFollowsInputAndDistantWindowWithoutFullProjection() throws {
    var session = TypingSession(configuration: .words(4), prompt: "alpha beta gamma delta")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    for input in ["", "a", "x", "l"] {
      if !input.isEmpty { session.insert(input, at: Date(timeIntervalSinceReferenceDate: 920_000_001)) }
      let full = session.promptGlyphs
      for range in [0..<2, 2..<4, 0..<2] {
        let slice = try XCTUnwrap(directory.materializeStates(fields: range, session: session))
        XCTAssertEqual(slice.map(\.id), directory.materialize(fields: range)?.cells.map(\.id))
        XCTAssertEqual(slice.map(\.glyph), slice.map { full[$0.id] })
      }
    }
  }

  func testVisibleStateRejectsStaleAttemptAndUnprovenExtraInput() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    XCTAssertNotNil(directory.materializeStates(fields: 0..<1, session: session))
    XCTAssertNil(directory.materializeStates(fields: 0..<1, session: session.repeatedAttempt()))
    session.insertBatch("abXYZ", at: Date(timeIntervalSinceReferenceDate: 920_000_002))
    XCTAssertNil(directory.materializeStates(fields: 0..<1, session: session))
  }

  func testVisibilityModifiersAndBlindColorOnlyRequestedFields() throws {
    let modifiers: [TestModifier?] = [nil, .focusCurrentWord, .focusNextWord,
      .focusTwoWords, .focusThreeWords, .readAheadEasy, .readAhead,
      .readAheadHard, .memory, .simonSays]
    for modifier in modifiers {
      var configuration = TestConfiguration.words(5)
      if let modifier { configuration = configuration.with(modifiers: [modifier]) }
      var session = TypingSession(configuration: configuration, prompt: "ab cd ef gh ij")
      let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
      for input in ["", "a", "x"] {
        if !input.isEmpty { session.insert(input, at: Date(timeIntervalSinceReferenceDate: 920_000_006)) }
        let full = session.promptGlyphs
        for fields in [0..<2, 3..<5, 0..<2] {
          let slice = try XCTUnwrap(directory.materializeStates(fields: fields, session: session),
            "modifier=\(String(describing: modifier)) input=\(input)")
          XCTAssertEqual(slice.map(\.glyph), slice.map { full[$0.id] },
            "modifier=\(String(describing: modifier)) input=\(input)")
        }
      }
    }
    var blindRules = InputRules()
    blindRules.blindMode = true
    var blindConfiguration = TestConfiguration.words(3)
    blindConfiguration.rules = blindRules
    var blind = TypingSession(configuration: blindConfiguration, prompt: "ab cd ef")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: blind))
    blind.insert("x", at: Date(timeIntervalSinceReferenceDate: 920_000_007))
    for fields in [0..<1, 2..<3] {
      let slice = try XCTUnwrap(directory.materializeStates(fields: fields, session: blind))
      let full = blind.promptGlyphs
      XCTAssertEqual(slice.map(\.glyph), slice.map { full[$0.id] })
    }
  }

  func testVisibilityOrdinalHandlesEmptyFieldsAndStructuralReturns() throws {
    let prompt = " a  b\nc d "
    for modifier in [TestModifier.focusCurrentWord, .focusNextWord,
      .readAheadEasy, .readAheadHard] {
      var session = TypingSession(configuration: .words(6).with(modifiers: [modifier]),
        prompt: prompt)
      let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
      for input in ["", " ", "a", " ", " ", "b", "\n"] {
        if !input.isEmpty { session.insert(input, at: Date(timeIntervalSinceReferenceDate: 920_000_008)) }
        let full = session.promptGlyphs
        for index in 0..<directory.fieldCount {
          let slice = try XCTUnwrap(directory.materializeStates(fields: index..<(index + 1),
            session: session))
          XCTAssertEqual(slice.map(\.glyph), slice.map { full[$0.id] },
            "modifier=\(modifier) input=\(input) field=\(index)")
        }
      }
    }
  }

  func testProviderFieldContainingReturnDoesNotPretendFieldIndexIsWordOrdinal() throws {
    let fields = ["north\nsouth ", "harbor ", "tail"]
    for modifier in [TestModifier.focusCurrentWord, .readAheadEasy] {
      var session = TypingSession(configuration: .words(4).with(modifiers: [modifier]),
        prompt: fields.joined(), sourceFields: fields)
      let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
      for input in ["", "n"] {
        if !input.isEmpty { session.insert(input, at: Date(timeIntervalSinceReferenceDate: 920_000_015)) }
        let full = session.promptGlyphs
        for index in 0..<directory.fieldCount {
          let slice = try XCTUnwrap(directory.materializeStates(fields: index..<(index + 1),
            session: session))
          XCTAssertEqual(slice.map(\.glyph), slice.map { full[$0.id] },
            "modifier=\(modifier) field=\(index) input=\(input)")
        }
      }
    }
  }

  func testForcedErrorRetainsTypedCharacterAndStoppedInputFallsBack() throws {
    var forced = TypingSession(configuration: .words(2), prompt: "ab cd")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: forced))
    forced.insert("a", forceError: true, at: Date(timeIntervalSinceReferenceDate: 920_000_009))
    let visible = try XCTUnwrap(directory.materializeStates(fields: 0..<1, session: forced))
    let full = forced.promptGlyphs
    XCTAssertEqual(visible.map(\.glyph), visible.map { full[$0.id] })
    XCTAssertEqual(visible.first?.glyph.state, .incorrect)
    XCTAssertEqual(visible.first?.glyph.typedCharacter, "a")

    var stopped = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .letter)), prompt: "ab cd")
    let stoppedDirectory = try XCTUnwrap(PromptViewportTargetDirectory(session: stopped))
    stopped.insert("a", at: Date(timeIntervalSinceReferenceDate: 920_000_010))
    stopped.insert("x", at: Date(timeIntervalSinceReferenceDate: 920_000_011))
    XCTAssertNil(stoppedDirectory.materializeStates(fields: 0..<1, session: stopped),
      "A transient rejected key changes presentation without changing accepted text")
  }

  func testBlindCommitStateTracksLiveToggleAndWordReentry() throws {
    var session = TypingSession(configuration: .words(3, rules: .init(blindMode: true)),
      prompt: "amber bay cedar")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    session.insertBatch("am ", at: Date(timeIntervalSinceReferenceDate: 920_000_012))
    session.setBlindMode(false)
    for step in 0..<3 {
      let visible = try XCTUnwrap(directory.materializeStates(fields: 0..<2, session: session))
      let full = session.promptGlyphs
      XCTAssertEqual(visible.map(\.glyph), visible.map { full[$0.id] })
      if step == 0 { session.deleteBackward(at: Date(timeIntervalSinceReferenceDate: 920_000_013)) }
      if step == 1 { session.insert(" ", at: Date(timeIntervalSinceReferenceDate: 920_000_014)) }
    }
  }

  func testVisibleStateMatchesReturnDeletionAndWrongInput() throws {
    var session = TypingSession(configuration: .words(3), prompt: "a\nb cd")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    for input in ["a", "\n", "x"] {
      session.insert(input, at: Date(timeIntervalSinceReferenceDate: 920_000_003))
      let full = session.promptGlyphs
      for range in [0..<1, 1..<3] {
        let slice = try XCTUnwrap(directory.materializeStates(fields: range, session: session))
        XCTAssertEqual(slice.map(\.glyph), slice.map { full[$0.id] })
      }
    }
    session.deleteBackward(at: Date(timeIntervalSinceReferenceDate: 920_000_004))
    let slice = try XCTUnwrap(directory.materializeStates(fields: 1..<3, session: session))
    XCTAssertEqual(slice.map(\.glyph), slice.map { session.promptGlyphs[$0.id] })
  }

  func testHundredThousandWordDirectoryMaterializesOnlyRequestedFields() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["TYPEBAR_ENDURANCE_TESTS"] == "1",
      "Run explicitly with TYPEBAR_ENDURANCE_TESTS=1")
    let words = 100_001
    let prompt = Array(repeating: "oak", count: words).joined(separator: " ")
    var session = TypingSession(configuration: .words(words), prompt: prompt)
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    XCTAssertEqual(directory.fieldCount, words)
    XCTAssertEqual(directory.targetUTF16, Array(prompt.utf16))
    let first = try XCTUnwrap(directory.materialize(fields: 0..<2))
    let distant = try XCTUnwrap(directory.materialize(fields: (words - 2)..<words))
    let returned = try XCTUnwrap(directory.materialize(fields: 0..<2))
    XCTAssertEqual(first, returned)
    XCTAssertEqual(first.cells.map(\.id), Array(0..<8))
    XCTAssertEqual(distant.cells.count, 7)
    XCTAssertEqual(distant.cells.last?.id, prompt.utf16.count - 1)
    XCTAssertEqual(distant.cells.map(\.unit), Array("oak oak".utf16))
    XCTAssertEqual(distant.cells.first?.wordOrdinal, words - 2)
    XCTAssertEqual(distant.cells.last?.wordOrdinal, words - 1)
    let distantWords = try XCTUnwrap(directory.materializeWordStates(
      fields: (words - 2)..<words, session: session))
    XCTAssertEqual(distantWords.words.map(\.index), [words - 2, words - 1])
    XCTAssertEqual(distantWords.words.map(\.value.range),
      [(prompt.utf16.count - 7)..<(prompt.utf16.count - 4),
        (prompt.utf16.count - 3)..<prompt.utf16.count])
    var paintedIDs: [Int] = []
    let distantRuns = try XCTUnwrap(directory.materializeFieldRuns(fields: (words - 2)..<words,
      session: session) { id, glyph in
      paintedIDs.append(id)
      return AttributedString(String(glyph.character))
    })
    XCTAssertEqual(distantRuns.flatMap(\.cells).count, 7)
    XCTAssertEqual(paintedIDs, distant.cells.map(\.id))
    XCTAssertEqual(distantRuns.map(\.fieldID), [words - 2, words - 1])
    let state = try XCTUnwrap(directory.materializeStates(fields: (words - 2)..<words,
      session: session))
    XCTAssertEqual(state.count, 7)
    XCTAssertTrue(state.allSatisfy { $0.glyph.state == .pending })
    session.insert("o", at: Date(timeIntervalSinceReferenceDate: 920_000_005))
    let firstAfterInput = try XCTUnwrap(directory.materializeStates(fields: 0..<2, session: session))
    let distantAfterInput = try XCTUnwrap(directory.materializeStates(fields: (words - 2)..<words,
      session: session))
    XCTAssertEqual(firstAfterInput.first?.glyph.state, .correct)
    XCTAssertEqual(firstAfterInput.dropFirst().first?.glyph.state, .current)
    XCTAssertEqual(distantAfterInput.map(\.glyph), state.map(\.glyph))
    let focused = TypingSession(configuration: .words(words).with(modifiers: [.focusCurrentWord]),
      prompt: prompt)
    let focusedDirectory = try XCTUnwrap(PromptViewportTargetDirectory(session: focused))
    let focusedDistant = try XCTUnwrap(focusedDirectory.materializeStates(
      fields: (words - 2)..<words, session: focused))
    XCTAssertEqual(focusedDistant.count, 7)
    XCTAssertTrue(focusedDistant.allSatisfy { $0.glyph.state == .hidden })
  }

  func testUnprovenFusionAndHiddenBoundariesUseExistingFullProjection() {
    let unicode = TypingSession(configuration: .words(2), prompt: "é cafe")
    XCTAssertNil(PromptViewportTargetDirectory(session: unicode))
    let crlf = TypingSession(configuration: .words(2), prompt: "a\r\nb")
    XCTAssertNil(PromptViewportTargetDirectory(session: crlf))
    let hidden = TypingSession(configuration: .words(2).with(modifiers: [.noSpaces]),
      prompt: "abcd", noSpaceWordEndIndices: [2, 4], noSpaceTargetWords: ["ab", "cd"])
    XCTAssertNil(PromptViewportTargetDirectory(session: hidden))
  }
}
