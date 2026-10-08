import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class ASLPromptLineScrollTests: XCTestCase {
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
  private let start = Date(timeIntervalSinceReferenceDate: 913_000_000)

  @Observable final class Model {
    var session = TypingSession(configuration: .words(5, rules: .init(freedomMode: true)), prompt: "a\nb\nc\nd\ne")
    var smooth = true
    var reduced = false
    var fontSize: CGFloat = 28
    var lineCount = 3
    var showsAll = false
    var markers = false
    let motion = PromptCaretMotionCoordinator()
    var retired: [PromptWordRetirement] = []
    var rendering: PromptRendering {
      PromptRendering.make(glyphs: session.promptGlyphs,
        indices: PromptGlyphLayout.indices(glyphs: session.promptGlyphs, words: session.promptWordPresentations,
          hideExtraLetters: false, firstRetainedWordIndex: session.firstRetainedPromptWordIndex)) { _, glyph in
        var value = AttributedString(String(glyph.character)); value.foregroundColor = .primary; return value
      }
    }
  }

  private struct Root: View {
    let model: Model
    var body: some View {
      let rendering = model.rendering, words = model.session.promptWordPresentations
      let font = NSFont.monospacedSystemFont(ofSize: model.fontSize, weight: .regular)
      let context = PromptLineScrollContext(attemptID: model.session.automaticInputAttemptID,
        activeWordID: words.first(where: { $0.phase == .active })?.range.lowerBound,
        characterOffsets: rendering.glyphCharacterOffsets, smoothScroll: model.smooth, reducesMotion: model.reduced,
        words: words.enumerated().map { .init(index: $0.offset, glyphID: $0.element.range.lowerBound) },
        firstRetainedWordIndex: model.session.firstRetainedPromptWordIndex,
        onRetire: { model.retired.append($0); model.session.retirePromptWords($0) }, caretMotion: model.motion)
      let carets: PromptCaretNativeView.Configuration? = model.markers ? .init(text: AttributedString(),
        mainOffset: nil, paceOffset: nil, mainStyle: .bar, paceStyle: .outline,
        font: font, lineSpacing: 12, rightToLeft: false, accent: .blue, motion: .off,
        reducesMotion: model.reduced, frameRate: 60, attemptID: model.session.automaticInputAttemptID,
        coordinator: model.motion,
        paceFrame: { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
          fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: model.session.promptCaretGlyphIndex) },
        mainGlyphID: model.session.promptCaretGlyphIndex) : nil
      let prompt = ASLPracticePrompt(glyphs: model.session.promptGlyphsInDisplayOrder,
        fontSize: model.fontSize, accent: .blue,
        glyphIDs: PromptGlyphLayout.indices(glyphs: model.session.promptGlyphs, words: words, hideExtraLetters: false),
        rendering: rendering, carets: carets, font: font, lineScroll: model.showsAll ? nil : context,
        caretGlyphID: model.session.promptCaretGlyphIndex, viewportLineCount: model.showsAll ? nil : model.lineCount,
        words: words)
      Group {
        if model.showsAll { prompt }
        else {
          PracticePromptViewport(text: rendering.text, font: font, lineSpacing: 12,
            isRightToLeft: false, lineCount: model.lineCount, measuresTextRows: false, measuresCustomRows: true) { prompt }
        }
      }.frame(width: 240).background(Color.white)
    }
  }

  private func mount(_ model: Model) -> (NSWindow, NSHostingView<Root>) {
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 240, height: 250),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    let host = NSHostingView(rootView: Root(model: model)); window.contentView = host
    host.frame = .init(x: 0, y: 0, width: 240, height: 250)
    pump(host)
    return (window, host)
  }

  private func pump(_ view: NSView, _ duration: TimeInterval = 0.04) {
    view.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(duration)); view.layoutSubtreeIfNeeded()
  }

  private func capture(_ view: NSView, _ name: String) throws {
    guard let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] else { return }
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
      to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
  }

  private func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
    (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
  }

  func testProductionASLReceivesWordScrollContextEvenWithoutVisibleCarets() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let start = try XCTUnwrap(app.range(of: "if practiceVisualEffect.usesASL {"))
    let end = try XCTUnwrap(app.range(of: "} else if practiceVisualEffect.usesChoo {", range: start.upperBound..<app.endIndex))
    XCTAssertTrue(app[start.upperBound..<end.lowerBound].contains("lineScroll:"),
      "ASL must receive the same attempt/word-retirement policy as ordinary prompts")
    XCTAssertTrue(app[start.upperBound..<end.lowerBound].contains("words: session.promptWordPresentations"),
      "Production word ownership must come from session metadata, not rendered replacements")
  }

  func testASLViewportMeasuresActualHandRowsRatherThanFixed184Points() throws {
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 240, height: 250),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.contentView = nil; window.close() }
    let prompt = ASLPracticePrompt(glyphs: "a\nb\nc\nd".map { .init(character: $0, state: .pending) },
      fontSize: 28, accent: .blue, viewportLineCount: 3)
    let host = NSHostingView(rootView: PracticePromptViewport(text: AttributedString("a\nb\nc\nd"),
      font: font, lineSpacing: 12, isRightToLeft: false, lineCount: 3,
      measuresTextRows: false, measuresCustomRows: true) { prompt })
    host.frame = .init(x: 0, y: 0, width: 240, height: 250); window.contentView = host
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.08))
    let scroll = try XCTUnwrap(descendants(host, NSScrollView.self).first)
    XCTAssertNotEqual(scroll.contentView.bounds.height, 184, "The ASL viewport must use measured hand rows")
    XCTAssertEqual(scroll.contentView.bounds.height, ceil((28 * 1.10 + 12) * 3), accuracy: 1)
    XCTAssertFalse(window.isVisible)
  }

  func testActualSwiftUIRetirementRebasesFramesButKeepsInputAndCorrectionBoundaryWithoutCarets() throws {
    let model = Model(); model.smooth = false
    let (window, host) = mount(model)
    defer { window.contentView = nil; window.close() }
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    XCTAssertEqual(descendants(host, PromptAutoScrollView.self).count, 1)
    model.session.insertBatch("a\n", at: start); pump(host)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
    model.session.insertBatch("b\n", at: start.addingTimeInterval(1)); pump(host); pump(host)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 1)
    XCTAssertEqual(String(model.rendering.text.characters), "b\nc\nd\ne")
    XCTAssertNil(container.measuredRect(for: 0)); XCTAssertNil(container.measuredRect(for: 1))
    let scroll = try XCTUnwrap(descendants(host, NSScrollView.self).first)
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 1)
    XCTAssertEqual(try XCTUnwrap(container.measuredRect(for: 2)).minY, 0, accuracy: 1)
    XCTAssertEqual(try XCTUnwrap(container.measuredRect(for: 4)).minY, 28 * 1.1 + 12, accuracy: 1)
    try capture(host, "asl-scroll-retired-no-markers")
    model.session.deleteWordBackward(at: start.addingTimeInterval(2))
    model.session.deleteBackward(at: start.addingTimeInterval(3)); pump(host)
    XCTAssertEqual(model.session.typed, "a\n")
    XCTAssertEqual(model.session.prompt, "a\nb\nc\nd\ne")
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 1)
    XCTAssertFalse(window.isVisible)
  }

  func testSmoothActualASLRetiresOnlyAfterAnimationAndContinuesThroughShortFinalRows() throws {
    let model = Model(); model.markers = true
    let (window, host) = mount(model)
    defer { window.contentView = nil; window.close() }
    model.session.insertBatch("a\n", at: start); pump(host)
    model.session.insertBatch("b\n", at: start.addingTimeInterval(1)); pump(host, 0.015)
    XCTAssertTrue(model.retired.isEmpty)
    pump(host, 0.22); pump(host)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 1)
    model.session.insertBatch("c\n", at: start.addingTimeInterval(2)); pump(host, 0.22); pump(host)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 2)
    model.session.insertBatch("d\n", at: start.addingTimeInterval(3)); pump(host, 0.22); pump(host)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 3)
    XCTAssertEqual(model.session.typed, "a\nb\nc\nd\n")
    XCTAssertEqual(String(model.rendering.text.characters), "d\ne")
    let scroll = try XCTUnwrap(descendants(host, NSScrollView.self).first)
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 1)
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    XCTAssertLessThan(try XCTUnwrap(container.measuredRect(for: 8)).maxY, scroll.contentView.bounds.height)
    XCTAssertEqual(descendants(host, PromptCaretNativeView.self).count, 1)
    try capture(host, "asl-scroll-short-final-markers")
    XCTAssertFalse(window.isVisible)
  }

  func testOversizedWordContainerRetiresAsOneUnitWithoutLosingOriginalInput() throws {
    let prompt = "aaaaaaaaaaaaaaaaa bbbbbbb ccccccc ddddddd eeeeeee"
    let model = Model(); model.smooth = false
    model.session = TypingSession(configuration: .words(5, rules: .init(freedomMode: true)), prompt: prompt)
    let (window, host) = mount(model)
    defer { window.contentView = nil; window.close() }
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let word = try XCTUnwrap(container.measuredWordRect(for: 0))
    XCTAssertGreaterThan(word.height, try XCTUnwrap(container.measuredRect(for: 0)).height * 2)
    XCTAssertGreaterThan(try XCTUnwrap(container.measuredWordRect(for: 18)).minY, word.maxY)
    model.session.insertBatch("aaaaaaaaaaaaaaaaa ", at: start); pump(host)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
    model.session.insertBatch("bbbbbbb ", at: start.addingTimeInterval(1)); pump(host); pump(host)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 1)
    XCTAssertNil(container.measuredWordRect(for: 0)); XCTAssertNil(container.measuredRect(for: 16))
    XCTAssertEqual(try XCTUnwrap(container.measuredWordRect(for: 18)).minY, 0, accuracy: 1)
    XCTAssertEqual(model.session.typed, "aaaaaaaaaaaaaaaaa bbbbbbb ")
    XCTAssertEqual(model.session.prompt, prompt)
    try capture(host, "asl-word-oversized-retired")
    model.session.deleteWordBackward(at: start.addingTimeInterval(2))
    model.session.deleteBackward(at: start.addingTimeInterval(3)); pump(host)
    XCTAssertEqual(model.session.typed, "aaaaaaaaaaaaaaaaa ")
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 1)
    XCTAssertFalse(window.isVisible)
  }

  func testReducedMotionUsesImmediateRetirementWithSmoothSettingEnabled() throws {
    let model = Model(); model.reduced = true
    let (window, host) = mount(model)
    defer { window.contentView = nil; window.close() }
    model.session.insertBatch("a\n", at: start); pump(host)
    model.session.insertBatch("b\n", at: start.addingTimeInterval(1)); pump(host)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 1)
    XCTAssertEqual(model.retired.count, 1)
  }

  func testActualViewportRemeasuresLargerHandsAndTwoLineMode() throws {
    let model = Model()
    let (window, host) = mount(model)
    defer { window.contentView = nil; window.close() }
    model.fontSize = 40; model.lineCount = 2; pump(host); pump(host)
    let scroll = try XCTUnwrap(descendants(host, NSScrollView.self).first)
    XCTAssertEqual(scroll.contentView.bounds.height, ceil((40 * 1.1 + 12) * 2), accuracy: 1)
    try capture(host, "asl-scroll-two-large-rows")
  }

  func testShowAllLinesRemovesFollowerAndDoesNotRetireWords() throws {
    let model = Model(); model.showsAll = true
    let (window, host) = mount(model)
    defer { window.contentView = nil; window.close() }
    model.session.insertBatch("a\nb\nc\n", at: start); pump(host, 0.2)
    XCTAssertTrue(descendants(host, PromptAutoScrollView.self).isEmpty)
    XCTAssertTrue(model.retired.isEmpty)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
  }

  func testMeasuredMixedRowsAndMissingIDsDoNotFallBackToLatinFont() throws {
    let geometry = ASLPromptLineGeometry(frames: [10: .init(x: 0, y: 0, width: 28, height: 31),
      11: .init(x: 28, y: 0, width: 20, height: 40), 20: .init(x: 0, y: 52, width: 28, height: 26),
      30: .init(x: 0, y: 90, width: 28, height: 31), 99: .zero])
    XCTAssertEqual(geometry.rowHeights, [52, 38, 43])
    let row = try XCTUnwrap(geometry.measure(active: 20, previous: 10, caret: 30,
      words: [.init(index: 0, glyphID: 10), .init(index: 1, glyphID: 20)]))
    XCTAssertEqual(row.activeTop, 52); XCTAssertEqual(row.previousWordTop, 0)
    XCTAssertEqual(row.activeRowHeight, 38); XCTAssertEqual(row.caretBottom, 121)
    XCTAssertNil(geometry.measure(active: 99, previous: 10, caret: nil, words: []))
    XCTAssertNil(geometry.measure(active: 404, previous: 10, caret: nil, words: []))
  }

  private final class Document: NSView { override var isFlipped: Bool { true } }
  private func fixture() -> (NSScrollView, ASLPromptCaretContainer, [Int: CGRect]) {
    let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 240, height: 129))
    let document = Document(frame: .init(x: 0, y: 0, width: 240, height: 500)); scroll.documentView = document
    let view = ASLPromptCaretContainer(frame: document.bounds); document.addSubview(view)
    let frames = Dictionary(uniqueKeysWithValues: (0..<6).map { ($0 * 2, CGRect(x: 0, y: CGFloat($0) * 43, width: 28, height: 31)) })
    return (scroll, view, frames)
  }
  private func update(_ view: ASLPromptCaretContainer, row: Int, attempt: UUID, frames: [Int: CGRect],
    callback: @escaping (PromptWordRetirement) -> Void) {
    view.configure(nil, frames: frames, glyphIDs: Array(stride(from: 0, through: 10, by: 2)),
      lineScroll: .init(attemptID: attempt, activeWordID: row * 2,
        characterOffsets: Dictionary(uniqueKeysWithValues: (0..<6).map { ($0 * 2, $0 * 2) }),
        smoothScroll: true, reducesMotion: false, words: (0..<6).map { .init(index: $0, glyphID: $0 * 2) },
        onRetire: callback), caretGlyphID: row * 2, text: AttributedString("a\nb\nc\nd\ne\nf"), font: font)
    pump(view, 0.005)
  }

  func testRestartAndDetachCancelPendingASLRetirement() {
    for detach in [false, true] {
      let (scroll, view, frames) = fixture(), attempt = UUID()
      defer { view.stop(); scroll.documentView = nil }
      var events: [PromptWordRetirement] = []
      for row in 0...2 { update(view, row: row, attempt: attempt, frames: frames) { events.append($0) } }
      if detach { view.removeFromSuperview() }
      else { update(view, row: 0, attempt: UUID(), frames: frames) { events.append($0) } }
      pump(view, 0.22)
      XCTAssertTrue(events.isEmpty)
      if !detach { XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 1) }
    }
  }

  func testOverlappingASLJumpsOnlyFinishLatestBoundary() {
    let (scroll, view, frames) = fixture(), attempt = UUID()
    defer { view.stop(); scroll.documentView = nil }
    var events: [Int] = []
    for row in 0...3 { update(view, row: row, attempt: attempt, frames: frames) { events.append($0.firstRetainedWordIndex) } }
    XCTAssertTrue(events.isEmpty); pump(view, 0.22)
    XCTAssertEqual(events, [2]); XCTAssertEqual(scroll.contentView.bounds.minY, 86, accuracy: 1)
  }

  func testMissingMeasuredActiveWordCannotUseValidTextOffsetsToScroll() {
    let (scroll, view, frames) = fixture(), attempt = UUID()
    defer { view.stop(); scroll.documentView = nil }
    var events: [Int] = []
    update(view, row: 0, attempt: attempt, frames: frames) { events.append($0.firstRetainedWordIndex) }
    update(view, row: 3, attempt: attempt, frames: [0: frames[0]!]) { events.append($0.firstRetainedWordIndex) }
    pump(view, 0.22)
    XCTAssertEqual(scroll.contentView.bounds.minY, 0); XCTAssertTrue(events.isEmpty)
  }

  func testTurningBothMarkersOffHidesExistingCaretWithoutRemovingScrollOwner() throws {
    let model = Model(); model.markers = true
    let (window, host) = mount(model)
    defer { window.contentView = nil; window.close() }
    let caret = try XCTUnwrap(descendants(host, PromptCaretNativeView.self).first)
    XCTAssertFalse(caret.isHidden)
    model.markers = false; pump(host)
    XCTAssertTrue(caret.isHidden, "Stopping its timer must also hide the previous marker pixels")
    XCTAssertEqual(descendants(host, PromptAutoScrollView.self).count, 1)
    model.smooth = false; model.session.insertBatch("a\n", at: start); pump(host)
    model.session.insertBatch("b\n", at: start.addingTimeInterval(1)); pump(host)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 1)
    model.markers = true; pump(host)
    XCTAssertFalse(caret.isHidden)
    XCTAssertEqual(descendants(host, PromptCaretNativeView.self).count, 1)
  }

  func testActualHandRowMetricsAgainstCompletePinnedLineJumpAndRemoval() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned clean reference and Anime.js archive")
    }
    struct Step: Decodable { let activeTop, previousWordTop, expectedOrigin, duration: Double }
    struct Fixture: Decodable { let smooth: Bool; let rowHeight: Double; let steps: [Step] }
    struct Evidence: Decodable { let fixtures: [Fixture] }
    let (window, host) = mount(Model())
    defer { window.contentView = nil; window.close() }
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let frames = try Dictionary(uniqueKeysWithValues: stride(from: 0, through: 8, by: 2).map {
      ($0, try XCTUnwrap(container.measuredRect(for: $0)))
    })
    let measured = ASLPromptLineGeometry(frames: frames)
    // SwiftUI rounds each placement to backing pixels (43, 86, 128, 171),
    // not five identical 43-point steps. The owned uniform source fixture uses
    // the measured cumulative step; individual anchors still stay within 0.5pt.
    let rowHeight = (try XCTUnwrap(frames[8]).minY - XCTUnwrap(frames[0]).minY) / 4
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-line-scroll.mjs").path,
      reference, "--emit-fixtures", "[\(rowHeight)]"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    guard process.terminationStatus == 0 else { return }
    let evidence = try JSONDecoder().decode(Evidence.self, from: data)
    XCTAssertEqual(evidence.fixtures.count, 8)
    for fixture in evidence.fixtures.filter({ abs($0.rowHeight - rowHeight) < 0.001 }) {
      var origin: CGFloat = 0
      for (index, step) in fixture.steps.prefix(4).enumerated() {
        let row = index + 1
        let geometry = try XCTUnwrap(measured.measure(active: row * 2, previous: index * 2, caret: row * 2,
          words: (0..<5).map { .init(index: $0, glyphID: $0 * 2) }))
        XCTAssertEqual(geometry.activeTop, step.activeTop, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(geometry.previousWordTop), step.previousWordTop, accuracy: 0.5)
        XCTAssertEqual(geometry.retirementBoundary(before: row), row > 1 ? row - 1 : nil)
        origin = geometry.targetTop(previousTarget: origin, recenter: false)
        XCTAssertEqual(origin, step.expectedOrigin, accuracy: 0.5)
        XCTAssertEqual(step.duration, fixture.smooth && row > 1 ? PromptLineScrollMotion.duration : 0)
      }
    }
  }

  func testLongSingleTokenFollowsActualCaretRowWithoutRetiringItsActiveWord() throws {
    let model = Model(); model.smooth = false
    model.session = TypingSession(configuration: .words(1), prompt: String(repeating: "a", count: 60))
    let (window, host) = mount(model)
    defer { window.contentView = nil; window.close() }
    model.session.insertBatch(String(repeating: "a", count: 48), at: start); pump(host)
    let scroll = try XCTUnwrap(descendants(host, NSScrollView.self).first)
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let caret = try XCTUnwrap(container.measuredRect(for: 48))
    XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
    XCTAssertLessThanOrEqual(caret.maxY - scroll.contentView.bounds.minY, scroll.contentView.bounds.height + 1)
    XCTAssertTrue(model.retired.isEmpty)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
    try capture(host, "asl-scroll-long-token")
  }

  func testActualMixedFallbackRowsDetermineViewportHeight() throws {
    let model = Model(); model.session = TypingSession(configuration: .words(4), prompt: "A🙂\nßB\nCD\nEF")
    let (window, host) = mount(model)
    defer { window.contentView = nil; window.close() }
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let frames = try Dictionary(uniqueKeysWithValues: [0, 1, 3, 4, 6, 7, 9, 10].map {
      ($0, try XCTUnwrap(container.measuredRect(for: $0)))
    })
    let actual = ASLPromptLineGeometry(frames: frames)
    let scroll = try XCTUnwrap(descendants(host, NSScrollView.self).first)
    XCTAssertEqual(scroll.contentView.bounds.height,
      try XCTUnwrap(PromptViewportLayout.height(forRowHeights: actual.rowHeights, lineCount: 3)), accuracy: 1)
    XCTAssertGreaterThan(try XCTUnwrap(frames[3]).height, 0)
    try capture(host, "asl-scroll-mixed-fallback")
  }
}
