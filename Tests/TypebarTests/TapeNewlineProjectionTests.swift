import AppKit
import XCTest
@testable import Typebar

@MainActor final class TapeNewlineProjectionTests: XCTestCase {
  private final class Canvas: NSView {
    let native: TapeNewlineTextLayout
    init(_ native: TapeNewlineTextLayout) { self.native = native; super.init(frame: .init(x: 0, y: 0, width: 400, height: 120)) }
    required init?(coder: NSCoder) { fatalError("test-only canvas") }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { NSColor.white.setFill(); dirtyRect.fill(); native.draw(in: dirtyRect) }
  }
  func testVirtualSlotsUseFieldIdentityInsidePersistentNewlineFlow() throws {
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    var session = TypingSession(configuration: .words(3), prompt: "a\nbc tail")
    session.insertBatch("a\nb", at: Date(timeIntervalSinceReferenceDate: 917_100_000))
    let presentation = try XCTUnwrap(PromptCompositionPresentation(session: session,
      composition: "XYZ😀", style: .replace))
    let rendering = presentation.render { _, glyph, cell in AttributedString(cell?.text ?? String(glyph.character)) }
    let map = try XCTUnwrap(rendering.compositionTextMap)
    let descriptors = TapePromptProjection.words(session: session, rendering: rendering)
    let field = try XCTUnwrap(session.promptCompositionField)
    let cells = map.fieldRuns.filter { $0.fieldID == field.index }.flatMap(\.cells).filter { !$0.isGap }
    XCTAssertTrue(cells.contains { $0.id < 0 })
    for rtl in [false, true] {
      let native = TapeNewlineTextLayout()
      native.configure(text: rendering.text, words: descriptors, font: font,
        rightToLeft: rtl, resets: true, compositionMap: map)
      let frame = try XCTUnwrap(native.projectedFieldRect(field.index))
      for cell in cells {
        let rect = try XCTUnwrap(native.projectedCellRect(cell.id))
        XCTAssertEqual(rect.minY, frame.minY, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(rect.minX, frame.minX - 0.001)
        XCTAssertLessThanOrEqual(rect.maxX, frame.maxX + 0.001)
      }
      XCTAssertEqual(frame.minY, native.metrics.rowHeight, accuracy: 0.001)
      let wordPass = try XCTUnwrap(native.requestProjectedScroll(fieldID: field.index,
        acceptedUTF16Count: 0, mode: .word, hidesExtras: false, viewportWidth: 400,
        duration: 0, time: 0, overflowing: { _, _ in false }))
      let letterPass = try XCTUnwrap(native.requestProjectedScroll(fieldID: field.index,
        acceptedUTF16Count: 1, mode: .letter, hidesExtras: false, viewportWidth: 400,
        duration: 0, time: 0, overflowing: { _, _ in false }))
      XCTAssertEqual(letterPass.advance - wordPass.advance,
        try XCTUnwrap(native.projectedCellRect(cells[0].id)).width, accuracy: 0.001)
      XCTAssertNil(native.projectedCellRect(Int.min))
      XCTAssertNil(native.projectedFieldRect(Int.min))
      let activeIDs = Set(cells.map(\.id))
      for (canonical, aliases) in map.canonicalAliases where aliases.allSatisfy({ activeIDs.contains($0) }) && !aliases.isEmpty {
        XCTAssertEqual(native.projectedCanonicalRect(canonical, after: false), native.projectedCellRect(aliases[0]))
        XCTAssertEqual(native.projectedCanonicalRect(canonical, after: true), native.projectedCellRect(aliases[aliases.count - 1]))
      }
      XCTAssertEqual(session.typed, "a\nb")
      let canvas = Canvas(native)
      let window = NSWindow(contentRect: canvas.frame, styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentView = canvas
      defer { window.contentView = nil; window.close() }
      let bitmap = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
      canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
      let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      XCTAssertGreaterThan(png.count, 500)
      if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("tape-multiline-projection-\(rtl ? "rtl" : "ltr").png"))
      }
      XCTAssertFalse(window.isVisible)
    }
  }

