import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class ChooPromptRenderingTests: XCTestCase {
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
  private let palette = ChooGlyphPalette(theme: AppTheme.paper.resolvedTheme,
    flipsCompletionAndFuture: false, usesColorfulMode: false)

  private func layers(_ view: ChooLayerView) -> [CATextLayer] {
    (view.layer?.sublayers?.compactMap { $0 as? CATextLayer }.filter { $0.name != "chooHint" } ?? [])
      .sorted { $0.frame.minY == $1.frame.minY ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY }
  }

  private func text(_ layer: CATextLayer) throws -> NSAttributedString {
    try XCTUnwrap(layer.string as? NSAttributedString)
  }

  private func view(_ glyphs: [TypingPromptGlyph], ids: [Int], rendering: PromptRendering,
    width: CGFloat = 400, animates: Bool = true) -> ChooLayerView {
    let height = ChooLayerView.measure(glyphs: glyphs, font: font, width: width,
      glyphIDs: ids, rendering: rendering)
    let view = ChooLayerView(frame: .init(x: 0, y: 0, width: width, height: height))
    view.configure(glyphs: glyphs, font: font, palette: palette, animates: animates,
      frameRate: 30, glyphIDs: ids, rendering: rendering)
    return view
  }

  private func capture(_ view: NSView, _ name: String) throws {
    guard let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] else { return }
    let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = view
    defer { window.close() }
    view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
      to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
  }

  func testSharedCandidateAndUnicodeHintReachRealLayersWithoutChangingInput() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd")
    session.insertBatch("abx", at: Date(timeIntervalSinceReferenceDate: 915_000_000))
    let glyphs = session.promptGlyphs, words = session.promptWordPresentations
    let extra = try XCTUnwrap(words[0].extraGlyphIndices.first)
    let ids = PromptGlyphLayout.indices(glyphs: glyphs, words: words, hideExtraLetters: false)
    let rendering = PromptRendering.make(glyphs: glyphs, indices: ids, words: words) { id, glyph in
      var body = AttributedString(id == extra ? "候选🙂" : String(glyph.character))
      body.foregroundColor = .orange
      if id == extra {
        var hint = AttributedString("原"); hint.foregroundColor = .red
        hint.font = .system(size: 13); hint.baselineOffset = -12; hint.kern = -18
        body += hint
      }
      return body
    }
    let result = view(ids.map { glyphs[$0] }, ids: ids, rendering: rendering)
    defer { result.stopCarets() }
    let values = layers(result)
    XCTAssertEqual(try values.map { try text($0).string }, ["a", "b", "候选🙂", " ", "c", "d"])
    let candidate = values[2], hint = try XCTUnwrap(result.layer?.sublayers?.first { $0.name == "chooHint" } as? CATextLayer)
    XCTAssertEqual(try text(hint).string, "原")
    let hintFont = try XCTUnwrap(try text(hint).attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    XCTAssertEqual(hint.frame.minY + hintFont.ascender - font.ascender, 12, accuracy: 0.1,
      "Below means a baseline displacement, not a top-edge displacement")
    XCTAssertGreaterThan(result.frame.height, candidate.frame.maxY,
      "Last-row hints must remain inside the measured view")
    XCTAssertEqual(hint.frame.midX, candidate.frame.midX, accuracy: 0.1)
    XCTAssertNotNil(candidate.animation(forKey: "chooRotation"))
    XCTAssertTrue(hint.superlayer === result.layer, "Source hints are siblings, not rotating letter descendants")
    XCTAssertEqual(hint.animation(forKey: "chooRotation")?.beginTime,
      candidate.animation(forKey: "chooRotation")?.beginTime)
    XCTAssertEqual(values[3].frame.minX, candidate.frame.maxX - 2, accuracy: 0.1)
    XCTAssertEqual(result.accessibilityLabel(), String(rendering.text.characters))
    XCTAssertEqual(session.typed, "abx"); XCTAssertEqual(session.prompt, "ab cd")
    try capture(result, "choo-shared-candidate-hint")
    result.configure(glyphs: ids.map { glyphs[$0] }, font: font, palette: palette, animates: false,
      frameRate: 30, glyphIDs: ids, rendering: rendering)
    XCTAssertTrue(result.layer?.sublayers?.allSatisfy { $0.animation(forKey: "chooRotation") == nil } ?? false)
  }

  func testSharedColorsVisibilityUnderlineAndBackgroundOverrideLegacyPalette() throws {
    let glyphs = "abcd".map { TypingPromptGlyph(character: $0, state: .incorrect, typedCharacter: "X") }
    let rendering = PromptRendering.make(glyphs: glyphs, indices: [0, 1, 2, 3]) { id, glyph in
      var value = AttributedString(String(glyph.character))
      value.foregroundColor = id == 0 ? .clear : .green
      if id == 1 { value.backgroundColor = .blue }
      if id == 2 {
        value.underlineStyle = Text.LineStyle(color: .orange)
        value.appKit.underlineColor = .orange
      }
      return value
    }
    let result = view(glyphs, ids: [0, 1, 2, 3], rendering: rendering, animates: false)
    let values = layers(result)
    XCTAssertEqual(try values.map { try text($0).string }, ["a", "b", "c", "d"])
    let hidden = try XCTUnwrap(try text(values[0]).attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
    XCTAssertEqual(hidden.alphaComponent, 0)
    let green = try XCTUnwrap(try text(values[3]).attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
    XCTAssertEqual(green, NSColor(Color.green))
    XCTAssertNotNil(try text(values[1]).attribute(.backgroundColor, at: 0, effectiveRange: nil))
    XCTAssertEqual(try text(values[2]).attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
    XCTAssertNotNil(try text(values[2]).attribute(.underlineColor, at: 0, effectiveRange: nil))
    XCTAssertTrue(values.allSatisfy { $0.backgroundColor == nil && $0.animation(forKey: "chooRotation") == nil })
    try capture(result, "choo-shared-attributes")
  }

  func testRealTargetReturnAndExtraReturnHaveDifferentStructuralOwnership() throws {
    let glyphs: [TypingPromptGlyph] = [.init(character: "\n", state: .incorrect, typedCharacter: "X"),
      .init(character: "\n", state: .extra), .init(character: "b", state: .pending)]
    let rendering = PromptRendering.make(glyphs: glyphs, indices: [0, 1, 2]) { _, glyph in
      var value = AttributedString(PromptControlCharacterPresentation.plan(for: glyph, style: .replace).text)
      value.foregroundColor = .orange; return value
    }
    let result = view(glyphs, ids: [0, 1, 2], rendering: rendering)
    let values = layers(result)
    XCTAssertEqual(try values.map { try text($0).string }, ["X", "↵", "b"])
    XCTAssertGreaterThan(values[0].frame.width, 0)
    XCTAssertGreaterThan(values[1].frame.minY, values[0].frame.maxY)
    XCTAssertEqual(values[1].frame.minY, values[2].frame.minY)
    try capture(result, "choo-shared-control-ownership")
  }

  func testZenHiddenControlsAndEmptyPlaceholderReserveRealBoxes() throws {
    let glyphs: [TypingPromptGlyph] = [.init(character: "\t", state: .correct),
      .init(character: "\n", state: .correct), .init(character: " ", state: .current)]
    let rendering = PromptRendering.make(glyphs: glyphs, indices: [0, 1, 2], emptyWordPlaceholderGlyphID: 2) { id, glyph in
      let plan = PromptControlCharacterPresentation.plan(for: glyph, style: .off, isZen: true, isEmptyWordPlaceholder: id == 2)
      var value = AttributedString(plan.text); value.foregroundColor = .clear; return value
    }
    let result = view(glyphs, ids: [0, 1, 2], rendering: rendering)
    let values = layers(result)
    XCTAssertEqual(try values.map { try text($0).string }, ["→", "↵", "_"])
    XCTAssertTrue(values.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 })
    XCTAssertGreaterThan(values[2].frame.minY, values[1].frame.maxY)
  }

  func testRetirementPreservesAnonymousRowsAndNeverRestoresRemovedCanonicalIDs() throws {
    let glyphs = "a\nb\nc".map { TypingPromptGlyph(character: $0, state: .pending) }
    var retained = AttributedString("a\n\nc"); retained.foregroundColor = .orange
    let rendering = PromptRendering(text: retained, glyphCharacterOffsets: [0: 0, 4: 3],
      structuralNewlineOffsets: [0: 1, 1: 2])
    let plan = ChooPromptPresentation(glyphs: glyphs, ids: Array(glyphs.indices), rendering: rendering)
    XCTAssertEqual(plan.cells.map(\.id), [0, 4])
    XCTAssertEqual(plan.structuralBreaksBefore, [1: 2]); XCTAssertEqual(plan.trailingStructuralBreaks, 0)
    let result = view(glyphs, ids: Array(glyphs.indices), rendering: rendering)
    let values = layers(result)
    XCTAssertEqual(try values.map { try text($0).string }, ["a", "c"])
    XCTAssertGreaterThan(values[1].frame.minY, values[0].frame.height * 2)
    let coordinator = PromptCaretMotionCoordinator()
    let config = PromptCaretNativeView.Configuration(text: AttributedString(), mainOffset: nil, paceOffset: nil,
      mainStyle: .bar, paceStyle: .off, font: font, lineSpacing: 12, rightToLeft: false,
      accent: .blue, motion: .off, reducesMotion: true, frameRate: 30, attemptID: UUID(),
      coordinator: coordinator, mainGlyphID: 2, automaticallyPresents: false)
    result.configureCarets(config, glyphIDs: Array(glyphs.indices))
    let caret = try XCTUnwrap(result.subviews.compactMap { $0 as? PromptCaretNativeView }.first)
    caret.layout(); caret.present(at: 0)
    XCTAssertNil(coordinator.main.position, "Removed canonical IDs have no invented geometry")
    result.stopCarets()
    try capture(result, "choo-shared-retired-rows")
  }

  func testSharedWidthFontAndCanonicalCaretUseTheActualCandidateLayer() throws {
    let glyphs = "ab".map { TypingPromptGlyph(character: $0, state: .pending) }
    var body = AttributedString("候选🙂b"); body.foregroundColor = .orange
    let rendering = PromptRendering(text: body, glyphCharacterOffsets: [23: 0, 5: 3])
    let result = view(glyphs, ids: [23, 5], rendering: rendering, width: 85)
    defer { result.stopCarets() }
    let values = layers(result)
    XCTAssertGreaterThan(values[1].frame.minY, values[0].frame.minY)
    let oldHeight = values[1].frame.height
    let coordinator = PromptCaretMotionCoordinator()
    let config = PromptCaretNativeView.Configuration(text: AttributedString(), mainOffset: nil, paceOffset: nil,
      mainStyle: .bar, paceStyle: .off, font: font, lineSpacing: 12, rightToLeft: false,
      accent: .blue, motion: .off, reducesMotion: true, frameRate: 30, attemptID: UUID(),
      coordinator: coordinator, mainGlyphID: 5, automaticallyPresents: false)
    result.configureCarets(config, glyphIDs: [23, 5])
    let caret = try XCTUnwrap(result.subviews.compactMap { $0 as? PromptCaretNativeView }.first)
    caret.layout(); caret.present(at: 0)
    XCTAssertEqual(coordinator.main.position, values[1].frame)
    let larger = NSFont.monospacedSystemFont(ofSize: 40, weight: .regular)
    result.configure(glyphs: glyphs, font: larger, palette: palette, animates: true,
      frameRate: 30, glyphIDs: [23, 5], rendering: rendering)
    result.configureCarets(config, glyphIDs: [23, 5])
    caret.layout(); caret.present(at: 0.1)
    XCTAssertEqual(coordinator.main.position, layers(result)[1].frame)
    XCTAssertGreaterThan(try XCTUnwrap(coordinator.main.position).height, oldHeight)
  }

  func testCandidateUpdateCancellationAndStyleDoNotRestartRotationOrKeepOldHint() throws {
    let glyphs = "ab".map { TypingPromptGlyph(character: $0, state: .pending) }
    var body = AttributedString("候"); body.foregroundColor = .orange
    var hint = AttributedString("原"); hint.baselineOffset = -12; hint.foregroundColor = .red
    let first = PromptRendering(text: body + hint + AttributedString("b"), glyphCharacterOffsets: [0: 0, 1: 2])
    let result = view(glyphs, ids: [0, 1], rendering: first)
    let layer = try XCTUnwrap(layers(result).first)
    let begin = try XCTUnwrap(layer.animation(forKey: "chooRotation")).beginTime
    for candidate in ["候选🙂", "a"] {
      var value = AttributedString(candidate + "b"); value.foregroundColor = .green
      let next = PromptRendering(text: value, glyphCharacterOffsets: [0: 0, 1: candidate.count])
      result.configure(glyphs: glyphs, font: font, palette: palette, animates: true,
        frameRate: 30, glyphIDs: [0, 1], rendering: next)
      XCTAssertTrue(layers(result).first === layer)
      XCTAssertEqual(try text(layer).string, candidate)
      XCTAssertEqual(layer.animation(forKey: "chooRotation")?.beginTime, begin)
      XCTAssertTrue(layer.sublayers?.isEmpty ?? true)
      XCTAssertFalse(result.layer?.sublayers?.contains { $0.name == "chooHint" } ?? true)
    }
    result.configure(glyphs: glyphs, font: font, palette: palette, animates: false,
      frameRate: 30, glyphIDs: [0, 1], rendering: .init(text: AttributedString("ab"), glyphCharacterOffsets: [0: 0, 1: 1]))
    XCTAssertNil(layer.animation(forKey: "chooRotation"))
  }

  func testEmptySharedRenderingAndRetiredLongPrefixRemainBounded() throws {
    let glyphs = Array(repeating: TypingPromptGlyph(character: "a", state: .pending), count: 20_003)
    let ids = Array(glyphs.indices), retained = Array(20_000..<20_003)
    let rendering = PromptRendering.make(glyphs: glyphs, indices: retained) { _, _ in AttributedString("a") }
    let result = view(glyphs, ids: ids, rendering: rendering)
    XCTAssertEqual(layers(result).count, 3)
    XCTAssertEqual(result.accessibilityLabel(), "aaa")
    result.configure(glyphs: glyphs, font: font, palette: palette, animates: true,
      frameRate: 30, glyphIDs: ids, rendering: .init(text: AttributedString(), glyphCharacterOffsets: [:]))
    XCTAssertTrue(layers(result).isEmpty)
    XCTAssertEqual(result.accessibilityLabel(), "")
    let rowsOnly = PromptRendering(text: AttributedString("\n\n"), glyphCharacterOffsets: [:],
      structuralNewlineOffsets: [0: 0, 1: 1])
    let plan = ChooPromptPresentation(glyphs: [], ids: [], rendering: rowsOnly)
    XCTAssertTrue(plan.cells.isEmpty); XCTAssertEqual(plan.trailingStructuralBreaks, 2)
    XCTAssertGreaterThan(ChooLayerView.measure(glyphs: [], font: font, width: 400, rendering: rowsOnly), font.pointSize * 2)
  }

  func testSharedLongPromptKeepsBoundedLayersAndReachesTheActualTail() throws {
    let glyphs = Array(repeating: TypingPromptGlyph(character: "a", state: .pending), count: 3_000)
    let ids = Array(glyphs.indices)
    let rendering = PromptRendering.make(glyphs: glyphs, indices: ids) { id, _ in
      var value = AttributedString(id == 2_999 ? "尾" : "a"); value.foregroundColor = .orange; return value
    }
    let result = view(glyphs, ids: ids, rendering: rendering)
    let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 400, height: 240))
    scroll.documentView = result; scroll.layoutSubtreeIfNeeded()
    XCTAssertLessThan(layers(result).count, 500)
    XCTAssertEqual(result.accessibilityLabel(), String(repeating: "a", count: 2_999) + "尾")
    scroll.contentView.scroll(to: .init(x: 0, y: result.frame.height - 240))
    scroll.reflectScrolledClipView(scroll.contentView); scroll.layoutSubtreeIfNeeded()
    XCTAssertLessThan(layers(result).count, 500)
    XCTAssertTrue(try layers(result).contains { try text($0).string == "尾" })
  }

  func testStructuralRetiredReturnDoesNotLeakIntoPrecedingSharedCellInk() {
    let glyphs = "a\nb".map { TypingPromptGlyph(character: $0, state: .pending) }
    let rendering = PromptRendering(text: AttributedString("A\nB"),
      glyphCharacterOffsets: [0: 0, 2: 2], structuralNewlineOffsets: [1: 1])
    let cells = ASLPromptCellPlan(glyphs: glyphs, ids: [0, 1, 2], rendering: rendering).cells
    XCTAssertEqual(cells.map(\.id), [0, 2])
    XCTAssertEqual(cells.map { String($0.content.main.characters) }, ["A", "B"],
      "A retired word's structural row has no canonical ink owner")
  }

  func testProductionChooReceivesSharedRenderingThroughSizingAndLayerConfiguration() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let branchStart = try XCTUnwrap(app.range(of: "} else if practiceVisualEffect.usesChoo {"))
    let branchEnd = try XCTUnwrap(app.range(of: "} else if usesTapePractice {", range: branchStart.upperBound..<app.endIndex))
    XCTAssertTrue(app[branchStart.upperBound..<branchEnd.lowerBound].contains("rendering: rendering"),
      "Choo must consume the same final attributes as Text, Tape and ASL")
    let layerStart = try XCTUnwrap(app.range(of: "private struct ChooLayerPrompt:"))
    let layerEnd = try XCTUnwrap(app.range(of: "final class ChooLayerView:", range: layerStart.upperBound..<app.endIndex))
    let bridge = app[layerStart.upperBound..<layerEnd.lowerBound]
    XCTAssertTrue(bridge.contains("glyphIDs: glyphIDs, rendering: rendering"),
      "Sizing and configuration must retain shared text and canonical IDs")
  }
}
