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

  func testMeasuredAdvanceUsesVirtualSlotBoxesNotCanonicalOffsets() throws {
    var session = TypingSession(configuration: .words(2), prompt: "😀 next")
    session.insertBatch("😀", at: start)
    let rendering = try render(session, marked: "XY")
    let map = try XCTUnwrap(rendering.compositionTextMap)
    let native = PromptFieldTextLayout(map: map, width: 10000,
      font: NSFont.monospacedSystemFont(ofSize: 28, weight: .regular))
    let cells = TapePromptProjection.advanceCells(session: session, rendering: rendering, mode: .letter)
    let expected = try cells.reduce(CGFloat.zero) { $0 + (try XCTUnwrap(native.cellFrames[$1.id])).width }
    XCTAssertGreaterThan(expected, 0)
    XCTAssertEqual(TapePromptProjection.inlineAdvance(cells: cells, nextCellID: nil,
      frames: native.cellFrames, hidesExtras: false), expected)
  }

  func testAdvanceSkipsHiddenExtrasAndBacksOffLastPositiveWidthBeforeZeroSlot() {
    func cell(_ id: Int, _ state: TypingPromptCharacterState) -> PromptFieldTextRun.Cell {
      .init(id: id, glyph: .init(character: "x", state: state), text: AttributedString("x"), isGap: false)
    }
    let cells = [cell(1, .correct), cell(-1, .extra), cell(-2, .pending)]
    let frames: [Int: CGRect] = [1: .init(x: 0, y: 0, width: 11, height: 30),
      -1: .init(x: 11, y: 0, width: 17, height: 30),
      -2: .init(x: 28, y: 0, width: 0, height: 30),
      -3: .init(x: 28, y: 0, width: 0, height: 30)]
    XCTAssertEqual(TapePromptProjection.inlineAdvance(cells: cells, nextCellID: -3,
      frames: frames, hidesExtras: false), 11)
    XCTAssertEqual(TapePromptProjection.inlineAdvance(cells: cells, nextCellID: -3,
      frames: frames, hidesExtras: true), 0)
    XCTAssertEqual(TapePromptProjection.inlineAdvance(cells: cells, nextCellID: nil,
      frames: frames, hidesExtras: true), 11)
    XCTAssertEqual(TapePromptProjection.inlineAdvance(cells: [], nextCellID: -3,
      frames: frames, hidesExtras: false), 0)
  }
}
