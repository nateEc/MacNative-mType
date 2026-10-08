import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class ASLPromptRetainedRenderingTests: XCTestCase {
  private func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
    (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
  }

  private func capture(_ view: NSView, _ name: String) throws {
    guard let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] else { return }
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
      to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
  }

  func testCellPlanMaterializesOnlyThreeRetainedCellsFromTwentyThousandRetiredGlyphs() {
    let glyphs = (String(repeating: "a\n", count: 10_000) + "b\nc").map {
      TypingPromptGlyph(character: $0, state: .correct)
    }
    let ids = Array(glyphs.indices), retained = Array(20_000..<20_003)
    let rendering = PromptRendering.make(glyphs: glyphs, indices: retained) { _, glyph in
      AttributedString(PromptControlCharacterPresentation.plan(for: glyph, style: .off).text)
    }
    let plan = ASLPromptCellPlan(glyphs: glyphs, ids: ids, rendering: rendering)
    XCTAssertEqual(plan.cells.map(\.id), retained)
    XCTAssertEqual(plan.cells.map { String($0.content.main.characters) }, ["b", "↵", "c"])
    XCTAssertEqual(plan.cells.map { $0.content.ownsLineBreak }, [false, true, false])
    XCTAssertEqual(glyphs.count, 20_003); XCTAssertEqual(rendering.glyphCharacterOffsets.count, 3)
  }

  func testRealReorderedExtrasKeepCanonicalIdentityUnicodeHintsAndWordOwnership() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd")
    session.insertBatch("abx", at: Date(timeIntervalSinceReferenceDate: 914_000_000))
    let glyphs = session.promptGlyphs, words = session.promptWordPresentations
    let extraID = try XCTUnwrap(words[0].extraGlyphIndices.first)
    let ids = PromptGlyphLayout.indices(glyphs: glyphs, words: words, hideExtraLetters: false)
    let retained = Array(ids.dropFirst(2))
    let rendering = PromptRendering.make(glyphs: glyphs, indices: retained) { id, glyph in
      if id == extraID {
        var body = AttributedString("🙂"); body.foregroundColor = .orange
        var hint = AttributedString("候"); hint.baselineOffset = -12; hint.foregroundColor = .red
        return body + hint
      }
      return AttributedString(String(glyph.character))
    }
    let cells = ASLPromptCellPlan(glyphs: ids.map { glyphs[$0] }, ids: ids, rendering: rendering).cells
    XCTAssertEqual(cells.map(\.id), retained); XCTAssertEqual(cells.first?.id, extraID)
    XCTAssertEqual(String(try XCTUnwrap(cells.first).content.main.characters), "🙂")
    XCTAssertEqual(String(try XCTUnwrap(cells.first?.content.hint).characters), "候")
    XCTAssertEqual(cells.first?.content.main.foregroundColor, .orange)
    let ownership = ASLPromptWordPlan(glyphs: cells.map(\.glyph), ids: cells.map(\.id), words: words)
    XCTAssertEqual(ownership.wordByGlyphID[extraID], 0)
    XCTAssertEqual(Set(ownership.wordByGlyphID.keys), Set(retained))
    XCTAssertEqual(session.typed, "abx"); XCTAssertEqual(session.prompt, "ab cd")
  }

  func testHiddenRetainedInkIsNotConfusedWithMissingRenderingIDs() {
    let glyphs = "abc".map { TypingPromptGlyph(character: $0, state: .hidden) }
    var text = AttributedString("bc"); text.foregroundColor = .clear
    let cells = ASLPromptCellPlan(glyphs: glyphs, ids: [10, 11, 12],
      rendering: .init(text: text, glyphCharacterOffsets: [11: 0, 12: 1])).cells
    XCTAssertEqual(cells.map(\.id), [11, 12])
    XCTAssertEqual(cells.map { String($0.content.main.characters) }, ["b", "c"])
    XCTAssertTrue(cells.allSatisfy { $0.content.main.foregroundColor == .clear })
  }

  func testEmptySharedRenderingRemainsEmptyWhileLegacyNilAndFallbackIDsStillWork() {
    let glyphs = "a\n".map { TypingPromptGlyph(character: $0, state: .pending) }
    XCTAssertTrue(ASLPromptCellPlan(glyphs: glyphs, ids: [5, 6],
      rendering: .init(text: AttributedString(), glyphCharacterOffsets: [:])).cells.isEmpty)
    let legacy = ASLPromptCellPlan(glyphs: glyphs, ids: [], rendering: nil)
    XCTAssertEqual(legacy.cells.map(\.id), [0, 1])
    XCTAssertEqual(legacy.cells.map { String($0.content.main.characters) }, ["a", "↵"])
    let fallback = ASLPromptCellPlan(glyphs: glyphs, ids: [99],
      rendering: .init(text: AttributedString("↵\n"), glyphCharacterOffsets: [1: 0]))
    XCTAssertEqual(fallback.cells.map(\.id), [1])
    XCTAssertTrue(fallback.cells[0].content.ownsLineBreak)
  }

  func testZenEmptyPlaceholderSurvivesSelectionButCannotRestoreMissingCells() {
    let glyphs: [TypingPromptGlyph] = [.init(character: "a", state: .correct),
      .init(character: "\n", state: .correct), .init(character: " ", state: .current)]
    var text = AttributedString("_"); text.foregroundColor = .clear
    let rendering = PromptRendering(text: text, glyphCharacterOffsets: [2: 0], emptyWordPlaceholderGlyphID: 2)
    let cells = ASLPromptCellPlan(glyphs: glyphs, ids: [0, 1, 2], rendering: rendering).cells
    XCTAssertEqual(cells.map(\.id), [2]); XCTAssertEqual(String(cells[0].content.main.characters), "_")
    XCTAssertEqual(cells[0].content.main.foregroundColor, .clear)
    let words = [TypingPromptWordPresentation(range: 2..<2, phase: .active, hasInputError: false, hasCommitError: false)]
    let plan = ASLPromptWordPlan(glyphs: cells.map(\.glyph), ids: cells.map(\.id), words: words,
      placeholderGlyphID: rendering.emptyWordPlaceholderGlyphID)
    XCTAssertEqual(plan.wordByGlyphID, [2: 2])
    XCTAssertTrue(ASLPromptCellPlan(glyphs: glyphs, ids: [0, 1, 2],
      rendering: .init(text: AttributedString(), glyphCharacterOffsets: [:], emptyWordPlaceholderGlyphID: 2)).cells.isEmpty)
  }

  func testRetainedSelectionDoesNotInventAFutureCapOrAnEarlyRetirementBoundary() {
    let glyphs = Array(repeating: TypingPromptGlyph(character: "a", state: .pending), count: 5_000)
    let ids = Array(glyphs.indices)
    let rendering = PromptRendering.make(glyphs: glyphs, indices: ids) { _, _ in AttributedString("a") }
    let plan = ASLPromptCellPlan(glyphs: glyphs, ids: ids, rendering: rendering)
    XCTAssertEqual(plan.cells.count, 5_000); XCTAssertEqual(plan.cells.map(\.id), ids)
    XCTAssertTrue(plan.cells.allSatisfy { $0.glyph.state == .pending })
  }

  func testProductionASLBuildsRetainedCellsBeforeItsCanonicalSwiftUIForEach() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let start = try XCTUnwrap(app.range(of: "struct ASLPracticePrompt: View {"))
    let end = try XCTUnwrap(app.range(of: "private struct SpacePracticeOverlay:", range: start.upperBound..<app.endIndex))
    let body = app[start.upperBound..<end.lowerBound]
    XCTAssertTrue(body.contains("ASLPromptCellPlan(")); XCTAssertTrue(body.contains("ForEach(cells)"))
    XCTAssertFalse(body.contains("glyphs.enumerated()")); XCTAssertFalse(body.contains("EmptyView()"))
    XCTAssertTrue(body.contains("glyphs: visibleGlyphs"))
  }

  func testRetiredWordOwnershipAllocatesOnlyRetainedCanonicalIDs() {
    let characters = Array(String(repeating: "a\n", count: 10_000))
    let words = TypingPromptWordPresentation.ranges(in: characters).map {
      TypingPromptWordPresentation(range: $0, phase: .committed, hasInputError: false, hasCommitError: false)
    }
    let ids = Array((characters.count - 4)..<characters.count)
    let glyphs = ids.map { TypingPromptGlyph(character: characters[$0], state: .correct) }
    let plan = ASLPromptWordPlan(glyphs: glyphs, ids: ids, words: words)
    XCTAssertEqual(Set(plan.wordByGlyphID.keys), Set(ids), "Retired ownership must not grow with all original words")
    XCTAssertEqual(plan.wordByGlyphID[19_997], 19_996)
    XCTAssertEqual(plan.wordByGlyphID[19_999], 19_998)
  }

  func testActualLongRetiredPrefixKeepsOnlyRetainedFramesAndCaretCoordinates() throws {
    let prefix = String(repeating: "a\n", count: 10_000), suffix = "b\nc"
    let glyphs = (prefix + suffix).map { TypingPromptGlyph(character: $0, state: .correct) }
    let ids = Array(glyphs.indices), retained = Array(prefix.count..<glyphs.count)
    let rendering = PromptRendering.make(glyphs: glyphs, indices: retained) { _, glyph in
      var text = AttributedString(PromptControlCharacterPresentation.plan(for: glyph, style: .off).text)
      text.foregroundColor = .black; return text
    }
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    let config = PromptCaretNativeView.Configuration(text: AttributedString(), mainOffset: nil, paceOffset: nil,
      mainStyle: .bar, paceStyle: .off, font: font, lineSpacing: 12, rightToLeft: false,
      accent: .blue, motion: .off, reducesMotion: true, frameRate: 60, attemptID: UUID(),
      coordinator: PromptCaretMotionCoordinator(), mainGlyphID: retained.last, automaticallyPresents: false)
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 240, height: 180),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    defer { window.contentView = nil; window.close() }
    let started = ProcessInfo.processInfo.systemUptime
    let host = NSHostingView(rootView: ASLPracticePrompt(glyphs: glyphs, fontSize: 28, accent: .blue,
      glyphIDs: ids, rendering: rendering, carets: config, font: font)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color.white))
    window.contentView = host; host.frame = .init(x: 0, y: 0, width: 240, height: 180)
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.04)); host.layoutSubtreeIfNeeded()
    print("ASL retained mounted 20000 retired / 3 retained: \(ProcessInfo.processInfo.systemUptime - started) seconds")
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    XCTAssertNil(container.measuredRect(for: 0)); XCTAssertNil(container.measuredRect(for: 19_999))
    let first = try XCTUnwrap(container.measuredRect(for: 20_000))
    let last = try XCTUnwrap(container.measuredRect(for: 20_002))
    XCTAssertEqual(first.minY, 0, accuracy: 1); XCTAssertGreaterThan(last.minY, first.maxY)
    XCTAssertEqual(container.rect(for: 20_002), last)
    XCTAssertNil(container.rect(for: 19_999)); XCTAssertFalse(window.isVisible)
    try capture(host, "asl-retained-long-prefix")
    let caret = try XCTUnwrap(descendants(host, PromptCaretNativeView.self).first)
    host.rootView = ASLPracticePrompt(glyphs: glyphs, fontSize: 28, accent: .blue, glyphIDs: ids,
      rendering: .init(text: AttributedString("c"), glyphCharacterOffsets: [20_002: 0]), carets: config, font: font)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color.white)
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.04)); host.layoutSubtreeIfNeeded()
    let updated = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    XCTAssertTrue(updated === container)
    XCTAssertTrue(try XCTUnwrap(descendants(host, PromptCaretNativeView.self).first) === caret)
    XCTAssertEqual(descendants(host, ASLPromptCaretContainer.self).count, 1)
    XCTAssertNil(updated.measuredRect(for: 20_000)); XCTAssertNil(updated.measuredRect(for: 20_001))
    XCTAssertEqual(try XCTUnwrap(updated.measuredRect(for: 20_002)).minY, 0, accuracy: 1)
    try capture(host, "asl-retained-next-prefix")
  }
}
