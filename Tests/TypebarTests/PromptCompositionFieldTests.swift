import XCTest
@testable import Typebar

final class PromptCompositionFieldTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 915_000_000)

  private func attempt(_ text: String, noSpace: Bool = false, rules: InputRules = .init()) -> TypingSession {
    TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: rules, modifiers: noSpace ? [.noSpaces] : []), customText: text)
  }

  func testIncompleteCommitAndExtrasUseOnlyTheActualCurrentField() throws {
    var session = attempt("abcdef gh ij")
    session.insertBatch("a gXYZ", at: start)
    let field = try XCTUnwrap(session.promptCompositionField)
    XCTAssertEqual(field.index, 1)
    XCTAssertEqual(field.targetUTF16, Array("gh".utf16))
    XCTAssertEqual(field.inputUTF16, Array("gXYZ".utf16))
    XCTAssertEqual(field.boundary, .separated)
    XCTAssertEqual(field.targetGlyphSlices.map(\.glyphID), [7, 8])
    let plan = PromptCompositionPlan(field: field, composition: "候选", style: .replace)
    XCTAssertEqual(plan.cells.map(\.text), ["候", "选"])
    XCTAssertEqual(plan.cells.map(\.targetIndex), [nil, nil])
    XCTAssertEqual(plan.caret, .afterComposition(1))
    XCTAssertEqual(session.typed, "a gXYZ")
    XCTAssertEqual(session.completedWordCount, 1)
  }

  func testSourceReturnBelongsToTheTargetButASpaceCommitDoesNot() throws {
    let session = attempt("a\n\nb c")
    let first = try XCTUnwrap(session.promptCompositionField)
    XCTAssertEqual(first.targetUTF16, [97, 10])
    XCTAssertEqual(first.targetGlyphSlices.map(\.glyphID), [0, 1])
    var advanced = session
    advanced.insertBatch("a\n", at: start)
    let blank = try XCTUnwrap(advanced.promptCompositionField)
    XCTAssertEqual(blank.index, 1)
    XCTAssertEqual(blank.targetUTF16, [10])
    XCTAssertTrue(blank.inputUTF16.isEmpty)
    advanced.insert("\n", at: start.addingTimeInterval(1))
    let next = try XCTUnwrap(advanced.promptCompositionField)
    XCTAssertEqual(next.index, 2)
    XCTAssertEqual(next.targetUTF16, [98])
    XCTAssertEqual(next.targetGlyphSlices.map(\.glyphID), [3])
  }

  func testHiddenBoundaryUsesTheSourceDirectoryRatherThanSplittingFlattenedInput() throws {
    var session = attempt("ab CD xy", noSpace: true)
    session.insertBatch("abC", at: start)
    let field = try XCTUnwrap(session.promptCompositionField)
    XCTAssertEqual(field.index, 1)
    XCTAssertEqual(field.boundary, .hidden)
    XCTAssertEqual(field.targetUTF16, Array("CD".utf16))
    XCTAssertEqual(field.inputUTF16, [67])
    XCTAssertEqual(field.targetGlyphSlices.map(\.glyphID), [2, 3])
    let plan = PromptCompositionPlan(field: field, composition: "DXY", style: .off)
    XCTAssertEqual(plan.cells.map(\.targetIndex), [1, nil, nil])
    XCTAssertEqual(plan.cells.map(\.text), ["D", "X", "Y"])
    XCTAssertEqual(session.completedWordCount, 1)
  }

  func testRealEmptyHiddenFieldDoesNotBorrowTheNextWordsGlyph() throws {
    var session = TypingSession(configuration: .words(3).with(modifiers: [.noSpaces]),
      prompt: "abxy", noSpaceWordEndIndices: [2, 2, 4], noSpaceTargetWords: ["ab", "", "xy"])
    session.insertBatch("ab", at: start)
    let field = try XCTUnwrap(session.promptCompositionField)
    XCTAssertEqual(field.index, 1)
    XCTAssertTrue(field.targetUTF16.isEmpty)
    XCTAssertTrue(field.targetGlyphSlices.isEmpty)
    let plan = PromptCompositionPlan(field: field, composition: "XY", style: .replace)
    XCTAssertEqual(plan.cells.map(\.targetIndex), [nil, nil])
    XCTAssertEqual(plan.caret, .afterComposition(1))
    XCTAssertEqual(session.completedWordCount, 1)
    let empty = TypingSession(configuration: .words(2).with(modifiers: [.noSpaces]),
      prompt: "", noSpaceTargetWords: ["", ""])
    let emptyField = try XCTUnwrap(empty.promptCompositionField)
    XCTAssertEqual(emptyField.boundary, .hidden)
    XCTAssertEqual(emptyField.index, 0)
    XCTAssertTrue(emptyField.targetUTF16.isEmpty)
    XCTAssertTrue(emptyField.targetGlyphSlices.isEmpty)
  }

  func testCombiningMarkFieldKeepsItsPartialGlyphOwnershipAcrossAFusedBoundary() throws {
    var session = attempt("a \u{301}b tail", noSpace: true)
    session.insert("a", at: start)
    let field = try XCTUnwrap(session.promptCompositionField)
    XCTAssertEqual(field.index, 1)
    XCTAssertEqual(field.targetUTF16, [769, 98])
    XCTAssertTrue(field.inputUTF16.isEmpty)
    let partial = try XCTUnwrap(field.targetGlyphSlices.first)
    XCTAssertEqual(partial.glyphID, 0)
    XCTAssertEqual(partial.fieldUTF16Range, 0..<1)
    XCTAssertEqual(partial.glyphUTF16Range, 1..<2)
    XCTAssertFalse(partial.isWholeGlyph)
    XCTAssertTrue(field.targetGlyphSlices[1].isWholeGlyph)
    XCTAssertEqual(field.targetGlyphSlices[1].glyphID, 1)
    session.insert("\u{301}", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.promptCompositionField?.inputUTF16, [769])
    XCTAssertEqual(session.typed, "a\u{301}")
    XCTAssertEqual(session.promptCompositionField?.index, 1)
  }

  func testRegionalIndicatorFieldKeepsBothHalvesWithoutMovingItsSourceBoundary() throws {
    var session = attempt("🇫 🇷🇨 tail", noSpace: true)
    session.insert("🇫", at: start)
    let field = try XCTUnwrap(session.promptCompositionField)
    XCTAssertEqual(field.index, 1)
    XCTAssertEqual(field.targetUTF16, Array("🇷🇨".utf16))
    XCTAssertEqual(field.targetGlyphSlices.map(\.glyphID), [0, 1])
    XCTAssertEqual(field.targetGlyphSlices.map(\.fieldUTF16Range), [0..<2, 2..<4])
    XCTAssertEqual(field.targetGlyphSlices.map(\.glyphUTF16Range), [2..<4, 0..<2])
    XCTAssertEqual(field.targetGlyphSlices.map(\.isWholeGlyph), [false, true])
  }

  func testLiteralSpaceInsideAFusedGlyphStillSeparatesTheRawSourceFields() throws {
    var session = attempt("a \u{301}b tail")
    session.insertBatch("a ", at: start)
    let field = try XCTUnwrap(session.promptCompositionField)
    XCTAssertEqual(field.index, 1)
    XCTAssertEqual(field.targetUTF16, [769, 98])
    XCTAssertEqual(field.boundary, .separated)
    XCTAssertEqual(field.targetGlyphSlices.first?.glyphID, 1)
    XCTAssertEqual(field.targetGlyphSlices.first?.glyphUTF16Range, 1..<2)
    XCTAssertEqual(field.targetGlyphSlices.first?.isWholeGlyph, false)
  }

  func testStoppedSurrogateIsRetainedAsRawInputRatherThanReplacementCharacter() throws {
    var session = attempt("🙂x tail", noSpace: true, rules: .init(stopOnErrorMode: .letter))
    session.insertBatch("🙃", at: start)
    let field = try XCTUnwrap(session.promptCompositionField)
    XCTAssertEqual(field.targetUTF16, Array("🙂x".utf16))
    XCTAssertEqual(field.inputUTF16, [55357])
    XCTAssertNotEqual(field.inputUTF16, Array(session.typed.utf16))
    let plan = PromptCompositionPlan(field: field, composition: "文", style: .replace)
    XCTAssertEqual(plan.referenceLetterUnitIndex, 2)
    session.bailOut(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.result()?.inputMetrics?.retainedUnits, 1)
    XCTAssertNil(session.promptCompositionField)
  }

  func testZenUsesItsActualCurrentFieldAndDoesNotInventTargetIdentities() throws {
    var session = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "")
    session.insertBatch("one\n🙂", at: start)
    let field = try XCTUnwrap(session.promptCompositionField)
    XCTAssertEqual(field.index, 1)
    XCTAssertEqual(field.boundary, .zen)
    XCTAssertEqual(field.inputUTF16, Array("🙂".utf16))
    XCTAssertTrue(field.targetUTF16.isEmpty)
    XCTAssertTrue(field.targetGlyphSlices.isEmpty)
    let plan = PromptCompositionPlan(field: field, composition: "文", style: .below)
    XCTAssertEqual(plan.cells.map(\.text), ["文"])
    XCTAssertEqual(plan.referenceLetterUnitIndex, 3)
    XCTAssertFalse(plan.hasEmptyPlaceholder)
  }

  func testUnknownHiddenDirectoryRemainsOneUnsegmentedTarget() throws {
    var session = TypingSession(configuration: .words(2).with(modifiers: [.noSpaces]), prompt: "中文")
    session.insert("中", at: start)
    let field = try XCTUnwrap(session.promptCompositionField)
    XCTAssertEqual(field.index, 0)
    XCTAssertEqual(field.boundary, .unsegmented)
    XCTAssertEqual(field.targetUTF16, Array("中文".utf16))
    XCTAssertEqual(field.inputUTF16, Array("中".utf16))
    XCTAssertEqual(field.targetGlyphSlices.map(\.glyphID), [0, 1])
  }

  func testLegacyRetainedEndsRemainTrustedWithoutInventingADirectory() throws {
    var session = TypingSession(configuration: .words(2).with(modifiers: [.noSpaces]),
      prompt: "🦊abay", noSpaceWordEndIndices: [2, 5])
    session.insertBatch("🦊a", at: start)
    let field = try XCTUnwrap(session.promptCompositionField)
    XCTAssertEqual(field.index, 1)
    XCTAssertEqual(field.boundary, .hidden)
    XCTAssertEqual(field.targetUTF16, Array("bay".utf16))
    XCTAssertTrue(field.inputUTF16.isEmpty)
    XCTAssertEqual(field.targetGlyphSlices.map(\.glyphID), [2, 3, 4])
    session.insert("b", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.promptCompositionField?.inputUTF16, [98])
  }

  func testRetainedLeadingReturnDoesNotCreateAFakeCommittedField() throws {
    var session = attempt("\na tail", rules: .init(strictSpace: true))
    session.insert("\n", at: start)
    let field = try XCTUnwrap(session.promptCompositionField)
    XCTAssertEqual(field.index, 0)
    XCTAssertEqual(field.targetUTF16, [10])
    XCTAssertEqual(field.inputUTF16, [10])
    XCTAssertEqual(session.completedWordCount, 0)
    let plan = PromptCompositionPlan(field: field, composition: "候", style: .replace)
    XCTAssertEqual(plan.cells.map(\.targetIndex), [nil])
    XCTAssertEqual(plan.caret, .afterComposition(0))
    XCTAssertEqual(session.typed, "\n")
  }

  func testClearedTerminalElementDoesNotExposeItsOldValidationInput() throws {
    var session = TypingSession(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(stopOnErrorMode: .letter), modifiers: [.noSpaces]),
      prompt: "ab", noSpaceTargetWords: ["ab"])
    session.insertBatch("abx", at: start)
    XCTAssertEqual(session.outcome, .active)
    let field = try XCTUnwrap(session.promptCompositionField)
    XCTAssertEqual(field.index, 0)
    XCTAssertTrue(field.inputUTF16.isEmpty)
    XCTAssertEqual(field.targetUTF16, [97, 98])
    let plan = PromptCompositionPlan(field: field, composition: "XYZ", style: .replace)
    XCTAssertEqual(plan.referenceLetterUnitIndex, 3)
    XCTAssertEqual(plan.replacedTargetRange, 0..<2)
    XCTAssertTrue(session.typed.isEmpty)
    session.bailOut(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.result()?.inputMetrics?.correctAttempts, 2)
    XCTAssertEqual(session.result()?.replayEvents.last?.inputField?.valueUTF16, [])
  }

  func testDeletionAndRepeatedAttemptRecomputeFieldsWithoutRetainingCandidateState() throws {
    var session = attempt("ab cd", rules: .init(freedomMode: true))
    session.insertBatch("ab c", at: start)
    let before = try XCTUnwrap(session.promptCompositionField)
    _ = PromptCompositionPlan(field: before, composition: "XYZ", style: .replace)
    session.deleteBackward(at: start.addingTimeInterval(1))
    session.deleteBackward(at: start.addingTimeInterval(2))
    let reopened = try XCTUnwrap(session.promptCompositionField)
    XCTAssertEqual(reopened.index, 0)
    XCTAssertEqual(reopened.inputUTF16, [97, 98])
    XCTAssertEqual(reopened.targetUTF16, [97, 98])
    let repeated = session.repeatedAttempt()
    let reset = try XCTUnwrap(repeated.promptCompositionField)
    XCTAssertEqual(reset.index, 0)
    XCTAssertTrue(reset.inputUTF16.isEmpty)
    XCTAssertNotEqual(repeated.automaticInputAttemptID, session.automaticInputAttemptID)
    XCTAssertEqual(session.typed, "ab")
  }
}
