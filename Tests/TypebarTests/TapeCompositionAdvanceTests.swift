import AppKit
import XCTest
@testable import Typebar

@MainActor final class TapeCompositionAdvanceTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 917_100_000)

  private func render(_ session: TypingSession, marked: String) throws -> PromptRendering {
    let presentation = try XCTUnwrap(PromptCompositionPresentation(session: session,
      composition: marked, style: .replace))
    return presentation.render { _, glyph, cell in
      AttributedString(cell?.text ?? String(glyph.character))
    }
  }

  func testAcceptedPrefixDoesNotAdvanceToMarkedCandidateEnd() throws {
    var session = TypingSession(configuration: .words(2), prompt: "abcd next")
    session.insertBatch("a", at: start)
    let rendering = try render(session, marked: "XYZ")
    let cells = TapePromptProjection.advanceCells(session: session, rendering: rendering, mode: .letter)
    XCTAssertEqual(cells.map(\.text), [AttributedString("a")])
    XCTAssertNotEqual(cells.last?.id, rendering.compositionTextMap?.caret?.cellID)
    XCTAssertEqual(session.typed, "a")
  }

  func testUtf16SnapshotCountSelectsDisplayedSlotsRatherThanGraphemeCount() throws {
    var session = TypingSession(configuration: .words(2), prompt: "😀 next")
    session.insertBatch("😀", at: start)
    let rendering = try render(session, marked: "XY")
    let run = try XCTUnwrap(rendering.compositionTextMap?.fieldRuns.first { $0.fieldID == 0 })
    let cells = TapePromptProjection.advanceCells(session: session, rendering: rendering, mode: .letter)
    XCTAssertEqual(session.promptCompositionField?.inputUTF16.count, 2)
    XCTAssertEqual(cells.map(\.id), Array(run.cells.filter { !$0.isGap }.prefix(2)).map(\.id))
    XCTAssertEqual(cells.count, 2, "The pinned source loops input.length over displayed letter nodes")
    XCTAssertTrue(cells.contains { $0.id < 0 }, "The selected prefix may include a virtual marked slot")
  }

  func testEmptyInputAndWordModeDoNotConsumeCandidateSlots() throws {
    let session = TypingSession(configuration: .words(2), prompt: "ab next")
    let rendering = try render(session, marked: "候选")
    for mode in [PracticeTapeMode.off, .word, .letter] {
      XCTAssertTrue(TapePromptProjection.advanceCells(session: session, rendering: rendering, mode: mode).isEmpty)
    }
  }

  func testAdvanceUsesActiveFieldNotEarlierCommittedFieldOrFutureText() throws {
    var session = TypingSession(configuration: .words(3), prompt: "a bc tail")
    session.insertBatch("a b", at: start)
    let rendering = try render(session, marked: "XYZ")
    let map = try XCTUnwrap(rendering.compositionTextMap)
    let cells = TapePromptProjection.advanceCells(session: session, rendering: rendering, mode: .letter)
    let active = try XCTUnwrap(map.fieldRuns.first { $0.fieldID == session.promptCompositionField?.index })
    XCTAssertEqual(cells.map(\.id), [try XCTUnwrap(active.cells.first { !$0.isGap }).id])
    XCTAssertEqual(cells.map(\.text), [AttributedString("b")])
    let legacy = PromptRendering(text: rendering.text, glyphCharacterOffsets: rendering.glyphCharacterOffsets)
    XCTAssertTrue(TapePromptProjection.advanceCells(session: session, rendering: legacy, mode: .letter).isEmpty)
  }
}
