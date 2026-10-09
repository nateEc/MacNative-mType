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

  func testActualTapeOwnerUsesProjectedBoxesAndSeparatesMarkedCaretFromAdvance() throws {
    var session = TypingSession(configuration: .words(2), prompt: "😀 next")
    session.insertBatch("😀", at: start)
    let rendering = try render(session, marked: "XY")
    let map = try XCTUnwrap(rendering.compositionTextMap)
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    let layout = PromptFieldTextLayout(map: map, width: 1_000_000_000, font: font, lineSpacing: 0)
    let cells = TapePromptProjection.advanceCells(session: session, rendering: rendering, mode: .letter)
    let run = try XCTUnwrap(map.fieldRuns.first { $0.fieldID == 0 })
    let next = run.cells.filter { !$0.isGap }.dropFirst(2).first?.id
    let expected = TapePromptProjection.inlineAdvance(cells: cells, nextCellID: next,
      frames: layout.cellFrames, hidesExtras: false)
    for mode in [PracticeTapeMode.letter, .word] {
      let coordinator = PromptCaretMotionCoordinator()
      var config = PromptCaretNativeView.Configuration(text: rendering.text, mainOffset: nil, paceOffset: nil,
        mainStyle: .bar, paceStyle: .outline, font: font, lineSpacing: 0, rightToLeft: false,
        accent: .yellow, motion: .off, reducesMotion: true, frameRate: 30,
        attemptID: session.automaticInputAttemptID, coordinator: coordinator,
        mainGlyphID: session.promptCaretGlyphIndex, automaticallyPresents: false)
      config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
        fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: 2) }
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 80))
      let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
      window.contentView = view
      view.layer?.backgroundColor = NSColor.white.cgColor
      defer { view.stop(); window.contentView = nil; window.close() }
      view.configure(rendering: rendering, anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
        compositionField: session.promptCompositionField, mode: mode, margin: 0.25,
        smoothScroll: false, carets: config, at: 0)
      view.present(at: 0)
      XCTAssertEqual(coordinator.wordsTapeMargin, mode == .letter ? -expected : 0, accuracy: 0.001)
      let main = try XCTUnwrap(coordinator.main.position)
      let projectedMain = try XCTUnwrap(layout.mainRect(style: .bar))
      XCTAssertEqual(main.minX, mode == .letter ? 100 : 100 + projectedMain.minX, accuracy: 0.001)
      XCTAssertNotNil(coordinator.pace.position)
      let textView = try XCTUnwrap(view.subviews.first { !($0 is PromptCaretNativeView) })
      XCTAssertLessThan(textView.frame.width, 1000, "The no-wrap proposal must not create a billion-point NSView")
      view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
      let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: bitmap)
      let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      XCTAssertGreaterThan(png.count, 500)
      if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
        let name = mode == .letter ? "letter" : "word"
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("tape-projection-\(name).png"))
      }
      XCTAssertFalse(window.isVisible)
      XCTAssertEqual(session.typed, "😀")
    }
  }

  func testProjectedOwnerCanCancelCandidatesAndReturnToLegacyGeometry() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab next")
    session.insertBatch("a", at: start)
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    let coordinator = PromptCaretMotionCoordinator()
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 80))
    defer { view.stop() }
    var config = PromptCaretNativeView.Configuration(text: AttributedString(), mainOffset: nil, paceOffset: nil,
      mainStyle: .bar, paceStyle: .outline, font: font, lineSpacing: 0, rightToLeft: false,
      accent: .yellow, motion: .off, reducesMotion: true, frameRate: 30,
      attemptID: session.automaticInputAttemptID, coordinator: coordinator,
      mainGlyphID: session.promptCaretGlyphIndex, automaticallyPresents: false)
    config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: true, fraction: 1, targetGlyphID: 0) }
    for marked in ["XYZ", "", "e\u{301}"] {
      let rendering = try render(session, marked: marked)
      view.configure(rendering: rendering, anchorCharacterIndex: 1, wordAnchorCharacterIndex: 0,
        compositionField: session.promptCompositionField, mode: .letter, margin: 0.25,
        smoothScroll: false, carets: config, at: 0)
      view.present(at: 0)
      XCTAssertEqual(try XCTUnwrap(coordinator.main.position).minX, 100, accuracy: 0.001)
      XCTAssertEqual(-coordinator.wordsTapeMargin,
        ("a" as NSString).size(withAttributes: [.font: font]).width, accuracy: 0.001)
      XCTAssertNotNil(coordinator.pace.position)
    }
    let projected = try render(session, marked: "")
    let legacy = PromptRendering(text: projected.text, glyphCharacterOffsets: projected.glyphCharacterOffsets)
    view.configure(rendering: legacy, anchorCharacterIndex: 1, wordAnchorCharacterIndex: 0,
      mode: .letter, margin: 0.25, smoothScroll: false, carets: config, at: 0)
    view.present(at: 0)
    XCTAssertNotNil(coordinator.main.position)
    XCTAssertEqual(-coordinator.wordsTapeMargin,
      ("a" as NSString).size(withAttributes: [.font: font]).width, accuracy: 0.001)
  }
}