  func testProjectionRebuildDoesNotResurrectHorizontallyRemovedReturnWord() throws {
    var session = TypingSession(configuration: .words(3), prompt: "a\nbc tail")
    session.insertBatch("a\nb", at: Date(timeIntervalSinceReferenceDate: 917_100_000))
    let native = TapeNewlineTextLayout()
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    let active = try XCTUnwrap(session.promptCompositionField).index
    for (iteration, marked) in ["XYZ", "候选😀", ""].enumerated() {
      let presentation = try XCTUnwrap(PromptCompositionPresentation(session: session, composition: marked, style: .replace))
      let rendering = presentation.render { _, glyph, cell in AttributedString(cell?.text ?? String(glyph.character)) }
      native.configure(text: rendering.text, words: TapePromptProjection.words(session: session, rendering: rendering),
        font: font, rightToLeft: false, resets: iteration == 0, compositionMap: rendering.compositionTextMap)
      if iteration == 0 {
        let pass = try XCTUnwrap(native.requestProjectedScroll(fieldID: active, acceptedUTF16Count: 1,
          mode: .letter, hidesExtras: false, viewportWidth: 400, duration: 0, time: 0,
          overflowing: { id, _ in id == 0 }))
        XCTAssertEqual(pass.removedWords, [0])
      }
      XCTAssertNil(native.projectedFieldRect(0))
      XCTAssertEqual(native.removedWordIndices, [0])
      let frame = try XCTUnwrap(native.projectedFieldRect(active))
      XCTAssertEqual(frame.minY, native.metrics.rowHeight, accuracy: 0.001,
        "The removed word's Return topology survives candidate rebuilds")
    }
  }

