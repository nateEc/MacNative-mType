import XCTest
@testable import Typebar

final class PromptCompositionProjectionTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 916_000_000)

  private func attempt(_ text: String, hidden: Bool = false) -> TypingSession {
    TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: hidden ? [.noSpaces] : []), customText: text)
  }

  private func projection(_ session: TypingSession, _ composition: String,
    style: CompositionDisplayStyle = .replace) throws -> PromptCompositionProjection {
    try XCTUnwrap(session.promptCompositionProjection(composition: composition, style: style))
  }

  func testMultipleMarkedSlotsConsumeOnlyTheirOwnGlobalTargets() throws {
    var session = attempt("abcdef gh")
    session.insert("a", at: start)
    let result = try projection(session, "bcX")
    XCTAssertEqual(result.cells.map(\.text).joined(), "abcXef gh")
    XCTAssertEqual(result.cells.map(\.id), Array(0..<9))
    XCTAssertEqual(result.markedCells.map(\.matchesTarget), [true, true, false])
    XCTAssertEqual(result.markedCells.map(\.sourceFieldIndex), [0, 0, 0])
    XCTAssertEqual(result.replacedTargetUTF16Range, 1..<4)
    XCTAssertEqual(result.caret, .init(cellID: 4, after: false))
    XCTAssertEqual(result.fields[1].cellIDs, [7, 8])
    XCTAssertEqual(session.typed, "a"); XCTAssertEqual(session.prompt, "abcdef gh")
  }

  func testOffAndBelowPreserveTargetInkButStillConsumeDistinctMarkedSlots() throws {
    var session = attempt("abcdef gh"); session.insert("a", at: start)
    for style in [CompositionDisplayStyle.off, .below] {
      let result = try projection(session, "XYZ", style: style)
      XCTAssertEqual(result.cells.map(\.text).joined(), session.prompt)
      XCTAssertEqual(result.markedCells.map(\.text), ["b", "c", "d"])
      XCTAssertEqual(result.caret, .init(cellID: 4, after: false))
    }
  }

  func testOverflowHasUniquePresentationIDsAndCannotBorrowTheNextField() throws {
    var session = attempt("ab CD"); session.insert("a", at: start)
    let result = try projection(session, "bXYZ")
    XCTAssertEqual(result.cells.map(\.text).joined(), "abXYZ CD")
    XCTAssertEqual(Set(result.cells.map(\.id)).count, result.cells.count)
    XCTAssertEqual(result.markedCells.first?.id, 1)
    XCTAssertTrue(result.markedCells.dropFirst().allSatisfy { $0.id < 0 && $0.sourceSlices.isEmpty })
    XCTAssertEqual(result.fields[1].cellIDs, [3, 4])
    XCTAssertEqual(result.caret, .init(cellID: try XCTUnwrap(result.markedCells.last).id, after: true))
    XCTAssertEqual(result.canonicalAliases[3], [3])
  }

  func testAcceptedExtrasRemainBeforeCandidateOverflowAndTheirCommitGap() throws {
    var session = attempt("abcdef gh ij"); session.insertBatch("a gXYZ", at: start)
    let result = try projection(session, "候选")
    let extras = session.promptWordPresentations[1].extraGlyphIndices
    XCTAssertFalse(extras.isEmpty)
    let ids = result.cells.map(\.id)
    let firstMarked = try XCTUnwrap(result.markedCells.first)
    let markedIndex = try XCTUnwrap(ids.firstIndex(of: firstMarked.id))
    for id in extras { XCTAssertLessThan(try XCTUnwrap(ids.firstIndex(of: id)), markedIndex) }
    XCTAssertLessThan(markedIndex, try XCTUnwrap(ids.firstIndex(of: 9)))
    XCTAssertTrue(result.markedCells.allSatisfy { $0.sourceSlices.isEmpty && $0.sourceFieldIndex == 1 })
    XCTAssertEqual(result.fields[2].cellIDs, [10, 11])
    XCTAssertEqual(session.typed, "a gXYZ")
  }

  func testEmptyHiddenFieldOwnsCandidatesWithoutMovingFutureTargetIDs() throws {
    var session = TypingSession(configuration: .words(3).with(modifiers: [.noSpaces]),
      prompt: "abxy", noSpaceWordEndIndices: [2, 2, 4], noSpaceTargetWords: ["ab", "", "xy"])
    session.insertBatch("ab", at: start)
    let result = try projection(session, "XY")
    XCTAssertEqual(result.cells.map(\.text).joined(), "abXYxy")
    XCTAssertEqual(result.fields.map(\.targetUTF16Range), [0..<2, 2..<2, 2..<4])
    XCTAssertEqual(result.fields[1].cellIDs, result.markedCells.map(\.id))
    XCTAssertEqual(result.fields[2].cellIDs, [2, 3])
    XCTAssertTrue(result.markedCells.allSatisfy { $0.sourceSlices.isEmpty })
  }

  func testFusedCombiningBoundaryPreservesTheOtherFieldsRawFragment() throws {
    var session = attempt("a \u{301}b tail", hidden: true); session.insert("a", at: start)
    let result = try projection(session, "X")
    XCTAssertEqual(result.cells.map(\.displayUTF16).flatMap { $0 }, Array("aXbtail".utf16))
    let first = try XCTUnwrap(result.cells.first), marked = try XCTUnwrap(result.markedCells.first)
    XCTAssertLessThan(first.id, 0); XCTAssertLessThan(marked.id, 0); XCTAssertNotEqual(first.id, marked.id)
    XCTAssertEqual(first.sourceFieldIndex, 0); XCTAssertEqual(marked.sourceFieldIndex, 1)
    XCTAssertEqual(first.sourceSlices.map(\.glyphUTF16Range), [0..<1])
    XCTAssertEqual(marked.sourceSlices.map(\.glyphUTF16Range), [1..<2])
    XCTAssertEqual(result.canonicalAliases[0], [first.id, marked.id])
    XCTAssertEqual(result.caret, .init(cellID: 1, after: false))
    XCTAssertEqual(session.prompt, "a\u{301}btail")
  }

  func testOneFieldCharacterCanConsumePiecesOfTwoCanonicalFlagGlyphs() throws {
    var session = attempt("🇫 🇷🇨 tail", hidden: true); session.insert("🇫", at: start)
    let result = try projection(session, "候")
    XCTAssertEqual(result.cells.map(\.displayUTF16).flatMap { $0 }, Array("🇫候tail".utf16))
    let marked = try XCTUnwrap(result.markedCells.first)
    XCTAssertEqual(marked.sourceSlices.map(\.glyphID), [0, 1])
    XCTAssertEqual(marked.sourceSlices.map(\.glyphUTF16Range), [2..<4, 0..<2])
    XCTAssertEqual(result.canonicalAliases[1], [marked.id])
    XCTAssertEqual(result.caret, .init(cellID: marked.id, after: true))
    XCTAssertEqual(Set(result.cells.map(\.id)).count, result.cells.count)
  }

  func testOrdinarySpaceFusedWithAMarkRetainsItsSeparateFieldOwnership() throws {
    var session = attempt("a \u{301}b tail"); session.insertBatch("a ", at: start)
    let result = try projection(session, "X")
    XCTAssertEqual(result.cells.map(\.displayUTF16).flatMap { $0 }, Array("a Xb tail".utf16))
    let space = try XCTUnwrap(result.cells.first { $0.displayUTF16 == [32] })
    XCTAssertEqual(space.sourceFieldIndex, 0)
    XCTAssertEqual(space.sourceSlices.map(\.glyphID), [1])
    XCTAssertEqual(space.sourceSlices.map(\.glyphUTF16Range), [0..<1])
    XCTAssertEqual(result.markedCells.first?.sourceSlices.map(\.glyphUTF16Range), [1..<2])
    XCTAssertNotEqual(space.id, result.markedCells.first?.id)
  }

  func testZenRemovesItsTrailingCaretPlaceholderDuringCompositionOnly() throws {
    var session = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "")
    session.insertBatch("one\n🙂", at: start)
    for style in CompositionDisplayStyle.allCases {
      let result = try projection(session, "中文", style: style)
      XCTAssertEqual(result.cells.map(\.text).joined(), "one\n🙂中文")
      XCTAssertTrue(result.markedCells.allSatisfy { $0.sourceSlices.isEmpty && $0.sourceFieldIndex == 1 })
      XCTAssertEqual(result.caret, .init(cellID: try XCTUnwrap(result.markedCells.last).id, after: true))
    }
    let restored = try projection(session, "")
    XCTAssertEqual(restored.cells.map(\.id), Array(session.promptGlyphs.indices))
    XCTAssertEqual(restored.cells.last?.text, " ")
    XCTAssertEqual(session.typed, "one\n🙂")
  }

  func testControlReplacementKeepsTargetAssociationWithoutCreatingATargetForOverflow() throws {
    let result = try projection(attempt("a\n\nb c"), "X\t ")
    XCTAssertEqual(result.markedCells.map(\.text), ["X", "\t", "_"])
    XCTAssertEqual(result.markedCells[1].sourceSlices.map(\.glyphID), [1])
    XCTAssertTrue(result.markedCells[2].sourceSlices.isEmpty)
    XCTAssertEqual(result.fields[1].cellIDs, [2])
    XCTAssertEqual(result.caret, .init(cellID: result.markedCells[2].id, after: true))
  }

  func testCancellationRestoresRawFusedTargetAndNeverAliasesCellIDs() throws {
    var session = attempt("a \u{301}b tail", hidden: true); session.insert("a", at: start)
    let result = try projection(session, "")
    XCTAssertEqual(result.cells.map(\.displayUTF16).flatMap { $0 }, Array(session.prompt.utf16))
    XCTAssertTrue(result.markedCells.isEmpty)
    XCTAssertEqual(Set(result.cells.map(\.id)).count, result.cells.count)
    XCTAssertEqual(result.fields[0].cellIDs.count, 1)
    XCTAssertEqual(result.fields[1].cellIDs.count, 2)
    XCTAssertEqual(result.caret?.cellID, result.fields[1].cellIDs.first)
    XCTAssertEqual(result.caret?.after, false)
  }

  func testLegacyEndsAndUnsegmentedTargetsKeepTheirRealFieldDirectories() throws {
    var legacy = TypingSession(configuration: .words(2).with(modifiers: [.noSpaces]),
      prompt: "🦊abay", noSpaceWordEndIndices: [2, 5])
    legacy.insertBatch("🦊a", at: start)
    let result = try projection(legacy, "b")
    XCTAssertEqual(result.fields.map(\.targetUTF16Range), [0..<3, 3..<6])
    XCTAssertEqual(result.markedCells.first?.sourceFieldIndex, 1)
    let flat = TypingSession(configuration: .words(2).with(modifiers: [.noSpaces]), prompt: "中文")
    XCTAssertEqual(try projection(flat, "候").fields.map(\.targetUTF16Range), [0..<2])
  }

  func testDeletionRepeatAndFinishDoNotRetainCandidatesOrMutateTheAttempt() throws {
    var session = attempt("ab cd"); session.insert("a", at: start)
    let first = try projection(session, "候")
    XCTAssertEqual(first.replacedTargetUTF16Range, 1..<2)
    session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(try projection(session, "候").replacedTargetUTF16Range, 0..<1)
    let repeated = TypingSession(configuration: session.configuration, prompt: session.prompt)
    XCTAssertEqual(try projection(repeated, "").cells.map(\.id), Array(repeated.promptGlyphs.indices))
    XCTAssertEqual(session.typed, "")
    session.bailOut(at: start.addingTimeInterval(2))
    XCTAssertNil(session.promptCompositionProjection(composition: "候", style: .replace))
  }

  func testRetirementDropsOnlyTheRetiredFragmentOfAFusedCanonicalGlyph() throws {
    var session = attempt("a \u{301}b tail", hidden: true); session.insert("a", at: start)
    session.retirePromptWords(.init(attemptID: session.automaticInputAttemptID, firstRetainedWordIndex: 1))
    let result = try projection(session, "X")
    XCTAssertTrue(result.fields[0].isRetired)
    XCTAssertTrue(result.fields[0].cellIDs.isEmpty)
    XCTAssertEqual(result.cells.map(\.text).joined(), "Xbtail")
    XCTAssertEqual(result.canonicalAliases[0], result.markedCells.map(\.id))
    XCTAssertEqual(result.caret, .init(cellID: 1, after: false))
    XCTAssertEqual(session.typed, "a")
  }

  func testIndependentRemovedFieldDoesNotEraseFutureOrCurrentCandidates() throws {
    var session = attempt("a b c d"); session.insertBatch("a b ", at: start)
    session.removeTapePromptWords(.init(attemptID: session.automaticInputAttemptID, wordIndices: [0, 2, 3]))
    let result = try projection(session, "候")
    XCTAssertEqual(result.fields.map(\.isRemoved), [true, false, false, true])
    XCTAssertEqual(result.cells.map(\.text).joined(), "b 候 ")
    XCTAssertEqual(result.markedCells.first?.sourceFieldIndex, 2)
    XCTAssertTrue(result.fields[3].cellIDs.isEmpty)
  }

  func testLoneSurrogateInputIsNotDecodedIntoTheCandidateConsumptionOffset() throws {
    var session = TypingSession(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(stopOnErrorMode: .letter), modifiers: [.noSpaces]),
      prompt: "🙂xtail", noSpaceWordEndIndices: [2, 6], noSpaceTargetWords: ["🙂x", "tail"])
    session.insert("🙃", at: start)
    XCTAssertEqual(session.promptCompositionField?.inputUTF16, [0xD83D])
    let result = try projection(session, "XYZ")
    XCTAssertEqual(result.referenceLetterUnitIndex, 4)
    XCTAssertEqual(result.markedCells.map(\.text), ["X", "Y", "Z"])
    XCTAssertEqual(result.fields[1].cellIDs, [2, 3, 4, 5])
  }

  func testAllEmptyRawFieldsKeepTheirDirectoriesAndAnAfterCandidateAnchor() throws {
    let session = TypingSession(configuration: .words(2).with(modifiers: [.noSpaces]),
      prompt: "", noSpaceWordEndIndices: [0, 0], noSpaceTargetWords: ["", ""])
    let result = try projection(session, "XY")
    XCTAssertEqual(result.fields.map(\.targetUTF16Range), [0..<0, 0..<0])
    XCTAssertEqual(result.fields[0].cellIDs, result.markedCells.map(\.id))
    XCTAssertTrue(result.fields[1].cellIDs.isEmpty)
    XCTAssertEqual(result.caret, .init(cellID: try XCTUnwrap(result.markedCells.last).id, after: true))
  }
}
