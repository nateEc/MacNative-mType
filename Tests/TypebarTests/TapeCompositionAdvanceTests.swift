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

  func testProjectedCrossWordRetirementUsesFieldBoxesAndAcknowledgesPrefixWithoutJump() throws {
    for rtl in [false, true] { for mode in [PracticeTapeMode.letter, .word] { for legacyOffsets in [false, true] { for sharedIDs in [false, true] {
      var session = TypingSession(configuration: .words(7), prompt: "aaa bbb ccc ddd eee fff ggg")
      session.insertBatch("aaa bbb ", at: start)
      let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
      let coordinator = PromptCaretMotionCoordinator()
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 80, height: 60))
      defer { view.stop() }
      var retired: [PromptWordRetirement] = []
      func configure(at time: Double) throws {
        let original = try render(session, marked: "XYZ")
        let rendering = PromptRendering(text: original.text,
          glyphCharacterOffsets: legacyOffsets ? original.glyphCharacterOffsets : [:],
          compositionTextMap: original.compositionTextMap)
        let field = try XCTUnwrap(session.promptCompositionField)
        let config = PromptCaretNativeView.Configuration(text: rendering.text, mainOffset: nil, paceOffset: nil,
          mainStyle: .bar, paceStyle: .off, font: font, lineSpacing: 0, rightToLeft: rtl,
          accent: .yellow, motion: .off, reducesMotion: true, frameRate: 30,
          attemptID: session.automaticInputAttemptID, coordinator: coordinator,
          mainGlyphID: session.promptCaretGlyphIndex, automaticallyPresents: false)
        view.configure(rendering: rendering, anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
          compositionField: field, mode: mode, margin: 0.25, smoothScroll: false,
          retirement: .init(attemptID: session.automaticInputAttemptID, activeWordID: sharedIDs ? 0 : session.promptWordPresentations[field.index].range.lowerBound,
            characterOffsets: rendering.glyphCharacterOffsets, smoothScroll: false, reducesMotion: true,
            words: session.promptWordPresentations.enumerated().map { .init(index: $0.offset, glyphID: sharedIDs ? 0 : $0.element.range.lowerBound) },
            firstRetainedWordIndex: session.firstRetainedPromptWordIndex, onRetire: { retired.append($0) }),
          carets: config, at: time)
        view.present(at: time)
      }
      try configure(at: 0)
      session.insertBatch("ccc ", at: start.addingTimeInterval(1))
      try configure(at: 1)
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
      XCTAssertEqual(retired, [.init(attemptID: session.automaticInputAttemptID, firstRetainedWordIndex: 1)])
      guard let removal = retired.first else { continue }
      let before = try XCTUnwrap(coordinator.main.position)
      let margin = coordinator.wordsTapeMargin
      session.retirePromptWords(removal)
      try configure(at: 1)
      XCTAssertEqual(try XCTUnwrap(coordinator.main.position), before)
      let width = ("aaa " as NSString).size(withAttributes: [.font: font]).width
      XCTAssertEqual(coordinator.wordsTapeMargin - margin, rtl ? -width : width, accuracy: 0.001)
      XCTAssertEqual(coordinator.main.cumulativeTapeCorrection, rtl ? -width : width, accuracy: 0.001)
      try configure(at: 1)
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
      XCTAssertEqual(retired.count, 1)
      XCTAssertEqual(coordinator.main.cumulativeTapeCorrection, rtl ? -width : width, accuracy: 0.001)
    } } } }
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

  func testOldRepresentableAndSnapshotCannotRestoreAcknowledgedPrefix() throws {
    var session = TypingSession(configuration: .words(7), prompt: "aaa bbb ccc ddd eee fff ggg")
    session.insertBatch("aaa bbb ccc ", at: start)
    func snapshot() throws -> TapePromptProjectionSnapshot {
      let rendering = try render(session, marked: "XYZ")
      let field = try XCTUnwrap(session.promptCompositionField)
      return try XCTUnwrap(TapePromptProjection.snapshot(session: session, composition: "XYZ", rendering: rendering,
        retirement: .init(attemptID: session.automaticInputAttemptID, activeWordID: field.index,
          characterOffsets: rendering.compositionTextMap?.fieldCharacterOffsets ?? [:], smoothScroll: false, reducesMotion: true,
          words: PromptLineScrollWord.compositionFields(field), firstRetainedWordIndex: session.firstRetainedPromptWordIndex,
          onRetire: { _ in })))
    }
    let stale = try snapshot()
    session.retirePromptWords(.init(attemptID: session.automaticInputAttemptID, firstRetainedWordIndex: 1))
    XCTAssertEqual(session.firstRetainedPromptWordIndex, 1)
    let acknowledged = try snapshot()
    let motion = PromptCaretMotionCoordinator()
    let owner = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 100))
    defer { owner.stop() }
    func config(_ value: TapePromptProjectionSnapshot) -> PromptCaretNativeView.Configuration {
      .init(text: value.rendering.text, mainOffset: nil, paceOffset: nil,
      mainStyle: .bar, paceStyle: .off, font: .monospacedSystemFont(ofSize: 28, weight: .regular),
      lineSpacing: 0, rightToLeft: false, accent: .yellow, motion: .off, reducesMotion: true, frameRate: 30,
      attemptID: value.input.attemptID, coordinator: motion,
      mainGlyphID: value.input.glyphID, automaticallyPresents: false)
    }
    func configure(_ value: TapePromptProjectionSnapshot, provider: (() -> TapePromptProjectionSnapshot?)? = nil) {
      owner.configure(rendering: value.rendering, anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
        compositionField: value.field, latestProjection: provider, mode: .letter, margin: 0.25,
        smoothScroll: false, retirement: value.retirement, newlineWords: value.newlineWords ?? [], carets: config(value), at: 0)
    }
    configure(acknowledged)
    let label = owner.accessibilityLabel(), margin = motion.wordsTapeMargin, main = motion.main.position
    for provider in [false, true] {
      configure(stale, provider: provider ? { stale } : nil)
      XCTAssertEqual(owner.accessibilityLabel(), label)
      XCTAssertEqual(motion.wordsTapeMargin, margin)
      XCTAssertEqual(motion.main.position, main)
    }
    configure(stale, provider: { acknowledged })
    XCTAssertEqual(owner.accessibilityLabel(), label, "A fresh complete transaction may rescue old representable arguments")
    XCTAssertEqual(motion.wordsTapeMargin, margin)
    session = TypingSession(configuration: .words(7), prompt: "aaa bbb ccc ddd eee fff ggg")
    let restarted = try snapshot()
    XCTAssertNotEqual(restarted.input.attemptID, acknowledged.input.attemptID)
    configure(restarted)
    XCTAssertEqual(owner.accessibilityLabel(), String(restarted.rendering.text.characters))
    XCTAssertEqual(motion.wordsTapeMargin, 0)
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

  func testRTLProjectedOwnerLocksTrailingEdgeAndUsesFiniteNativeCoordinates() throws {
    var session = TypingSession(configuration: .words(2), prompt: "אבג דהו")
    session.insertBatch("א", at: start)
    let rendering = try render(session, marked: "בגד")
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    for style in [TypingCaretStyle.bar, .block, .outline, .underline] {
      let coordinator = PromptCaretMotionCoordinator()
      var config = PromptCaretNativeView.Configuration(text: rendering.text, mainOffset: nil, paceOffset: nil,
        mainStyle: style, paceStyle: .outline, font: font, lineSpacing: 0, rightToLeft: true,
        accent: .yellow, motion: .off, reducesMotion: true, frameRate: 30,
        attemptID: session.automaticInputAttemptID, coordinator: coordinator,
        mainGlyphID: session.promptCaretGlyphIndex, automaticallyPresents: false)
      config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
        fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: 4) }
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 80))
      defer { view.stop() }
      view.configure(rendering: rendering, anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
        compositionField: session.promptCompositionField, mode: .letter, margin: 0.25,
        smoothScroll: false, carets: config, at: 0)
      view.present(at: 0)
      XCTAssertEqual(try XCTUnwrap(coordinator.main.position).maxX, 300, accuracy: 0.001)
      XCTAssertEqual(coordinator.wordsTapeMargin,
        ("א" as NSString).size(withAttributes: [.font: font]).width, accuracy: 0.001)
      let textView = try XCTUnwrap(view.subviews.first { !($0 is PromptCaretNativeView) })
      XCTAssertLessThan(textView.frame.width, 1000)
      XCTAssertLessThan(abs(textView.frame.minX), 1000)
      XCTAssertGreaterThan(try XCTUnwrap(coordinator.pace.position).minX, -1000)
      XCTAssertLessThan(try XCTUnwrap(coordinator.pace.position).maxX, 300)
      if style == .bar { try capture(view, name: "tape-projection-rtl-letter") }
    }
  }

  private func capture(_ view: TapePromptNativeView, name: String) throws {
    let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    window.contentView = view; view.layer?.backgroundColor = NSColor.white.cgColor
    defer { window.contentView = nil; window.close() }
    view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    XCTAssertGreaterThan(png.count, 500); XCTAssertFalse(window.isVisible)
    if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
      try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }
  }

  func testNaturalFlowWidthDoesNotWrapJoinedFieldAtTheMeasurementProposal() throws {
    let session = TypingSession(configuration: .words(2), prompt: "abcdefgh next")
    let map = try XCTUnwrap(render(session, marked: "").compositionTextMap)
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    for rtl in [false, true] {
      let bounded = PromptFieldTextLayout(map: map, width: 50, font: font, rightToLeft: rtl, joinsLetters: true)
      let natural = PromptFieldTextLayout(map: map, width: 50, font: font,
        rightToLeft: rtl, joinsLetters: true, unbounded: true)
      XCTAssertGreaterThan(bounded.size.height, natural.size.height)
      XCTAssertGreaterThan(natural.size.width, 50)
      XCTAssertTrue(natural.cellFrames.values.allSatisfy { abs($0.minY) < 0.001 })
      XCTAssertGreaterThanOrEqual(natural.cellFrames.values.map(\.minX).min() ?? 0, -0.001)
      XCTAssertLessThanOrEqual(natural.cellFrames.values.map(\.maxX).max() ?? 0, natural.size.width + 0.001)
    }
  }

  func testRTLWordProjectionAdvancesByCompletedFieldAndKeepsCandidateCaretWithinActiveWord() throws {
    var session = TypingSession(configuration: .words(2), prompt: "אבג דהו")
    session.insertBatch("אבג ד", at: start)
    let rendering = try render(session, marked: "הוז")
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    let before = "אבג ".reduce(CGFloat.zero) { $0 + (String($1) as NSString).size(withAttributes: [.font: font]).width }
    for mode in [PracticeTapeMode.letter, .word] {
      let coordinator = PromptCaretMotionCoordinator()
      let config = PromptCaretNativeView.Configuration(text: rendering.text, mainOffset: nil, paceOffset: nil,
        mainStyle: .bar, paceStyle: .off, font: font, lineSpacing: 0, rightToLeft: true,
        accent: .yellow, motion: .off, reducesMotion: true, frameRate: 30,
        attemptID: session.automaticInputAttemptID, coordinator: coordinator,
        mainGlyphID: session.promptCaretGlyphIndex, automaticallyPresents: false)
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 80))
      defer { view.stop() }
      view.configure(rendering: rendering, anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
        compositionField: session.promptCompositionField, mode: mode, margin: 0.25,
        smoothScroll: false, carets: config, at: 0)
      view.present(at: 0)
      let expected = before + (mode == .letter ? ("ד" as NSString).size(withAttributes: [.font: font]).width : 0)
      XCTAssertEqual(coordinator.wordsTapeMargin, expected, accuracy: 0.001)
      let main = try XCTUnwrap(coordinator.main.position)
      if mode == .letter { XCTAssertEqual(main.maxX, 300, accuracy: 0.001) }
      else {
        XCTAssertLessThan(main.maxX, 300)
        XCTAssertGreaterThan(main.minX, 200)
        try capture(view, name: "tape-projection-rtl-word")
      }
      XCTAssertEqual(session.typed, "אבג ד")
    }
  }

  func testFreshSnapshotUpdatesAcceptedAdvanceBeforeRepresentableConfiguration() throws {
    var session = TypingSession(configuration: .words(2), prompt: "abcd next")
    let attempt = session.automaticInputAttemptID
    func snapshot(_ marked: String) throws -> TapePromptProjectionSnapshot {
      .init(input: .init(attemptID: attempt, typed: session.typed, composition: marked,
        glyphID: session.promptCaretGlyphIndex), field: try XCTUnwrap(session.promptCompositionField),
        rendering: try render(session, marked: marked))
    }
    var current = try snapshot("")
    var reads = 0
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    let coordinator = PromptCaretMotionCoordinator()
    let config = PromptCaretNativeView.Configuration(text: current.rendering.text, mainOffset: nil, paceOffset: nil,
      mainStyle: .bar, paceStyle: .off, font: font, lineSpacing: 0, rightToLeft: false,
      accent: .yellow, motion: .off, reducesMotion: true, frameRate: 30,
      attemptID: attempt, coordinator: coordinator, mainGlyphID: 0, automaticallyPresents: false)
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 80))
    defer { view.stop() }
    view.configure(rendering: current.rendering, anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
      compositionField: current.field, latestProjection: { reads += 1; return current },
      mode: .letter, margin: 0.25, smoothScroll: false, carets: config, at: 0)
    session.insertBatch("a", at: start); current = try snapshot("XYZ")
    let before = reads
    view.present(at: 1)
    XCTAssertEqual(reads - before, 1, "One immutable snapshot per owner presentation")
    XCTAssertEqual(-coordinator.wordsTapeMargin, ("a" as NSString).size(withAttributes: [.font: font]).width, accuracy: 0.001)
    XCTAssertEqual(view.accessibilityLabel(), String(current.rendering.text.characters))
    XCTAssertEqual(try XCTUnwrap(coordinator.main.position).minX, 100, accuracy: 0.001)
    XCTAssertEqual(session.typed, "a")
  }

  private func freshView(_ initial: TapePromptProjectionSnapshot,
    provider: @escaping () -> TapePromptProjectionSnapshot?)
    -> (TapePromptNativeView, PromptCaretMotionCoordinator) {
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    let coordinator = PromptCaretMotionCoordinator()
    var config = PromptCaretNativeView.Configuration(text: initial.rendering.text, mainOffset: nil, paceOffset: nil,
      mainStyle: .bar, paceStyle: .outline, font: font, lineSpacing: 0, rightToLeft: false,
      accent: .yellow, motion: .off, reducesMotion: true, frameRate: 30,
      attemptID: initial.input.attemptID, coordinator: coordinator,
      mainGlyphID: initial.input.glyphID, automaticallyPresents: false)
    config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: 5) }
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 80))
    view.configure(rendering: initial.rendering, anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
      compositionField: initial.field, latestProjection: provider, mode: .word,
      margin: 0.25, smoothScroll: false, carets: config, at: 0)
    return (view, coordinator)
  }

  private func snapshot(_ session: TypingSession, marked: String, attempt: UUID? = nil) throws -> TapePromptProjectionSnapshot {
    .init(input: .init(attemptID: attempt ?? session.automaticInputAttemptID, typed: session.typed,
      composition: marked, glyphID: session.promptCaretGlyphIndex), field: try XCTUnwrap(session.promptCompositionField),
      rendering: try render(session, marked: marked))
  }

  func testIndependentPaceRequestRefreshesCandidateGeometryBeforePresentation() throws {
    var session = TypingSession(configuration: .words(2), prompt: "abcd next")
    session.insertBatch("a", at: start)
    var current = try snapshot(session, marked: "X")
    var reads = 0
    let (view, coordinator) = freshView(current, provider: { reads += 1; return current })
    defer { view.stop() }
    let caret = try XCTUnwrap(view.subviews.compactMap { $0 as? PromptCaretNativeView }.first)
    _ = caret.requestPacePosition(at: 0)
    let oldPace = try XCTUnwrap(coordinator.pace.position)
    let oldMain = try XCTUnwrap(coordinator.main.position)
    current = try snapshot(session, marked: "XYZ123")
    let before = reads
    _ = caret.requestPacePosition(at: 1, fromDeadline: true)
    XCTAssertEqual(reads - before, 1)
    XCTAssertGreaterThan(try XCTUnwrap(coordinator.pace.position).minX, oldPace.minX + 1)
    XCTAssertEqual(coordinator.main.position, oldMain, "A pace deadline must not paint or position main")
    XCTAssertEqual(view.accessibilityLabel(), String(current.rendering.text.characters))
    view.present(at: 1)
    XCTAssertGreaterThan(try XCTUnwrap(coordinator.main.position).minX, oldMain.minX + 1)
    XCTAssertEqual(coordinator.wordsTapeMargin, 0)
  }

  func testUnavailableOldAttemptAndCrossFieldSnapshotsCannotReplaceCurrentLayout() throws {
    var session = TypingSession(configuration: .words(2), prompt: "abcd next")
    session.insertBatch("a", at: start)
    let initial = try snapshot(session, marked: "X")
    var current: TapePromptProjectionSnapshot? = initial
    var reads = 0
    let (view, coordinator) = freshView(initial, provider: { reads += 1; return current })
    defer { view.stop() }
    let label = view.accessibilityLabel(), main = coordinator.main.position
    current = nil; view.present(at: 1)
    XCTAssertEqual(view.accessibilityLabel(), label); XCTAssertEqual(coordinator.main.position, main)
    current = try snapshot(session, marked: "ZZZ", attempt: UUID()); view.present(at: 2)
    XCTAssertEqual(view.accessibilityLabel(), label); XCTAssertEqual(coordinator.main.position, main)
    session.insertBatch("bcd ", at: start)
    current = try snapshot(session, marked: "ZZZ"); view.present(at: 3)
    XCTAssertNotEqual(current?.field.index, initial.field.index)
    XCTAssertEqual(view.accessibilityLabel(), label, "Cross-field retirement needs a complete transaction")
    view.stop(); let before = reads; view.present(at: 4)
    XCTAssertEqual(reads, before, "Detached owners must not read a retained provider")
  }

  func testReentrantSnapshotReadCannotStartAnotherProviderRead() throws {
    let session = TypingSession(configuration: .words(2), prompt: "abcd next")
    let current = try snapshot(session, marked: "XY")
    var owner: TapePromptNativeView?, reenter = false, reads = 0
    let (view, _) = freshView(current, provider: {
      reads += 1
      if reenter { reenter = false; owner?.present(at: 1) }
      return current
    })
    owner = view; defer { view.stop(); owner = nil }
    reenter = true; let before = reads; view.present(at: 1)
    XCTAssertEqual(reads - before, 1, "A bounded reentry must reuse the last coherent snapshot")
  }

  func testStoppingDuringProviderReadDiscardsTheReturnedSnapshot() throws {
    let session = TypingSession(configuration: .words(2), prompt: "abcd next")
    let initial = try snapshot(session, marked: "X"), next = try snapshot(session, marked: "XYZ123")
    var owner: TapePromptNativeView?, stopOnRead = false
    let (view, coordinator) = freshView(initial, provider: {
      if stopOnRead { owner?.stop(); return next }
      return initial
    })
    owner = view; defer { view.stop(); owner = nil }
    let old = view.accessibilityLabel()
    stopOnRead = true; view.present(at: 1)
    XCTAssertEqual(view.accessibilityLabel(), old, "A cancelled callback must not install new text")
    XCTAssertFalse(coordinator.isAnimatingTape)
  }

  func testPaceDeadlineStopsWhenItsFreshProviderDetachesTheOwner() throws {
    let session = TypingSession(configuration: .words(2), prompt: "abcd next")
    let initial = try snapshot(session, marked: "X")
    var owner: TapePromptNativeView?, stopOnRead = false
    let (view, _) = freshView(initial, provider: {
      if stopOnRead { owner?.stop() }
      return initial
    })
    owner = view; defer { view.stop(); owner = nil }
    let caret = try XCTUnwrap(view.subviews.compactMap { $0 as? PromptCaretNativeView }.first)
    stopOnRead = true
    XCTAssertNil(caret.requestPacePosition(at: 1, fromDeadline: true), "An in-flight cancelled deadline must not continue with captured configuration")
  }
}
