import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class ASLPromptCompositionTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 916_500_000)
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)

  private func render(_ session: TypingSession, _ marked: String = "",
    style: CompositionDisplayStyle = .replace) throws -> (PromptCompositionPresentation, PromptRendering) {
    let value = try XCTUnwrap(PromptCompositionPresentation(session: session, composition: marked, style: style))
    let result = value.render { index, glyph, cell in
      let plan = PromptControlCharacterPresentation.plan(for: glyph, style: .both,
        isZen: value.isZen, compositionReplacement: cell?.text,
        isEmptyWordPlaceholder: index == value.emptyPlaceholderIndex)
      var text = AttributedString(plan.text)
      text.foregroundColor = glyph.state == .hidden ? .clear : glyph.state == .correct ? .green : .orange
      if cell != nil { text.underlineStyle = .single; text.appKit.underlineColor = .magenta }
      if cell == nil, let hint = plan.hint {
        var tail = AttributedString(hint); tail.baselineOffset = -12; tail.foregroundColor = .red
        text += tail
      }
      return text
    }
    return (value, result)
  }

  private func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
    (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
  }
  private func settle(_ host: NSView) {
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.04))
    host.layoutSubtreeIfNeeded()
  }
  private func mounted(_ session: TypingSession, rendering: PromptRendering,
    motion: PromptCaretMotionCoordinator = .init(), pace: Int? = nil)
    -> (NSWindow, NSHostingView<ASLPracticePrompt>) {
    var config = PromptCaretNativeView.Configuration(text: AttributedString(), mainOffset: nil, paceOffset: nil,
      mainStyle: .bar, paceStyle: pace == nil ? .off : .bar, font: font, lineSpacing: 12,
      rightToLeft: false, accent: .blue, motion: .off, reducesMotion: true, frameRate: 30,
      attemptID: UUID(), coordinator: motion, mainGlyphID: session.promptCaretGlyphIndex, automaticallyPresents: false)
    if let pace { config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 1, sequence: 1, targetGlyphID: pace) } }
    let ids = PromptGlyphLayout.indices(glyphs: session.promptGlyphs,
      words: session.promptWordPresentations, hideExtraLetters: session.configuration.rules.hideExtraLetters)
    let host = NSHostingView(rootView: ASLPracticePrompt(glyphs: ids.map { session.promptGlyphs[$0] },
      fontSize: 28, accent: .blue, glyphIDs: ids, rendering: rendering, carets: config, font: font,
      words: session.promptWordPresentations))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 800, height: 220),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    window.contentView = host; host.frame = .init(x: 0, y: 0, width: 800, height: 220)
    settle(host)
    return (window, host)
  }

  func testEveryCompositionStyleRetainsVirtualOverflowAndFinalPerCellAttributes() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd")
    session.insertBatch("a", at: start)
    for style in CompositionDisplayStyle.allCases {
      let (value, result) = try render(session, "bXYZ", style: style)
      let expected = try XCTUnwrap(result.compositionTextMap).fieldRuns.flatMap(\.cells)
      let plan = ASLPromptCellPlan(glyphs: session.promptGlyphs, ids: Array(session.promptGlyphs.indices), rendering: result)
      XCTAssertTrue(value.projection.cells.contains { $0.id < 0 })
      XCTAssertEqual(plan.cells.map(\.id), expected.map(\.id), style.rawValue)
      XCTAssertEqual(plan.cells.map { $0.content.text }, expected.map(\.text))
      XCTAssertEqual(plan.cells.map(\.glyph), expected.map(\.glyph))
      XCTAssertEqual(session.typed, "a")
    }
  }

  func testCancelledCrossFieldGraphemeKeepsSeparateSlotsAndActualFieldBoxes() throws {
    var session = TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces]), customText: "a \u{301}b tail")
    session.insertBatch("a", at: start)
    let (value, result) = try render(session)
    let alias = try XCTUnwrap(value.projection.canonicalAliases[0])
    XCTAssertEqual(alias.count, 2)
    let (window, host) = mounted(session, rendering: result)
    defer { window.contentView = nil; window.close() }
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let first = try XCTUnwrap(container.measuredRect(for: alias[0]))
    let second = try XCTUnwrap(container.measuredRect(for: alias[1]))
    XCTAssertGreaterThanOrEqual(second.minX, first.maxX - 0.1)
    XCTAssertNotNil(container.measuredWordRect(for: 0))
    XCTAssertNotNil(container.measuredWordRect(for: 1))
    XCTAssertFalse(window.isVisible)
  }

  func testOverflowMainCaretFollowsItsActualLastSlotWhilePaceKeepsCanonicalTarget() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd")
    session.insertBatch("a", at: start)
    let (_, result) = try render(session, "bXYZ"), map = try XCTUnwrap(result.compositionTextMap)
    let anchor = try XCTUnwrap(map.caret); XCTAssertTrue(anchor.after)
    let motion = PromptCaretMotionCoordinator()
    let (window, host) = mounted(session, rendering: result, motion: motion, pace: 3)
    defer { window.contentView = nil; window.close() }
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let caret = try XCTUnwrap(descendants(host, PromptCaretNativeView.self).first)
    let last = try XCTUnwrap(container.measuredRect(for: anchor.cellID))
    caret.present(at: 0)
    XCTAssertEqual(try XCTUnwrap(motion.main.position).minX, last.maxX, accuracy: 0.1)
    XCTAssertEqual(motion.pace.position, container.measuredRect(for: 3))
    XCTAssertFalse(window.isVisible)
  }

  func testReturnBreakFollowsTheWholeProjectedFieldIncludingRealExtras() throws {
    var session = TypingSession(configuration: .words(2), prompt: "aa\nbb")
    session.insertBatch("aaxy", at: start)
    let (_, result) = try render(session)
    let firstField = try XCTUnwrap(result.compositionTextMap?.fieldRuns.first { $0.fieldID == 0 })
    let (window, host) = mounted(session, rendering: result)
    defer { window.contentView = nil; window.close() }
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let first = try XCTUnwrap(container.measuredRect(for: firstField.cells[0].id))
    for cell in firstField.cells { XCTAssertEqual(container.measuredRect(for: cell.id)?.minY, first.minY) }
    let next = try XCTUnwrap(container.measuredWordRect(for: 1))
    XCTAssertGreaterThan(next.minY, first.maxY)
  }

  func testRetiredFieldsDoNotReturnAsCanonicalCellsOrIncorrectWordOwners() throws {
    var session = TypingSession(configuration: .words(3), prompt: "aa bb cc")
    session.insertBatch("aa b", at: start)
    session.retirePromptWords(.init(attemptID: session.automaticInputAttemptID, firstRetainedWordIndex: 1))
    let (_, result) = try render(session, "bXYZ")
    let (window, host) = mounted(session, rendering: result)
    defer { window.contentView = nil; window.close() }
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    XCTAssertNil(container.measuredRect(for: 0)); XCTAssertNil(container.measuredRect(for: 1))
    XCTAssertNotNil(container.measuredWordRect(for: 1)); XCTAssertNotNil(container.measuredWordRect(for: 2))
  }

  func testMarkedExtraReturnCannotInventAStructuralTargetBreak() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd")
    session.insertBatch("ab", at: start)
    let (_, result) = try render(session, "\nX"), map = try XCTUnwrap(result.compositionTextMap)
    let native = PromptFieldTextLayout(map: map, width: 800, font: font)
    XCTAssertEqual(native.fieldFrames[0]?.minY, native.fieldFrames[1]?.minY,
      "Structure follows the target field, never a marked extra Return")
    let (window, host) = mounted(session, rendering: result)
    defer { window.contentView = nil; window.close() }
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    XCTAssertEqual(container.measuredWordRect(for: 0)?.minY, container.measuredWordRect(for: 1)?.minY)
  }

  func testProductionProjectionGateDoesNotExcludeASLOnceItsAdapterIsAvailable() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let start = try XCTUnwrap(source.range(of: "let usesCompositionProjection ="))
    let end = try XCTUnwrap(source.range(of: "let presentation =", range: start.upperBound..<source.endIndex))
    XCTAssertFalse(source[start.lowerBound..<end.lowerBound].contains("!practiceVisualEffect.usesASL"))
  }

  func testProjectedZeroAdvanceCellCannotBorrowThePreviousFieldsBox() throws {
    var session = TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces]), customText: "a \u{301}b tail")
    session.insertBatch("a", at: start)
    let (_, result) = try render(session), map = try XCTUnwrap(result.compositionTextMap)
    let ids = map.fieldRuns.flatMap(\.cells).map(\.id)
    XCTAssertGreaterThan(ids.count, 1)
    let first = CGRect(x: 0, y: 0, width: 24, height: 30)
    let zero = CGRect(x: 24, y: 42, width: 0, height: 30)
    let container = ASLPromptCaretContainer(frame: .init(x: 0, y: 0, width: 300, height: 100))
    defer { container.stop() }
    container.configure(nil, frames: [ids[0]: first, ids[1]: zero], glyphIDs: ids, compositionMap: map)
    XCTAssertEqual(container.rect(for: ids[1]), zero,
      "A projected combining fragment keeps its own field/row, even with zero horizontal advance")
  }

  func testMountedProjectedComponentsCaptureOverflowCancellationAndReturnExtras() throws {
    var overflow = TypingSession(configuration: .words(2), prompt: "ab cd")
    overflow.insertBatch("a", at: start)
    var cancelled = TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces]), customText: "a \u{301}b tail")
    cancelled.insertBatch("a", at: start)
    var returns = TypingSession(configuration: .words(2), prompt: "aa\nbb")
    returns.insertBatch("aaxy", at: start)
    for (name, session, marked) in [("overflow", overflow, "bXYZ"),
      ("cancelled", cancelled, ""), ("return-extras", returns, "")] {
      let (_, result) = try render(session, marked)
      let (window, host) = mounted(session, rendering: result)
      defer { window.contentView = nil; window.close() }
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("asl-composition-" + name + ".png"))
      }
      XCTAssertGreaterThan(png.count, 300)
      XCTAssertFalse(window.isVisible)
    }
  }
}
