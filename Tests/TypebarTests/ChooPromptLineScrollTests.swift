import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class ChooPromptLineScrollTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 916_700_000)

  @Observable final class Model {
    var session = TypingSession(configuration: .words(5, rules: .init(freedomMode: true)), prompt: "a\nb\nc\nd\ne")
    var smooth = false
    var reduced = false
    var showsAll = false
    var marked = ""
    var markers = false
    let motion = PromptCaretMotionCoordinator()
    var retired: [PromptWordRetirement] = []
    var rendering: PromptRendering {
      let projection = PromptCompositionPresentation(session: session, composition: marked, style: .replace)!
      return projection.render { index, glyph, cell in
        let plan = PromptControlCharacterPresentation.plan(for: glyph, style: .off,
          isZen: projection.isZen, compositionReplacement: cell?.text,
          isEmptyWordPlaceholder: index == projection.emptyPlaceholderIndex)
        var value = AttributedString(plan.text); value.foregroundColor = .orange; return value
      }
    }
  }

  private struct Root: View {
    let model: Model
    var body: some View {
      let rendering = model.rendering
      let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
      let context = PromptLineScrollContext(attemptID: model.session.automaticInputAttemptID,
        activeWordID: model.session.promptCompositionField?.index,
        characterOffsets: rendering.compositionTextMap?.fieldCharacterOffsets ?? [:],
        smoothScroll: model.smooth, reducesMotion: model.reduced,
        words: PromptLineScrollWord.compositionFields(model.session.promptCompositionField),
        firstRetainedWordIndex: model.session.firstRetainedPromptWordIndex,
        onRetire: { model.retired.append($0); model.session.retirePromptWords($0) },
        followsWordReflow: PromptWordReflowPolicy.isEnabled(mode: model.session.configuration.mode,
          slowTimer: false, showAllLines: model.showsAll), caretMotion: model.motion)
      let carets: PromptCaretNativeView.Configuration? = model.markers ? .init(text: AttributedString(),
        mainOffset: nil, paceOffset: nil, mainStyle: .bar, paceStyle: .outline, font: font,
        lineSpacing: 12, rightToLeft: false, accent: .blue, motion: .off, reducesMotion: model.reduced,
        frameRate: 60, attemptID: model.session.automaticInputAttemptID, coordinator: model.motion,
        paceFrame: { .init(fromCharacterOffset: nil, targetCharacterOffset: nil, fromAfter: false,
          targetAfter: false, fraction: 1, targetGlyphID: model.session.promptCaretGlyphIndex) },
        mainGlyphID: model.session.promptCaretGlyphIndex) : nil
      let prompt = ChooPracticePrompt(glyphs: model.session.promptGlyphsInDisplayOrder, rendering: rendering,
        font: font, palette: ChooGlyphPalette(theme: AppTheme.paper.resolvedTheme,
          flipsCompletionAndFuture: false, usesColorfulMode: false), isEnabled: true,
        reducesMotion: model.reduced, ignoresSystemReducedMotion: false,
        glyphIDs: PromptGlyphLayout.indices(glyphs: model.session.promptGlyphs,
          words: model.session.promptWordPresentations, hideExtraLetters: false),
        carets: carets,
        viewportLineCount: model.showsAll ? nil : (model.session.configuration.mode == .zen ? 2 : 3),
        lineScroll: model.showsAll ? nil : context)
      Group {
        if model.showsAll { prompt }
        else {
          PracticePromptViewport(text: rendering.text, font: font, lineSpacing: 12,
            isRightToLeft: false, lineCount: model.session.configuration.mode == .zen ? 2 : 3,
            measuresTextRows: false, measuresCustomRows: true) { prompt }
        }
      }.frame(width: 240).background(Color.white)
    }
  }

  private func pump(_ view: NSView, _ duration: TimeInterval = 0.05) {
    view.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(duration)); view.layoutSubtreeIfNeeded()
  }
  private func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
    (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
  }
  private func mount(_ model: Model) -> (NSWindow, NSHostingView<Root>) {
    let host = NSHostingView(rootView: Root(model: model))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 240, height: 250),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    host.frame = .init(x: 0, y: 0, width: 240, height: 250); pump(host)
    return (window, host)
  }

  func testImmediateRetirementUsesRealChooFieldsWithoutAnyCaretView() throws {
    let model = Model(), (window, host) = mount(model)
    defer { window.close() }
    XCTAssertEqual(descendants(host, PromptAutoScrollView.self).count, 1)
    XCTAssertTrue(descendants(host, PromptCaretNativeView.self).isEmpty)
    model.session.insertBatch("a\n", at: start); pump(host)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
    model.session.insertBatch("b\n", at: start.addingTimeInterval(1)); pump(host); pump(host)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 1)
    XCTAssertEqual(model.retired.map(\.firstRetainedWordIndex), [1])
    XCTAssertEqual(model.session.typed, "a\nb\n")
    XCTAssertEqual(model.session.prompt, "a\nb\nc\nd\ne")
    let values = try XCTUnwrap(descendants(host, ChooLayerView.self).first).layer?.sublayers?.compactMap { $0 as? CATextLayer } ?? []
    XCTAssertFalse(values.contains { ($0.string as? NSAttributedString)?.string == "a" })
    XCTAssertEqual(try XCTUnwrap(descendants(host, NSScrollView.self).first).contentView.bounds.minY, 0, accuracy: 1)
    XCTAssertFalse(window.isVisible)
  }

  func testSmoothRetirementWaitsForCompletionAndKeepsOneScrollOwner() throws {
    let model = Model(); model.smooth = true
    let (window, host) = mount(model); defer { window.close() }
    model.session.insertBatch("a\n", at: start); pump(host)
    model.session.insertBatch("b\n", at: start.addingTimeInterval(1)); pump(host, 0.015)
    XCTAssertTrue(model.retired.isEmpty)
    pump(host, 0.25); pump(host)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 1)
    for (index, word) in ["c\n", "d\n"].enumerated() {
      model.session.insertBatch(word, at: start.addingTimeInterval(Double(index + 2))); pump(host, 0.25); pump(host)
    }
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 3)
    XCTAssertEqual(model.retired.map(\.firstRetainedWordIndex), [1, 2, 3])
    XCTAssertEqual(descendants(host, PromptAutoScrollView.self).count, 1)
    XCTAssertTrue(descendants(host, PromptCaretNativeView.self).isEmpty)
    XCTAssertFalse(window.isVisible)
  }

  func testRemovingChooDuringPendingJumpCancelsRetirement() throws {
    let model = Model(); model.smooth = true
    let (window, host) = mount(model); defer { window.close() }
    model.session.insertBatch("a\n", at: start); pump(host)
    model.session.insertBatch("b\n", at: start.addingTimeInterval(1)); pump(host, 0.015)
    let owner = try XCTUnwrap(descendants(host, ChooLayerView.self).first)
    owner.stop(); pump(host, 0.25)
    XCTAssertTrue(model.retired.isEmpty)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
    XCTAssertTrue(descendants(owner, PromptAutoScrollView.self).isEmpty)
  }

  func testZenPlaceholderParticipatesInScrollRetirementWithoutCommittingMarkedText() throws {
    let model = Model()
    model.session = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(freedomMode: true)), prompt: "")
    let (window, host) = mount(model); defer { window.close() }
    for (index, word) in ["a\n", "b\n", "c\n"].enumerated() {
      model.session.insertBatch(word, at: start.addingTimeInterval(Double(index))); pump(host); pump(host)
    }
    XCTAssertGreaterThan(model.session.firstRetainedPromptWordIndex, 0)
    let accepted = model.session.typed
    model.marked = "候选"; pump(host)
    XCTAssertEqual(model.session.typed, accepted)
    XCTAssertEqual(descendants(host, PromptAutoScrollView.self).count, 1)
    XCTAssertFalse(window.isVisible)
  }

  func testRestartDropsPendingOldAttemptRetirement() throws {
    let model = Model(); model.smooth = true
    let (window, host) = mount(model); defer { window.close() }
    model.session.insertBatch("a\n", at: start); pump(host)
    model.session.insertBatch("b\n", at: start.addingTimeInterval(1)); pump(host, 0.015)
    let oldAttempt = model.session.automaticInputAttemptID
    model.session = TypingSession(configuration: .words(5), prompt: "a\nb\nc\nd\ne")
    XCTAssertNotEqual(model.session.automaticInputAttemptID, oldAttempt)
    pump(host, 0.25); pump(host)
    XCTAssertTrue(model.retired.isEmpty)
    XCTAssertEqual(model.session.typed, "")
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
    XCTAssertEqual(descendants(host, PromptAutoScrollView.self).count, 1)
  }

  func testProductionChooReceivesSharedWordScrollContextEvenWithoutCarets() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let start = try XCTUnwrap(source.range(of: "} else if practiceVisualEffect.usesChoo {"))
    let end = try XCTUnwrap(source.range(of: "} else if usesTapePractice {", range: start.upperBound..<source.endIndex))
    XCTAssertTrue(source[start.upperBound..<end.lowerBound].contains("lineScroll:"),
      "Choo must receive the same attempt/word-retirement policy as ordinary projected fields")
    XCTAssertTrue(source.contains("view.configureLineScroll(lineScroll)"),
      "The actual native Choo owner must update scrolling even when caret configuration is nil")
    XCTAssertTrue(source.contains("words: PromptLineScrollWord.compositionFields(field)"))
  }

  func testProjectedWordDirectoryIncludesZenEmptyActiveFieldAndOrdinaryFutureFields() throws {
    var zen = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "")
    zen.insertBatch("a\n", at: start)
    let field = try XCTUnwrap(zen.promptCompositionField)
    XCTAssertEqual(field.index, field.sourceFieldUTF16Ranges.count)
    XCTAssertEqual(PromptLineScrollWord.compositionFields(field).map(\.index), [0, 1])
    XCTAssertEqual(PromptLineScrollWord.compositionFields(field).map(\.glyphID), [0, 1])
    let ordinary = TypingSession(configuration: .words(3), prompt: "ab cd ef")
    XCTAssertEqual(PromptLineScrollWord.compositionFields(ordinary.promptCompositionField).map(\.index), [0, 1, 2])
    XCTAssertTrue(PromptLineScrollWord.compositionFields(nil).isEmpty)
  }

  func testReducedMotionRetiresImmediatelyAndHiddenMarkersKeepTheScrollOwner() throws {
    let model = Model(); model.smooth = true; model.reduced = true; model.markers = true
    let (window, host) = mount(model); defer { window.close() }
    let owner = try XCTUnwrap(descendants(host, PromptAutoScrollView.self).first)
    model.session.insertBatch("a\n", at: start); pump(host)
    model.session.insertBatch("b\n", at: start.addingTimeInterval(1)); pump(host); pump(host)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 1)
    XCTAssertEqual(descendants(host, PromptCaretNativeView.self).count, 1)
    XCTAssertNotNil(model.motion.main.position); XCTAssertNotNil(model.motion.pace.position)
    model.markers = false; pump(host)
    XCTAssertTrue(descendants(host, PromptCaretNativeView.self).isEmpty)
    XCTAssertTrue(try XCTUnwrap(descendants(host, PromptAutoScrollView.self).first) === owner)
  }

  func testAllLinesDoesNotInstallBoundedScrollOrRetireWords() throws {
    let model = Model(); model.showsAll = true
    let (window, host) = mount(model); defer { window.close() }
    model.session.insertBatch("a\nb\nc\n", at: start); pump(host)
    XCTAssertTrue(descendants(host, PromptAutoScrollView.self).isEmpty)
    XCTAssertTrue(descendants(host, NSScrollView.self).isEmpty)
    XCTAssertTrue(model.retired.isEmpty)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
  }

  func testLongFieldFollowsItsActualCaretRowWithoutRetiringTheActiveField() throws {
    let model = Model()
    model.session = TypingSession(configuration: .words(1), prompt: String(repeating: "a", count: 60))
    let (window, host) = mount(model); defer { window.close() }
    model.session.insertBatch(String(repeating: "a", count: 48), at: start); pump(host); pump(host)
    let scroll = try XCTUnwrap(descendants(host, NSScrollView.self).first)
    XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
    XCTAssertTrue(model.retired.isEmpty)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
    XCTAssertEqual(model.session.typed.count, 48)
  }

  func testActualChooRowsMatchCompletePinnedLineJumpAndRemoval() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference and QA-only Anime.js archive")
    }
    struct Step: Decodable { let activeTop, previousWordTop, expectedOrigin, duration: Double }
    struct Fixture: Decodable { let smooth: Bool; let rowHeight: Double; let steps: [Step] }
    struct Evidence: Decodable { let fixtures: [Fixture] }
    let model = Model(), (window, host) = mount(model); defer { window.close() }
    let values = try XCTUnwrap(descendants(host, ChooLayerView.self).first).layer?.sublayers?.compactMap { $0 as? CATextLayer } ?? []
    var frames: [Int: CGRect] = [:]
    for (index, text) in ["a", "b", "c", "d", "e"].enumerated() {
      let layer = try XCTUnwrap(values.first { ($0.string as? NSAttributedString)?.string == text })
      frames[index] = layer.frame
    }
    let geometry = ASLPromptLineGeometry(frames: frames, wordFrames: frames)
    let rowHeight = try XCTUnwrap(frames[1]).minY - XCTUnwrap(frames[0]).minY
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
        let measured = try XCTUnwrap(geometry.measure(active: row, previous: index, caret: row,
          words: (0..<5).map { .init(index: $0, glyphID: $0) }))
        XCTAssertEqual(measured.activeTop, step.activeTop, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(measured.previousWordTop), step.previousWordTop, accuracy: 0.1)
        XCTAssertEqual(measured.retirementBoundary(before: row), row > 1 ? row - 1 : nil)
        origin = measured.targetTop(previousTarget: origin, recenter: false)
        XCTAssertEqual(origin, step.expectedOrigin, accuracy: 0.1)
        XCTAssertEqual(step.duration, fixture.smooth && row > 1 ? PromptLineScrollMotion.duration : 0)
      }
    }
  }
}
