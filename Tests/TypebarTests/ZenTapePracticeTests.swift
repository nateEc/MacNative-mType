import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class ZenTapePracticeTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 913_200_000)

  @Observable final class Model {
    var session = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(freedomMode: true)), prompt: "")
    var mode = PracticeTapeMode.letter
    var fontSize: Double = 28
    var paceID: Int? = nil
    var smooth = false
    var reduced = true
    let motion = PromptCaretMotionCoordinator()
    var retirements: [PromptWordRetirement] = []
    var removals: [PromptTapeWordRemoval] = []
    var onRemoval: ((PromptTapeWordRemoval) -> Void)? = nil
    var rendering: PromptRendering {
      let glyphs = session.promptGlyphs, words = session.promptWordPresentations
      return .make(glyphs: glyphs, indices: PromptGlyphLayout.indices(glyphs: glyphs, words: words,
        hideExtraLetters: false, firstRetainedWordIndex: session.firstRetainedPromptWordIndex),
        emptyWordPlaceholderGlyphID: session.zenEmptyWordPlaceholderGlyphIndex,
        words: words, removedTapeWordIndices: session.removedTapePromptWordIndices) { index, glyph in
        let plan = PromptControlCharacterPresentation.plan(for: glyph, style: .off,
          isZen: session.configuration.mode == .zen,
          isEmptyWordPlaceholder: index == session.zenEmptyWordPlaceholderGlyphIndex)
        var value = AttributedString(plan.text); value.foregroundColor = Color.black.opacity(plan.opacity)
        return value
      }
    }
  }

  private struct Root: View {
    let model: Model
    var body: some View {
      let session = model.session, rendering = model.rendering
      let attempt = session.automaticInputAttemptID, glyph = session.promptCaretGlyphIndex, typed = session.typed
      let active = session.promptWordPresentations.first { $0.phase == .active }?.range.lowerBound
      let pace = model.paceID
      var config = PromptCaretNativeView.Configuration(text: rendering.text, mainOffset: nil, paceOffset: nil,
        mainStyle: .outline, paceStyle: pace == nil ? .off : .outline,
        font: .monospacedSystemFont(ofSize: model.fontSize, weight: .medium), lineSpacing: 0,
        rightToLeft: session.configuration.usesRightToLeftPrompt, accent: .blue,
        motion: .off, reducesMotion: model.reduced, frameRate: 60,
        attemptID: attempt, coordinator: model.motion, mainGlyphID: glyph)
      config.latestInput = { .init(attemptID: attempt, typed: typed, composition: "", glyphID: glyph) }
      config.mainPresentation = { .init(isVisible: true, isBlinking: false) }
      config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
        fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: pace) }
      let context = PromptLineScrollContext(attemptID: attempt, activeWordID: active,
        characterOffsets: rendering.glyphCharacterOffsets, smoothScroll: model.smooth, reducesMotion: model.reduced,
        words: session.promptWordPresentations.enumerated().map { .init(index: $0.offset, glyphID: $0.element.range.lowerBound) },
        firstRetainedWordIndex: session.firstRetainedPromptWordIndex,
        onRetire: { model.retirements.append($0); model.session.retirePromptWords($0) },
        followsWordReflow: true, caretMotion: model.motion)
      return TapePracticePrompt(session: session, rendering: rendering,
        mode: model.mode, margin: 0.25, fontSize: model.fontSize,
        animatesScroll: model.smooth, carets: config, retirement: context,
        onTapeWordsRemoved: { model.removals.append($0); model.session.removeTapePromptWords($0); model.onRemoval?($0) })
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
    (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
  }
  private func mount(_ model: Model, width: CGFloat = 400) -> (NSWindow, NSHostingView<Root>) {
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: 200),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    let host = NSHostingView(rootView: Root(model: model)); window.contentView = host
    return (window, host)
  }
  private func close(_ window: NSWindow, _ host: NSView) {
    descendants(host, TapePromptNativeView.self).forEach { $0.stop() }
    window.contentView = nil; window.close()
  }
  private func expectedHeight(_ model: Model) -> CGFloat {
    guard model.session.configuration.mode == .zen else { return CGFloat(model.fontSize * 1.7) }
    let rendering = model.rendering, layout = TapeNewlineTextLayout()
    layout.configure(text: rendering.text, words: TapePromptProjection.words(session: model.session, rendering: rendering),
      font: .monospacedSystemFont(ofSize: model.fontSize, weight: .medium),
      rightToLeft: model.session.configuration.usesRightToLeftPrompt, resets: true)
    return 2 * layout.metrics.rowHeight
  }

  @discardableResult private func capture(_ view: NSView, name: String) throws -> Data {
    view.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    var ink = 0
    for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
      if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
        color.alphaComponent > 0.2, min(color.redComponent, color.greenComponent, color.blueComponent) < 0.5 { ink += 1 }
    } }
    XCTAssertGreaterThan(ink, 10, "Native capture must contain text or visible markers")
    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
      try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("zen-tape-\(name).png"))
    }
    return data
  }
  @discardableResult private func settle(_ host: NSView, model: Model,
    firstRetainedIndex: Int? = nil) throws -> TapePromptNativeView {
    let deadline = Date(timeIntervalSinceNow: 1)
    repeat {
      host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
      host.layoutSubtreeIfNeeded()
      if let view = descendants(host, TapePromptNativeView.self).first,
        view.accessibilityLabel() == String(model.rendering.text.characters),
        abs(view.bounds.height - expectedHeight(model)) < 1,
        firstRetainedIndex.map({ model.session.firstRetainedPromptWordIndex == $0 }) ?? true {
        view.present(at: ProcessInfo.processInfo.systemUptime); return view
      }
    } while Date() < deadline
    let view = try XCTUnwrap(descendants(host, TapePromptNativeView.self).first)
    XCTFail("Zen must reserve two measured rows: expected=\(expectedHeight(model)), actual=\(view.bounds.height), input=\(String(reflecting: model.session.typed))")
    return view
  }

  func testEmptyZenAndTabUseStableTwoRowNativeOwner() throws {
    for mode in [PracticeTapeMode.word, .letter] {
      let model = Model(); model.mode = mode
      let (window, host) = mount(model); defer { close(window, host) }
      let original = try settle(host, model: model)
      XCTAssertGreaterThan(try XCTUnwrap(model.motion.main.visibleRect).width, 0)
      model.session.insertBatch("a\t", at: start); model.paceID = 1
      XCTAssertTrue(try settle(host, model: model) === original)
      let tab = try XCTUnwrap(model.motion.pace.visibleRect)
      XCTAssertEqual(tab.width, ("→" as NSString).size(withAttributes: [.font:
        NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)]).width, accuracy: 0.01)
      model.fontSize = 32
      XCTAssertTrue(try settle(host, model: model) === original)
      XCTAssertEqual(model.session.typed, "a\t"); XCTAssertEqual(model.session.prompt, "")
      try capture(original, name: "tab-\(mode.rawValue)")
      XCTAssertFalse(window.isVisible)
    }
  }

  func testConsecutiveReturnsRetireRowsWithoutDroppingInputOrPlaceholder() throws {
    for mode in [PracticeTapeMode.word, .letter] {
      let model = Model(); model.mode = mode
      let (window, host) = mount(model); defer { close(window, host) }
      let original = try settle(host, model: model)
      for (index, text) in ["a\n", "b\n", "c\n"].enumerated() {
        model.session.insertBatch(text, at: start.addingTimeInterval(Double(index)))
        XCTAssertTrue(try settle(host, model: model, firstRetainedIndex: max(0, index)) === original)
        let main = try XCTUnwrap(model.motion.main.visibleRect)
        XCTAssertGreaterThan(main.width, 0); XCTAssertGreaterThanOrEqual(main.minY, -1)
        XCTAssertLessThanOrEqual(main.maxY, original.bounds.height + 1)
        XCTAssertNotNil(model.session.zenEmptyWordPlaceholderGlyphIndex)
      }
      XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 2)
      XCTAssertEqual(model.retirements.map(\.firstRetainedWordIndex), [1, 2])
      XCTAssertEqual(model.session.typed, "a\nb\nc\n")
      try capture(original, name: "retired-\(mode.rawValue)")
      model.session.deleteBackward(at: start.addingTimeInterval(4)); try settle(host, model: model)
      XCTAssertEqual(model.session.typed, "a\nb\nc")
      model.session = model.session.repeatedAttempt(); model.paceID = nil
      XCTAssertTrue(try settle(host, model: model) === original)
      XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
      XCTAssertEqual(model.session.typed, ""); XCTAssertTrue(model.session.removedTapePromptWordIndices.isEmpty)
      XCTAssertFalse(window.isVisible)
    }
  }

  func testOrdinarySessionConstructorRetainsTheExistingSingleLineHeight() throws {
    for mode in [PracticeTapeMode.word, .letter] {
      let model = Model(); model.mode = mode
      model.session = TypingSession(configuration: .words(3), prompt: "ab cd ef")
      let (window, host) = mount(model); defer { close(window, host) }
      let original = try settle(host, model: model)
      model.session.insertBatch("ab c", at: start)
      XCTAssertTrue(try settle(host, model: model) === original)
      XCTAssertEqual(original.bounds.height, CGFloat(model.fontSize * 1.7), accuracy: 0.5)
      XCTAssertEqual(model.session.typed, "ab c"); XCTAssertFalse(window.isVisible)
    }
  }

  func testRTLUnicodeControlsAndRetiredGlyphIDsKeepTheCurrentPlaceholderVisible() throws {
    let model = Model()
    var configuration = model.session.configuration; configuration.language = .hebrew
    model.session = TypingSession(configuration: configuration, prompt: "")
    let (window, host) = mount(model); defer { close(window, host) }
    let original = try settle(host, model: model)
    model.session.insertBatch("א👩🏽‍💻\t\n", at: start); model.paceID = 2
    try settle(host, model: model)
    XCTAssertGreaterThan(try XCTUnwrap(model.motion.pace.visibleRect).width, 0)
    XCTAssertGreaterThanOrEqual(try XCTUnwrap(model.motion.main.visibleRect).minX, 0)
    try capture(original, name: "rtl-emoji")
    model.session.insertBatch("בe\u{301}\n", at: start.addingTimeInterval(1))
    try settle(host, model: model, firstRetainedIndex: 1)
    let retiredPace = try XCTUnwrap(model.motion.pace.visibleRect)
    XCTAssertLessThanOrEqual(retiredPace.maxY, 0, "Source keeps the prior caret position when its word is gone")
    XCTAssertFalse(retiredPace.intersects(original.bounds), "The cached retired Tab marker must remain fully clipped")
    let withPace = try capture(original, name: "rtl-retired-pace")
    model.paceID = nil; try settle(host, model: model)
    XCTAssertEqual(try capture(original, name: "rtl-retired-no-pace"), withPace,
      "Retired marker must contribute no pixels, not just report an out-of-bounds box")
    XCTAssertLessThanOrEqual(try XCTUnwrap(model.motion.main.visibleRect).maxY, original.bounds.height + 1)
    XCTAssertEqual(model.session.typed, "א👩🏽‍💻\t\nבe\u{301}\n")
    XCTAssertEqual(model.session.prompt, ""); XCTAssertFalse(window.isVisible)
  }

  func testNarrowZenTapeAcknowledgesHorizontalHolesWithoutDeletingTheInput() throws {
    let model = Model(), delivered = expectation(description: "Zen horizontal removal")
    var received = false
    model.onRemoval = { event in
      if !received, !event.wordIndices.isEmpty { received = true; delivered.fulfill() }
    }
    let (window, host) = mount(model, width: 80); defer { close(window, host) }
    let original = try settle(host, model: model)
    var input = ""
    for (index, word) in ["alpha ", "bravo ", "charlie ", "delta ", "echo "].enumerated() {
      input += word; model.session.insertBatch(word, at: start.addingTimeInterval(Double(index)))
      try settle(host, model: model)
    }
    wait(for: [delivered], timeout: 1); model.onRemoval = nil
    try settle(host, model: model)
    XCTAssertFalse(model.session.removedTapePromptWordIndices.isEmpty)
    XCTAssertEqual(model.session.typed, input)
    let events = model.removals.count
    host.needsLayout = true; try settle(host, model: model)
    XCTAssertEqual(model.removals.count, events, "Acknowledgement/repaint is not a second removal")
    try capture(original, name: "overflow")
    XCTAssertFalse(window.isVisible)
  }

  func testSmoothTransitionAndRepeatCancelStaleRetirementWithoutLosingInput() throws {
    let model = Model(); model.smooth = true; model.reduced = false
    let (window, host) = mount(model); defer { close(window, host) }
    let original = try settle(host, model: model)
    model.session.insertBatch("a\n", at: start); try settle(host, model: model)
    model.session.insertBatch("b\n", at: start.addingTimeInterval(1))
    try settle(host, model: model, firstRetainedIndex: 1)
    XCTAssertEqual(model.session.typed, "a\nb\n")
    model.session.insertBatch("c\n", at: start.addingTimeInterval(2)); try settle(host, model: model)
    let attempt = model.session.automaticInputAttemptID, events = model.retirements.count
    model.session = model.session.repeatedAttempt()
    XCTAssertTrue(try settle(host, model: model, firstRetainedIndex: 0) === original)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)); try settle(host, model: model)
    XCTAssertNotEqual(model.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(model.retirements.count, events)
    XCTAssertEqual(model.session.typed, ""); XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
    XCTAssertFalse(window.isVisible)
  }

  func testTwoRowNativeViewportAgainstCompletePinnedWrapperHeight() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned clean reference")
    }
    struct Fixture: Decodable { let tapeMode, gate: String; let force, expanded: Bool; let rowHeight: Double; let height: String? }
    struct Evidence: Decodable { let pin: String; let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-zen-tape-viewport.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    guard process.terminationStatus == 0 else { return }
    let evidence = try JSONDecoder().decode(Evidence.self, from: data)
    XCTAssertEqual(evidence.pin, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(evidence.fixtures.count, 192)
    for fixture in evidence.fixtures where fixture.force && !fixture.expanded && fixture.gate == "test" && fixture.tapeMode != "off" {
      let model = Model(); model.mode = try XCTUnwrap(PracticeTapeMode(rawValue: fixture.tapeMode))
      model.fontSize = fixture.rowHeight > 40 ? 32 : 28
      let (window, host) = mount(model); defer { close(window, host) }
      let native = try settle(host, model: model)
      let height = try XCTUnwrap(Double(try XCTUnwrap(fixture.height).replacingOccurrences(of: "px", with: "")))
      XCTAssertEqual(native.bounds.height / (expectedHeight(model) / 2), height / fixture.rowHeight, accuracy: 0.01,
        "Compare the actual source row multiplier using native measured font metrics, not CSS pixel equivalence")
      XCTAssertFalse(window.isVisible)
    }
  }

  func testDeletingReturnRemovesItsStructureWithoutShrinkingTheViewport() throws {
    let model = Model()
    let (window, host) = mount(model); defer { close(window, host) }
    let original = try settle(host, model: model)
    model.session.insertBatch("a\n", at: start); try settle(host, model: model)
    XCTAssertGreaterThan(try XCTUnwrap(model.motion.main.visibleRect).minY, 0)
    model.session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertTrue(try settle(host, model: model) === original)
    XCTAssertEqual(try XCTUnwrap(model.motion.main.visibleRect).minY, 0, accuracy: 0.01)
    XCTAssertEqual(model.session.typed, "a"); XCTAssertFalse(window.isVisible)
  }

  func testProductionUsesTheSessionConstructorInsteadOfTheTargetNewlineSignal() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let start = try XCTUnwrap(app.range(of: "} else if usesTapePractice {"))
    let end = try XCTUnwrap(app.range(of: "} else {", range: start.upperBound..<app.endIndex))
    let branch = app[start.upperBound..<end.lowerBound]
    XCTAssertTrue(branch.contains("TapePracticePrompt(session: session"))
    XCTAssertFalse(branch.contains("session.hasPracticeNewlineContent ?"))
  }
}
