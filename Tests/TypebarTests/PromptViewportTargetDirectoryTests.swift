import XCTest
@testable import Typebar

final class PromptViewportTargetDirectoryTests: XCTestCase {
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

  func testHundredThousandWordDirectoryMaterializesOnlyRequestedFields() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["TYPEBAR_ENDURANCE_TESTS"] == "1",
      "Run explicitly with TYPEBAR_ENDURANCE_TESTS=1")
    let words = 100_001
    let prompt = Array(repeating: "oak", count: words).joined(separator: " ")
    let session = TypingSession(configuration: .words(words), prompt: prompt)
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