  func testActualOwnerUsesMultilineFieldGeometryWithoutLegacyOffsets() throws {
    var session = TypingSession(configuration: .words(3), prompt: "a\nbc tail")
    session.insertBatch("a\nb", at: Date(timeIntervalSinceReferenceDate: 917_100_000))
    let presentation = try XCTUnwrap(PromptCompositionPresentation(session: session, composition: "XYZ😀", style: .replace))
    let original = presentation.render { _, glyph, cell in AttributedString(cell?.text ?? String(glyph.character)) }
    let rendering = PromptRendering(text: original.text, glyphCharacterOffsets: [:], compositionTextMap: original.compositionTextMap)
    let descriptors = TapePromptProjection.words(session: session, rendering: original)
    let field = try XCTUnwrap(session.promptCompositionField)
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    for rtl in [false, true] { for mode in [PracticeTapeMode.letter, .word] {
      let reference = TapeNewlineTextLayout()
      reference.configure(text: rendering.text, words: descriptors, font: font, rightToLeft: rtl,
        resets: true, compositionMap: rendering.compositionTextMap)
      let pass = try XCTUnwrap(reference.requestProjectedScroll(fieldID: field.index,
        acceptedUTF16Count: field.inputUTF16.count, mode: mode, hidesExtras: false,
        viewportWidth: 400, duration: 0, time: 0, overflowing: { _, _ in false }))
      let coordinator = PromptCaretMotionCoordinator()
      let owner = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 120))
      let window = NSWindow(contentRect: owner.frame, styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
      window.contentView = owner; owner.layer?.backgroundColor = NSColor.white.cgColor
      defer { owner.stop(); window.contentView = nil; window.close() }
      let paceID = try XCTUnwrap(session.promptWordPresentations.last).range.lowerBound
      var config = PromptCaretNativeView.Configuration(text: rendering.text, mainOffset: nil, paceOffset: nil,
        mainStyle: .bar, paceStyle: .outline, font: font, lineSpacing: 0, rightToLeft: rtl,
        accent: .yellow, motion: .off, reducesMotion: true, frameRate: 30,
        attemptID: session.automaticInputAttemptID, coordinator: coordinator,
        mainGlyphID: session.promptCaretGlyphIndex, automaticallyPresents: false)
      config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
        fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: paceID) }
      owner.configure(rendering: rendering, anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
        compositionField: field, mode: mode, margin: 0.25, smoothScroll: false,
        newlineWords: descriptors, carets: config, at: 0)
      owner.present(at: 0)
      XCTAssertEqual(coordinator.wordsTapeMargin, rtl ? pass.advance : -pass.advance, accuracy: 0.001)
      let main = try XCTUnwrap(coordinator.main.position)
      XCTAssertEqual(main.minY, try XCTUnwrap(reference.projectedFieldRect(field.index)).minY, accuracy: 0.001)
      let projectedMain = try XCTUnwrap(reference.projectedMainRect(style: .bar))
      let word = try XCTUnwrap(reference.projectedFieldRect(field.index))
      let expectedMainX: CGFloat = mode == .word
        ? projectedMain.minX + (rtl ? 300 - word.maxX : 100 - word.minX)
        : (rtl ? 300 - projectedMain.width : 100)
      XCTAssertEqual(main.minX, expectedMainX, accuracy: 0.001)
      let pace = try XCTUnwrap(coordinator.pace.position)
      let target = try XCTUnwrap(reference.projectedCanonicalRect(paceID, after: false))
      let base: CGFloat = rtl ? 300 : 100
      XCTAssertEqual(pace.minX, target.minX + base - reference.leadingEdge + coordinator.wordsTapeMargin, accuracy: 0.001)
      XCTAssertEqual(pace.minY, target.minY, accuracy: 0.001)
      let bitmap = try XCTUnwrap(owner.bitmapImageRepForCachingDisplay(in: owner.bounds))
      owner.cacheDisplay(in: owner.bounds, to: bitmap)
      let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      XCTAssertGreaterThan(png.count, 500)
      if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(
          "tape-multiline-owner-\(rtl ? "rtl" : "ltr")-\(mode == .letter ? "letter" : "word").png"))
      }
      XCTAssertFalse(window.isVisible)
    } }
  }

  func testProjectedVerticalRetirementKeepsMapAndAcknowledgesPrefixOnce() throws {
    for rtl in [false, true] { for smooth in [false, true] { for cancels in [false, true] { for sharedID in [false, true] {
      var session = TypingSession(configuration: .words(4), prompt: "a\nb\nc\ntail")
      let coordinator = PromptCaretMotionCoordinator()
      let owner = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 160))
      defer { owner.stop() }
      let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
      var retired: [PromptWordRetirement] = []
      let delivered = XCTestExpectation(description: "Retirement rtl=\(rtl), smooth=\(smooth), shared=\(sharedID)")
      func configure(at time: Double) throws {
        let presentation = try XCTUnwrap(PromptCompositionPresentation(session: session, composition: "XYZ😀", style: .replace))
        let original = presentation.render { _, glyph, cell in AttributedString(cell?.text ?? String(glyph.character)) }
        let rendering = PromptRendering(text: original.text, glyphCharacterOffsets: [:], compositionTextMap: original.compositionTextMap)
        let descriptors = TapePromptProjection.words(session: session, rendering: original)
        let field = try XCTUnwrap(session.promptCompositionField)
        var config = PromptCaretNativeView.Configuration(text: rendering.text, mainOffset: nil, paceOffset: nil,
          mainStyle: .bar, paceStyle: .outline, font: font, lineSpacing: 0, rightToLeft: rtl,
          accent: .yellow, motion: .off, reducesMotion: false, frameRate: 30,
          attemptID: session.automaticInputAttemptID, coordinator: coordinator,
          mainGlyphID: session.promptCaretGlyphIndex, automaticallyPresents: false)
        let identity = PromptCaretInputIdentity(attemptID: session.automaticInputAttemptID,
          typed: session.typed, composition: "XYZ😀", glyphID: session.promptCaretGlyphIndex)
        config.latestInput = { identity }
        config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
          fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: 6) }
        owner.configure(rendering: rendering, anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
          compositionField: field, mode: .letter, margin: 0.25, smoothScroll: smooth,
          retirement: .init(attemptID: session.automaticInputAttemptID,
            activeWordID: sharedID ? 0 : session.promptWordPresentations[field.index].range.lowerBound,
            characterOffsets: [:], smoothScroll: smooth, reducesMotion: false,
            words: session.promptWordPresentations.enumerated().map { .init(index: $0.offset, glyphID: sharedID ? 0 : $0.element.range.lowerBound) },
            firstRetainedWordIndex: session.firstRetainedPromptWordIndex, onRetire: { retired.append($0); delivered.fulfill() }),
          newlineWords: descriptors, carets: config, at: time)
      }
      try configure(at: 0)
      session.insertBatch("a\n", at: Date(timeIntervalSinceReferenceDate: 917_100_000))
      try configure(at: 0.1); owner.present(at: 0.213)
      session.insertBatch("b\n", at: Date(timeIntervalSinceReferenceDate: 917_100_001))
      try configure(at: 1)
      if cancels {
        owner.stop(); owner.present(at: 2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.002))
        XCTAssertTrue(retired.isEmpty, "Stop cancels pending completion and already queued notification")
        continue
      }
      owner.present(at: 1.05)
      if smooth { XCTAssertLessThan(coordinator.wordsMargin, 0) }
      owner.present(at: 1.113)
      wait(for: [delivered], timeout: 1)
      XCTAssertEqual(retired.map(\.firstRetainedWordIndex), [1], "rtl=\(rtl), smooth=\(smooth), shared=\(sharedID)")
      guard let removal = retired.first else { continue }
      let main = try XCTUnwrap(coordinator.main.position), pace = try XCTUnwrap(coordinator.pace.position)
      let correction = coordinator.pace.cumulativeTapeCorrection
      session.retirePromptWords(removal)
      try configure(at: 1.113); owner.present(at: 1.113)
      XCTAssertEqual(coordinator.main.position, main)
      XCTAssertEqual(coordinator.pace.position, pace)
      XCTAssertEqual(coordinator.pace.cumulativeTapeCorrection, correction)
      try configure(at: 1.113); owner.present(at: 1.113)
      RunLoop.main.run(until: Date().addingTimeInterval(0.002))
      XCTAssertEqual(retired.count, 1)
      XCTAssertEqual(session.typed, "a\nb\n")
    } } } }
  }

  func testSharedCanonicalIDsDoNotMergeDistinctReturnFillerChannels() throws {
    let session = TypingSession(configuration: .words(4), prompt: "a\nbbbb\ncc\ntail")
    let presentation = try XCTUnwrap(PromptCompositionPresentation(session: session, composition: "X", style: .replace))
    let rendering = presentation.render { _, glyph, cell in AttributedString(cell?.text ?? String(glyph.character)) }
    let original = TapePromptProjection.words(session: session, rendering: rendering)
    let shared = original.map { word in
      TapePromptWord(index: word.index, glyphID: 0, characters: word.characters,
        newlineCharacterOffset: word.newlineCharacterOffset, incorrectNewline: word.incorrectNewline,
        hasStructuralNewline: word.hasStructuralNewline, isRemoved: word.isRemoved,
        controlCharacterOffsets: word.controlCharacterOffsets)
    }
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    for rtl in [false, true] {
      let reference = TapeNewlineTextLayout(), aliased = TapeNewlineTextLayout()
      for (native, descriptors) in [(reference, original), (aliased, shared)] {
        native.configure(text: rendering.text, words: descriptors, font: font, rightToLeft: rtl,
          resets: true, compositionMap: rendering.compositionTextMap)
        _ = try XCTUnwrap(native.requestProjectedScroll(fieldID: 1, acceptedUTF16Count: 0,
          mode: .word, hidesExtras: false, viewportWidth: 400, duration: 0.125, time: 0,
          overflowing: { _, _ in false }))
      }
      for time in [0.0, 0.06, 0.125] {
        reference.sample(at: time); aliased.sample(at: time)
        for id in 0..<4 {
          XCTAssertEqual(aliased.projectedFieldRect(id), reference.projectedFieldRect(id), "field=\(id), time=\(time), rtl=\(rtl)")
        }
      }
    }
  }
}
