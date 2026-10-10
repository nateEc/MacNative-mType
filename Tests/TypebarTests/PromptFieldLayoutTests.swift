import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptFieldLayoutTests: XCTestCase {
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
  private let start = Date(timeIntervalSinceReferenceDate: 916_200_000)

  func testEdgeRebasePreservesTweenTimingWithChangingGlyphWidths() throws {
    var original = PromptCaretChannel()
    original.goTo(.init(x: 10, y: 0, width: 20, height: 30), at: 0, duration: 0)
    original.goTo(.init(x: 100, y: 0, width: 40, height: 30), at: 0, duration: 1, curve: .linear)
    var rebased = original
    rebased.rebaseHorizontalEdge(fromRTL: true, toRTL: false)
    XCTAssertEqual(try XCTUnwrap(rebased.position).minX, try XCTUnwrap(original.position).maxX)
    for time in [0.25, 0.5, 1.0] {
      original.sample(at: time); rebased.sample(at: time)
      XCTAssertEqual(try XCTUnwrap(rebased.position).minX, try XCTUnwrap(original.position).maxX,
        accuracy: 0.001)
      XCTAssertEqual(rebased.position?.size, original.position?.size)
      XCTAssertEqual(rebased.margin, original.margin)
      XCTAssertEqual(rebased.tapeMargin, original.tapeMargin)
    }
  }

  func testPaceDirectionChangePreservesTheLastPresentedMarkerBeforeTweening() throws {
    let value = try rendering("אב XY", marked: "א")
    let view = PromptFieldNativeView(frame: .init(x: 0, y: 0, width: 400, height: 180))
    defer { view.stop() }
    let motion = PromptCaretMotionCoordinator()
    var configuration = config(motion, style: .off, pace: .bar)
    configuration = .init(text: configuration.text, mainOffset: nil, paceOffset: nil,
      mainStyle: .off, paceStyle: .bar, font: font, lineSpacing: 12, rightToLeft: false,
      accent: .blue, motion: .off, reducesMotion: false, frameRate: 30,
      attemptID: configuration.attemptID, coordinator: motion, automaticallyPresents: false)
    configuration.fieldDirectionPerGlyph = true
    var target = 0, sequence = 1.0, fraction = 1.0
    var predecessor: PaceCaretGlyphAnchor?
    configuration.latestRendering = { value }
    configuration.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: true, fraction: fraction, stepDuration: 1,
      sequence: sequence, targetGlyphID: target, zeroDeadlinePredecessor: predecessor) }
    view.configure(rendering: value, font: font, carets: configuration)
    view.layout(); view.present(at: 0)
    let caret = try XCTUnwrap(view.subviews.compactMap { $0 as? PromptCaretNativeView }.first)
    let marker = try XCTUnwrap(caret.subviews.compactMap { $0 as? NSHostingView<PromptCaretMarkerView> }.first)
    let previous = marker.frame.midX
    target = 3; sequence = 2; fraction = 0
    view.present(at: 0.1)
    XCTAssertEqual(marker.frame.midX, previous, accuracy: 0.1,
      "Changing the target direction must not teleport the last presented edge")
    motion.sample(at: 1.1); fraction = 1; view.present(at: 1.1)
    XCTAssertEqual(marker.frame.midX, try XCTUnwrap(view.measuredRect(for: 3)).maxX, accuracy: 0.1)
    let latinEdge = marker.frame.midX
    target = 0; sequence = 3; fraction = 0
    view.present(at: 1.2)
    XCTAssertEqual(marker.frame.midX, latinEdge, accuracy: 0.1,
      "Returning to RTL must preserve the last presented LTR edge too")
    motion.sample(at: 2.2); fraction = 1; view.present(at: 2.2)
    XCTAssertEqual(marker.frame.midX, try XCTUnwrap(view.measuredRect(for: 0)).minX, accuracy: 0.1)
    predecessor = .init(glyphIndex: 3, after: true)
    sequence = 5; fraction = 0
    caret.requestPacePosition(at: 2.3, fromDeadline: true)
    view.present(at: 2.3)
    XCTAssertEqual(marker.frame.midX, try XCTUnwrap(view.measuredRect(for: 3)).maxX, accuracy: 0.1,
      "A skipped LTR predecessor must establish its own edge before returning to RTL")
    motion.sample(at: 3.3); fraction = 1; view.present(at: 3.3)
    XCTAssertEqual(marker.frame.midX, try XCTUnwrap(view.measuredRect(for: 0)).minX, accuracy: 0.1)
  }

  func testCanonicalDirectionUsesFirstAndLastAliasSlotsIndependently() throws {
    let value = try rendering("אב XY", marked: "א")
    let map = try XCTUnwrap(value.compositionTextMap)
    let layout = PromptFieldTextLayout(fieldRuns: map.fieldRuns, aliases: [900: [0, 3]],
      width: 400, font: font)
    XCTAssertEqual(layout.canonicalDirection(900, after: false, perGlyph: true), true)
    XCTAssertEqual(layout.canonicalDirection(900, after: true, perGlyph: true), false)
    XCTAssertEqual(layout.canonicalRect(900, after: false), layout.cellFrames[0])
    XCTAssertEqual(layout.canonicalRect(900, after: true), layout.cellFrames[3])
    XCTAssertNil(layout.canonicalDirection(901, after: false, perGlyph: true),
      "A missing canonical target must not borrow another field's direction")
  }

  func testNativePaceAfterEdgesResolveEachCanonicalTargetsDirection() throws {
    let value = try rendering("אב XY", marked: "א")
    let view = PromptFieldNativeView(frame: .init(x: 0, y: 0, width: 400, height: 180))
    defer { view.stop() }
    let motion = PromptCaretMotionCoordinator()
    var configuration = config(motion, style: .off, pace: .bar)
    configuration.fieldDirectionPerGlyph = true
    var target = 0, sequence = 1.0
    configuration.latestRendering = { value }
    configuration.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: true, fraction: 1, sequence: sequence, targetGlyphID: target) }
    view.configure(rendering: value, font: font, carets: configuration)
    view.layout(); view.present(at: 0)
    let hebrew = try XCTUnwrap(view.measuredRect(for: 0))
    XCTAssertEqual(motion.pace.position, hebrew.offsetBy(dx: -hebrew.width, dy: 0))
    let caret = try XCTUnwrap(view.subviews.compactMap { $0 as? PromptCaretNativeView }.first)
    let marker = try XCTUnwrap(caret.subviews.compactMap { $0 as? NSHostingView<PromptCaretMarkerView> }.first)
    XCTAssertEqual(marker.frame.midX, hebrew.minX, accuracy: 0.1)
    target = 3; sequence = 2
    view.present(at: 0.1)
    let latin = try XCTUnwrap(view.measuredRect(for: 3))
    XCTAssertEqual(motion.pace.position, latin.offsetBy(dx: latin.width, dy: 0))
    XCTAssertEqual(marker.frame.midX, latin.maxX, accuracy: 0.1)
  }

  func testFieldMainCaretUsesResolvedMixedDirectionRatherThanOuterFlow() throws {
    let value = try rendering("אב cd", marked: "א")
    let map = try XCTUnwrap(value.compositionTextMap)
    let layout = PromptFieldTextLayout(map: map, width: 400, font: font)
    let anchor = try XCTUnwrap(map.caret)
    let own = try XCTUnwrap(layout.cellFrames[anchor.cellID])
    XCTAssertTrue(layout.mainDirection(perGlyph: false))
    XCTAssertEqual(PromptCaretPlacementPolicy.horizontalAnchor(
      for: try XCTUnwrap(layout.mainRect(style: .bar, perGlyph: false)), style: .bar,
      isRightToLeft: layout.mainDirection(perGlyph: false)), own.maxX,
      accuracy: 0.1)
  }

  func testPerGlyphMainDirectionDiffersFromMixedFieldDirection() throws {
    let value = try rendering("אבXYZ cd", accepted: "אב", marked: "X")
    let map = try XCTUnwrap(value.compositionTextMap)
    let layout = PromptFieldTextLayout(map: map, width: 400, font: font)
    XCTAssertTrue(layout.mainDirection(perGlyph: false))
    XCTAssertFalse(layout.mainDirection(perGlyph: true))
    let own = try XCTUnwrap(layout.cellFrames[try XCTUnwrap(map.caret).cellID])
    XCTAssertEqual(PromptCaretPlacementPolicy.horizontalAnchor(
      for: try XCTUnwrap(layout.mainRect(style: .bar, perGlyph: true)), style: .bar,
      isRightToLeft: layout.mainDirection(perGlyph: true)), own.minX,
      accuracy: 0.1)
  }

  func testNativeMainMarkerSwitchesEdgesWhenDirectionModeChanges() throws {
    let value = try rendering("אבXYZ cd", accepted: "אב", marked: "X")
    let map = try XCTUnwrap(value.compositionTextMap)
    let view = PromptFieldNativeView(frame: .init(x: 0, y: 0, width: 400, height: 180))
    defer { view.stop() }
    var configuration = config(PromptCaretMotionCoordinator())
    view.configure(rendering: value, font: font, carets: configuration)
    view.layout(); view.present(at: 0)
    let caret = try XCTUnwrap(view.subviews.compactMap { $0 as? PromptCaretNativeView }.first)
    let marker = try XCTUnwrap(caret.subviews.compactMap { $0 as? NSHostingView<PromptCaretMarkerView> }.first)
    let own = try XCTUnwrap(view.measuredRect(for: try XCTUnwrap(map.caret).cellID))
    XCTAssertEqual(marker.frame.midX, own.maxX, accuracy: 0.1)
    let revision = view.geometryRevision
    configuration.fieldDirectionPerGlyph = true
    view.configure(rendering: value, font: font, carets: configuration)
    view.present(at: 0.1)
    XCTAssertEqual(view.geometryRevision, revision, "Mode changes must not invent text geometry changes")
    XCTAssertEqual(marker.frame.midX, own.minX, accuracy: 0.1)
  }

  func testIndependentHebrewCellsUseRTLOrderWithinLTRFieldFlow() throws {
    let value = try rendering("אב cd", marked: "א")
    let map = try XCTUnwrap(value.compositionTextMap)
    let layout = PromptFieldTextLayout(map: map, width: 400, font: font)
    let ids = map.fieldRuns[0].cells.map(\.id)
    XCTAssertLessThan(try XCTUnwrap(layout.cellFrames[ids[1]]).minX,
      try XCTUnwrap(layout.cellFrames[ids[0]]).minX)
    XCTAssertLessThanOrEqual(try XCTUnwrap(layout.fieldFrames[0]).maxX,
      try XCTUnwrap(layout.fieldFrames[1]).minX)
  }

  func testIndependentLatinCellsStayLTRWithinRTLFieldFlow() throws {
    let value = try rendering("ab cd", marked: "a")
    let map = try XCTUnwrap(value.compositionTextMap)
    let layout = PromptFieldTextLayout(map: map, width: 400, font: font, rightToLeft: true)
    let ids = map.fieldRuns[0].cells.map(\.id)
    XCTAssertLessThan(try XCTUnwrap(layout.cellFrames[ids[0]]).minX,
      try XCTUnwrap(layout.cellFrames[ids[1]]).minX)
    XCTAssertLessThanOrEqual(try XCTUnwrap(layout.fieldFrames[1]).maxX,
      try XCTUnwrap(layout.fieldFrames[0]).minX)
  }

  func testMixedDigitsKeepLTRSequenceInsideIndependentRTLField() throws {
    let value = try rendering("אב12גד tail", marked: "א")
    let map = try XCTUnwrap(value.compositionTextMap)
    let layout = PromptFieldTextLayout(map: map, width: 400, font: font)
    let ids = Array(map.fieldRuns[0].cells.filter { !$0.isGap }.map(\.id))
    let physical = try ids.sorted {
      try XCTUnwrap(layout.cellFrames[$0]).minX < XCTUnwrap(layout.cellFrames[$1]).minX
    }
    XCTAssertEqual(physical, [ids[5], ids[4], ids[2], ids[3], ids[1], ids[0]])
    for id in ids { XCTAssertEqual(layout.canonicalRect(id, after: false), layout.cellFrames[id]) }
  }

  func testIndependentRTLOrderingStaysWithinEachWrappedRow() throws {
    let value = try rendering("אבגדהוזח tail", marked: "א")
    let map = try XCTUnwrap(value.compositionTextMap)
    let layout = PromptFieldTextLayout(map: map, width: 65, font: font)
    let ids = map.fieldRuns[0].cells.filter { !$0.isGap }.map(\.id)
    let rows = try Dictionary(grouping: ids) { try XCTUnwrap(layout.cellFrames[$0]).minY }
    XCTAssertGreaterThan(rows.count, 1, "The case must actually wrap")
    for row in rows.values {
      for (first, next) in zip(row, row.dropFirst()) {
        XCTAssertLessThan(try XCTUnwrap(layout.cellFrames[next]).minX,
          try XCTUnwrap(layout.cellFrames[first]).minX)
      }
    }
    XCTAssertEqual(layout.cellFrames.count, map.cellTexts.count)
  }

  private func rendering(_ words: String, accepted: String = "", marked: String = "") throws -> PromptRendering {
    var session = TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces]), customText: words)
    if !accepted.isEmpty { session.insertBatch(accepted, at: start) }
    return try render(session, marked: marked)
  }

  private func render(_ session: TypingSession, marked: String = "", hints: Bool = false,
    style: CompositionDisplayStyle = .replace) throws -> PromptRendering {
    let value = try XCTUnwrap(PromptCompositionPresentation(session: session, composition: marked, style: style))
    return value.render { index, glyph, cell in
      let plan = PromptControlCharacterPresentation.plan(for: glyph, style: .both,
        isZen: value.isZen, compositionReplacement: cell?.text,
        isEmptyWordPlaceholder: index == value.emptyPlaceholderIndex)
      var text = AttributedString(plan.text)
      text.foregroundColor = glyph.state == .correct ? .green : .orange
      if plan.opacity != 1 { text.foregroundColor = text.foregroundColor?.opacity(plan.opacity) }
      if cell != nil { text.underlineStyle = Text.LineStyle(color: .gray) }
      if hints, glyph.state == .incorrect {
        var hint = AttributedString("原"); hint.baselineOffset = -12; hint.foregroundColor = .red
        text += hint
      }
      return text
    }
  }

  private func frame(_ id: Int, in rendering: PromptRendering) throws -> CGRect {
    let layout = PromptFieldTextLayout(map: try XCTUnwrap(rendering.compositionTextMap), width: 400, font: font)
    return try XCTUnwrap(layout.cellFrames[id])
  }

  func testCancelledCombiningFieldStartsAfterTheAcceptedFieldRatherThanInsideItsGlyph() throws {
    let result = try rendering("a \u{301}b tail", accepted: "a")
    let ids = try XCTUnwrap(result.compositionTextMap?.canonicalAliases[0])
    XCTAssertEqual(ids.count, 2)
    let preceding = try frame(ids[0], in: result), next = try frame(ids[1], in: result)
    XCTAssertGreaterThanOrEqual(next.minX, preceding.maxX - 0.1)
  }

  func testRegionalIndicatorsInDifferentFieldsCannotShareAFlagBox() throws {
    let result = try rendering("🇺 🇸x tail")
    let ids = try XCTUnwrap(result.compositionTextMap?.canonicalAliases[0])
    XCTAssertEqual(ids.count, 2)
    let first = try frame(ids[0], in: result), next = try frame(ids[1], in: result)
    XCTAssertGreaterThanOrEqual(next.minX, first.maxX - 0.1)
  }

  private func config(_ motion: PromptCaretMotionCoordinator, attempt: UUID = UUID(),
    rightToLeft: Bool = false, style: TypingCaretStyle = .bar, pace: TypingCaretStyle = .off) -> PromptCaretNativeView.Configuration {
    .init(text: AttributedString(), mainOffset: nil, paceOffset: nil, mainStyle: style, paceStyle: pace,
      font: font, lineSpacing: 12, rightToLeft: rightToLeft, accent: .blue, motion: .off,
      reducesMotion: true, frameRate: 30, attemptID: attempt, coordinator: motion, automaticallyPresents: false)
  }

  func testCommitSpaceBeforeWrappedWordFollowsThatWordsActualRow() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd")
    session.insertBatch("ab", at: start)
    let result = try render(session), map = try XCTUnwrap(result.compositionTextMap)
    let layout = PromptFieldTextLayout(map: map, width: 45, font: font)
    let main = try XCTUnwrap(layout.mainRect(style: .bar)), next = try XCTUnwrap(layout.cellFrames[3])
    XCTAssertGreaterThan(next.minY, try XCTUnwrap(layout.cellFrames[0]).minY)
    XCTAssertEqual(main, next)
  }

  func testCachedNativeLayoutMustNoticeCanonicalAliasChangesWithIdenticalFieldText() throws {
    var result = try render(TypingSession(configuration: .words(2), prompt: "ab cd"))
    let map = try XCTUnwrap(result.compositionTextMap), motion = PromptCaretMotionCoordinator()
    let view = PromptFieldNativeView(frame: .init(x: 0, y: 0, width: 400, height: 180))
    var configuration = config(motion, style: .off, pace: .bar), target = 1, sequence = 1.0
    configuration.latestRendering = { result }
    configuration.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 1, sequence: sequence, targetGlyphID: target) }
    view.configure(rendering: result, font: font, carets: configuration); view.layout(); view.present(at: 0)
    XCTAssertEqual(motion.pace.position, view.measuredRect(for: 1))
    result.compositionTextMap = .init(text: result.text, cellRanges: map.cellRanges, inkRanges: map.inkRanges,
      cellTexts: map.cellTexts, canonicalAliases: [900: [0]], fieldUnits: [:], caret: map.caret, fieldRuns: map.fieldRuns)
    target = 900; sequence = 2
    view.configure(rendering: result, font: font, carets: configuration); view.present(at: 0.1)
    XCTAssertEqual(motion.pace.position, view.measuredRect(for: 0))
    view.stop()
  }

  func testPaceFirstTweenBeginsAtTheFirstActualRetainedSlot() throws {
    let result = try render(TypingSession(configuration: .words(2), prompt: "ab cd"))
    let motion = PromptCaretMotionCoordinator(), view = PromptFieldNativeView(frame: .init(x: 0, y: 0, width: 400, height: 180))
    var configuration = PromptCaretNativeView.Configuration(text: AttributedString(), mainOffset: nil, paceOffset: nil,
      mainStyle: .off, paceStyle: .bar, font: font, lineSpacing: 12, rightToLeft: false, accent: .blue,
      motion: .off, reducesMotion: false, frameRate: 30, attemptID: UUID(), coordinator: motion, automaticallyPresents: false)
    configuration.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 0, stepDuration: 1, sequence: 1, targetGlyphID: 4) }
    view.configure(rendering: result, font: font, carets: configuration); view.layout(); view.present(at: 0)
    XCTAssertEqual(motion.pace.position, view.measuredRect(for: 0))
    motion.sample(at: 0.5)
    XCTAssertGreaterThan(try XCTUnwrap(motion.pace.position).minX, try XCTUnwrap(view.measuredRect(for: 0)).minX)
    XCTAssertLessThan(try XCTUnwrap(motion.pace.position).minX, try XCTUnwrap(view.measuredRect(for: 4)).minX)
    view.stop()
  }

  func testFreshCandidateReflowMovesAnUnchangedPaceTargetInTheSamePresentation() throws {
    let session = TypingSession(configuration: .words(2), prompt: "ab cd")
    var result = try render(session), marked = ""
    let motion = PromptCaretMotionCoordinator(), view = PromptFieldNativeView(frame: .init(x: 0, y: 0, width: 400, height: 180))
    var configuration = config(motion, pace: .bar)
    let attempt = configuration.attemptID
    configuration.latestInput = { .init(attemptID: attempt, typed: "", composition: marked, glyphID: nil) }
    configuration.latestRendering = { result }
    configuration.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 1, sequence: 1, targetGlyphID: 3) }
    view.configure(rendering: result, font: font, carets: configuration); view.layout(); view.present(at: 0)
    let before = try XCTUnwrap(motion.pace.position)
    marked = "XYZ"; result = try render(session, marked: marked)
    view.present(at: 0.1) // Same frame sequence, no SwiftUI/configuration update.
    XCTAssertEqual(motion.pace.position, view.measuredRect(for: 3))
    XCTAssertGreaterThan(try XCTUnwrap(motion.pace.position).minX, before.minX)
    view.stop()
  }

  func testViewportCountUpdateReportsNewHeightWithoutRebuildingText() throws {
    let result = try render(TypingSession(configuration: .words(2), prompt: "ab cd"))
    let motion = PromptCaretMotionCoordinator(), view = PromptFieldNativeView(frame: .init(x: 0, y: 0, width: 400, height: 180))
    let configuration = config(motion)
    var heights: [CGFloat] = []
    view.configure(rendering: result, font: font, carets: configuration, viewportLineCount: 3,
      onViewportHeight: { if let value = $0 { heights.append(value) } })
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    XCTAssertEqual(heights.count, 1)
    view.configure(rendering: result, font: font, carets: configuration, viewportLineCount: 2,
      onViewportHeight: { if let value = $0 { heights.append(value) } })
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    XCTAssertEqual(heights.count, 2)
    if heights.count == 2 { XCTAssertEqual(heights[0] / 3, heights[1] / 2, accuracy: 1) }
    view.stop()
  }

  func testHintsAreDrawnWithoutChangingSlotOrFieldAdvance() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd"); session.insert("X", at: start)
    let plain = try render(session), hinted = try render(session, hints: true)
    let first = PromptFieldTextLayout(map: try XCTUnwrap(plain.compositionTextMap), width: 400, font: font)
    let second = PromptFieldTextLayout(map: try XCTUnwrap(hinted.compositionTextMap), width: 400, font: font)
    XCTAssertEqual(first.cellFrames, second.cellFrames)
    XCTAssertEqual(first.fieldFrames, second.fieldFrames)
    XCTAssertGreaterThan(hinted.text.characters.count, plain.text.characters.count)
  }

  func testFinalRowHintInkFitsInsideTheMeasuredNativeContentHeight() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd"); session.insert("X", at: start)
    let result = try render(session, hints: true)
    let layout = PromptFieldTextLayout(map: try XCTUnwrap(result.compositionTextMap), width: 400, font: font)
    let ink = try XCTUnwrap(layout.cellFrames[0])
    XCTAssertGreaterThanOrEqual(layout.size.height, ink.maxY + max(9, font.pointSize * 0.48) * 1.4)
  }

  func testWholeFieldMovesToFreshRowAndOversizedFieldKeepsItsFullAllocation() throws {
    let ordinary = try render(TypingSession(configuration: .words(3), prompt: "aa bbbb cc"))
    let whole = PromptFieldTextLayout(map: try XCTUnwrap(ordinary.compositionTextMap), width: 130, font: font)
    XCTAssertGreaterThan(try XCTUnwrap(whole.cellFrames[3]).minY, try XCTUnwrap(whole.cellFrames[0]).minY)
    for id in 3...6 { XCTAssertEqual(whole.cellFrames[id]?.minY, whole.cellFrames[3]?.minY) }
    let oversized = try render(TypingSession(configuration: .words(2), prompt: "aaaaaaa b"))
    let wrapped = PromptFieldTextLayout(map: try XCTUnwrap(oversized.compositionTextMap), width: 65, font: font)
    XCTAssertGreaterThan(try XCTUnwrap(wrapped.cellFrames[6]).minY, try XCTUnwrap(wrapped.cellFrames[0]).minY)
    XCTAssertGreaterThan(try XCTUnwrap(wrapped.cellFrames[8]).minY, try XCTUnwrap(wrapped.cellFrames[6]).minY)
    XCTAssertEqual(wrapped.fieldFrames[0]?.maxY, wrapped.cellFrames[6]?.maxY)
  }

  func testJoiningScriptShapesWithinItsFieldButNeverAcrossFields() throws {
    let result = try render(TypingSession(configuration: .words(2, language: .arabic), prompt: "سلام عالم"))
    let map = try XCTUnwrap(result.compositionTextMap)
    let joined = PromptFieldTextLayout(map: map, width: 400, font: font, rightToLeft: true, joinsLetters: true)
    let separate = PromptFieldTextLayout(map: map, width: 400, font: font, rightToLeft: true)
    XCTAssertLessThan(try XCTUnwrap(joined.fieldFrames[0]).width, try XCTUnwrap(separate.fieldFrames[0]).width)
    XCTAssertLessThanOrEqual(try XCTUnwrap(joined.fieldFrames[1]).maxX, try XCTUnwrap(joined.fieldFrames[0]).minX)
    XCTAssertEqual(joined.cellFrames.count, map.cellTexts.count)
    let fused = try rendering("a \u{301}b tail", accepted: "a")
    let isolated = PromptFieldTextLayout(map: try XCTUnwrap(fused.compositionTextMap), width: 400, font: font, joinsLetters: true)
    XCTAssertGreaterThanOrEqual(try XCTUnwrap(isolated.fieldFrames[1]).minX, try XCTUnwrap(isolated.fieldFrames[0]).maxX)
  }

  func testArabicJoiningInLTRFieldFlowRetainsLigatureAndCanonicalSlots() throws {
    let result = try render(TypingSession(configuration: .words(3), prompt: "ab سلام cd"), marked: "中文")
    let map = try XCTUnwrap(result.compositionTextMap)
    let joined = PromptFieldTextLayout(map: map, width: 400, font: font, joinsLetters: true)
    let isolated = PromptFieldTextLayout(map: map, width: 400, font: font)
    XCTAssertLessThan(try XCTUnwrap(joined.fieldFrames[1]).width,
      try XCTUnwrap(isolated.fieldFrames[1]).width)
    XCTAssertGreaterThan(try XCTUnwrap(joined.cellFrames[3]).minX,
      try XCTUnwrap(joined.cellFrames[6]).minX)
    XCTAssertEqual(joined.cellFrames[4], joined.cellFrames[5],
      "Lam and alef retain separate source slots but share the shaped ligature's geometry")
    for id in 3...6 {
      XCTAssertEqual(joined.canonicalRect(id, after: false), joined.cellFrames[id])
      XCTAssertEqual(joined.canonicalDirection(id, after: false, perGlyph: true), true)
    }
    XCTAssertLessThanOrEqual(try XCTUnwrap(joined.fieldFrames[0]).maxX,
      try XCTUnwrap(joined.fieldFrames[1]).minX)
    XCTAssertLessThanOrEqual(try XCTUnwrap(joined.fieldFrames[1]).maxX,
      try XCTUnwrap(joined.fieldFrames[2]).minX)
  }

  func testWrappedOppositeJoiningCandidatesReuseAndCancelWithoutStaleSlots() throws {
    try checkWrappedOppositeJoiningCandidates(language: .bangla, word: "বাংলা")
  }

  func testWrappedHindiCandidatesReuseAndCancelWithoutStaleSlots() throws {
    for language in [TypingLanguage.hindi, .hindi1k] {
      try checkWrappedOppositeJoiningCandidates(language: language, word: "किरण")
    }
  }

  func testWrappedTamilCandidatesReuseAndCancelWithoutStaleSlots() throws {
    for language in [TypingLanguage.tamil, .tamil1k, .tamilOld] {
      try checkWrappedOppositeJoiningCandidates(language: language, word: "கொடி")
    }
  }

  func testWrappedGujaratiCandidatesReuseAndCancelWithoutStaleSlots() throws {
    for language in [TypingLanguage.gujarati, .gujarati1k] {
      try checkWrappedOppositeJoiningCandidates(language: language, word: "કિરણ")
    }
  }

  func testWrappedNepaliAndSanskritCandidatesReuseAndCancelWithoutStaleSlots() throws {
    for language in [TypingLanguage.nepali, .nepali1k, .sanskrit] {
      try checkWrappedOppositeJoiningCandidates(language: language, word: "किरण")
    }
  }

  func testWrappedKannadaCandidatesReuseAndCancelWithoutStaleSlots() throws {
    try checkWrappedOppositeJoiningCandidates(language: .kannada, word: "ಕಿರಣ")
  }

  func testWrappedKhmerCandidatesReuseAndCancelWithoutStaleSlots() throws {
    try checkWrappedOppositeJoiningCandidates(language: .khmer, word: "ខ្មែរ")
  }

  func testWrappedKoreanCandidatesReuseAndCancelWithoutStaleSlots() throws {
    for language in [TypingLanguage.korean, .korean1k, .korean5k] {
      try checkWrappedOppositeJoiningCandidates(language: language, word: "한글")
    }
  }

  func testWrappedMalayalamCandidatesReuseAndCancelWithoutStaleSlots() throws {
    try checkWrappedOppositeJoiningCandidates(language: .malayalam, word: "കിരണം")
  }

  func testWrappedSinhalaCandidatesReuseAndCancelWithoutStaleSlots() throws {
    try checkWrappedOppositeJoiningCandidates(language: .sinhala, word: "කිරණ")
  }

  func testWrappedTeluguCandidatesReuseAndCancelWithoutStaleSlots() throws {
    for language in [TypingLanguage.telugu, .telugu1k] {
      try checkWrappedOppositeJoiningCandidates(language: language, word: "కిరణం")
    }
  }

  func testWrappedTibetanCandidatesReuseAndCancelWithoutStaleSlots() throws {
    for language in [TypingLanguage.tibetan, .tibetan1k] {
      try checkWrappedOppositeJoiningCandidates(language: language, word: "བོད་སྐད་")
    }
  }

  func testWrappedMyanmarBurmeseCandidatesReuseAndCancelWithoutStaleSlots() throws {
    try checkWrappedOppositeJoiningCandidates(language: .myanmarBurmese, word: "မြန်မာ")
  }

  private func checkWrappedOppositeJoiningCandidates(language: TypingLanguage, word indicWord: String) throws {
    let configuration = TestConfiguration.words(4, language: .mixedLanguages,
      mixedLanguageComponents: [.english, .arabic, language])
    for (accepted, word, owner, rtl) in [
      ("ab ", "سلام", 1, true), ("ab سلام ", indicWord, 2, false)
    ] {
      var session = TypingSession(configuration: configuration, prompt: "ab سلام \(indicWord) cd")
      session.insertBatch(accepted, at: start)
      for style in CompositionDisplayStyle.allCases {
        for testedFont in [font, NSFont.systemFont(ofSize: 28, weight: .regular)] {
          let initialMap = try XCTUnwrap(render(session, style: style).compositionTextMap)
          let initial = PromptFieldTextLayout(map: initialMap, width: 90, font: testedFont, joinsLetters: true)
          var previous = initial
          for marked in [String(repeating: word, count: 12), word, ""] {
            let map = try XCTUnwrap(render(session, marked: marked, style: style).compositionTextMap)
            let reused = PromptFieldTextLayout(map: map, width: 90, font: testedFont,
              joinsLetters: true, reusing: previous)
            let fresh = PromptFieldTextLayout(map: map, width: 90, font: testedFont, joinsLetters: true)
            XCTAssertEqual(reused.cellFrames, fresh.cellFrames)
            XCTAssertEqual(reused.fieldFrames, fresh.fieldFrames)
            XCTAssertEqual(reused.size, fresh.size)
            XCTAssertEqual(reused.cellFrames.count, map.cellTexts.count,
              "Every current slot must have geometry, including wrapped candidate extras")
            let active = try XCTUnwrap(map.fieldRuns.first { $0.fieldID == owner })
            let rows = try Set(active.cells.filter { !$0.isGap }.map {
              try XCTUnwrap(reused.cellFrames[$0.id]).minY
            })
            if marked.count > word.count {
              XCTAssertGreaterThan(rows.count, 1, "The long candidate must actually wrap")
              let following = try XCTUnwrap(reused.fieldFrames[owner + 1])
              XCTAssertGreaterThanOrEqual(following.minY,
                try XCTUnwrap(reused.fieldFrames[owner]).maxY,
                "The following word must not overlap a multi-row candidate")
            }
            for id in map.canonicalAliases.keys {
              for after in [false, true] {
                XCTAssertEqual(reused.canonicalRect(id, after: after), fresh.canonicalRect(id, after: after))
                XCTAssertEqual(reused.canonicalDirection(id, after: after, perGlyph: true),
                  fresh.canonicalDirection(id, after: after, perGlyph: true))
              }
            }
            XCTAssertEqual(reused.mainRect(style: .bar, perGlyph: false),
              fresh.mainRect(style: .bar, perGlyph: false))
            XCTAssertEqual(reused.mainDirection(perGlyph: false), rtl)
            if marked.isEmpty {
              XCTAssertEqual(map.canonicalAliases, initialMap.canonicalAliases)
              XCTAssertEqual(reused.cellFrames, initial.cellFrames,
                "Cancellation must restore original slots rather than retain expanded candidate geometry")
              XCTAssertEqual(reused.fieldFrames, initial.fieldFrames)
            }
            previous = reused
          }
        }
      }
    }
  }

  func testNativeFreshCandidateCancellationUpdatesFieldCaretWithoutAConfigurationUpdate() throws {
    var result = try rendering("a \u{301}b tail", accepted: "a", marked: "XY"), marked = "XY", reads = 0
    let motion = PromptCaretMotionCoordinator(), view = PromptFieldNativeView(frame: .init(x: 0, y: 0, width: 400, height: 180))
    var configuration = config(motion)
    let attempt = configuration.attemptID
    configuration.latestInput = { .init(attemptID: attempt, typed: "a", composition: marked, glyphID: nil) }
    configuration.latestRendering = { reads += 1; return result }
    view.configure(rendering: result, font: font, carets: configuration); view.layout(); view.present(at: 0)
    let revision = view.geometryRevision
    for index in 1...5 { view.present(at: Double(index) / 1000) }
    XCTAssertEqual(reads, 1); XCTAssertEqual(view.geometryRevision, revision)
    marked = ""; result = try rendering("a \u{301}b tail", accepted: "a")
    view.present(at: 0.1)
    let anchor = try XCTUnwrap(result.compositionTextMap?.caret), own = try XCTUnwrap(view.measuredRect(for: anchor.cellID))
    XCTAssertEqual(reads, 2); XCTAssertGreaterThan(view.geometryRevision, revision)
    XCTAssertEqual(motion.main.position, own)
    XCTAssertGreaterThanOrEqual(own.minX, try XCTUnwrap(view.measuredFieldRect(for: 0)).maxX - 0.1)
    view.stop()
  }

  func testNativeRTLOverflowBlockIsAfterItsOwnSlotNotInsideTheNextField() throws {
    var session = TypingSession(configuration: .words(2, language: .hebrew), prompt: "אב גד")
    session.insert("א", at: start)
    let result = try render(session, marked: "בXYZ"), motion = PromptCaretMotionCoordinator()
    let map = try XCTUnwrap(result.compositionTextMap), anchor = try XCTUnwrap(map.caret)
    let view = PromptFieldNativeView(frame: .init(x: 0, y: 0, width: 400, height: 180))
    var configuration = config(motion, rightToLeft: true, style: .block)
    configuration.latestRendering = { result }
    view.configure(rendering: result, font: font, rightToLeft: true, carets: configuration)
    view.layout(); view.present(at: 0)
    XCTAssertTrue(anchor.after)
    let own = try XCTUnwrap(view.measuredRect(for: anchor.cellID)), main = try XCTUnwrap(motion.main.position)
    XCTAssertEqual(main.minX, own.minX - (" " as NSString).size(withAttributes: [.font: font]).width, accuracy: 0.1)
    XCTAssertGreaterThanOrEqual(main.minX, try XCTUnwrap(view.measuredFieldRect(for: 1)).maxX)
    view.stop()
  }

  func testRemovedFieldRetainsTwoStructuralRowsWithoutAnyRemovedGlyphBox() throws {
    var session = TypingSession(configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(freedomMode: true), modifiers: [.noSpaces]),
      prompt: "ba\n\ncd", noSpaceWordEndIndices: [1, 4, 6], noSpaceTargetWords: ["b", "a\n\n", "cd"])
    session.removeTapePromptWords(.init(attemptID: session.automaticInputAttemptID, wordIndices: [1]))
    let result = try render(session, marked: "X"), map = try XCTUnwrap(result.compositionTextMap)
    let layout = PromptFieldTextLayout(map: map, width: 400, font: font)
    XCTAssertNil(layout.fieldFrames[1])
    let first = try XCTUnwrap(layout.fieldFrames[0]), next = try XCTUnwrap(layout.fieldFrames[2])
    XCTAssertEqual(next.minY - first.minY, (first.height + 12) * 2, accuracy: 0.1)
    XCTAssertTrue(map.fieldRuns.contains { $0.fieldID == 1 && $0.removedReturns == 2 && $0.cells.isEmpty })
  }

  func testZenHiddenReturnKeepsItsRowAndCancellationPlaceholder() throws {
    var session = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "")
    session.insertBatch("a\n", at: start)
    let result = try render(session), map = try XCTUnwrap(result.compositionTextMap)
    let layout = PromptFieldTextLayout(map: map, width: 400, font: font)
    let placeholder = try XCTUnwrap(result.emptyWordPlaceholderGlyphID)
    XCTAssertGreaterThan(try XCTUnwrap(layout.cellFrames[placeholder]).minY, try XCTUnwrap(layout.cellFrames[0]).minY)
    XCTAssertEqual(layout.mainRect(style: .bar), layout.cellFrames[placeholder])
    XCTAssertEqual(map.fieldRuns.flatMap(\.cells).first(where: { $0.glyph.character == "\n" })?.text.foregroundColor,
      Color.green.opacity(0))
  }

  func testReturnContainerBreaksAfterItsExtrasRatherThanImmediatelyAfterTheIcon() throws {
    var session = TypingSession(configuration: .words(2), prompt: "aa\nbb")
    session.insertBatch("aaxy", at: start)
    let result = try render(session), map = try XCTUnwrap(result.compositionTextMap)
    let cells = try XCTUnwrap(map.fieldRuns.first { $0.fieldID == 0 }).cells
    XCTAssertEqual(cells.map(\.glyph.character), ["a", "a", "\n", "y"])
    for rtl in [false, true] {
      for joins in [false, true] {
        let layout = PromptFieldTextLayout(map: map, width: 400, font: font, rightToLeft: rtl, joinsLetters: joins)
        let first = try XCTUnwrap(layout.cellFrames[cells[0].id])
        for cell in cells { XCTAssertEqual(layout.cellFrames[cell.id]?.minY, first.minY) }
        XCTAssertGreaterThan(try XCTUnwrap(layout.fieldFrames[1]).minY, try XCTUnwrap(layout.fieldFrames[0]).maxY)
      }
    }
  }

  func testReturnProjectionKeepsTrueExtrasAndCommittedHistory() throws {
    for accepted in ["aaxy", "aaxy ", "aa\nb"] {
      var session = TypingSession(configuration: .words(2), prompt: "aa\nbb")
      session.insertBatch(accepted, at: start)
      let before = session.typed
      let result = try render(session)
      let first = try XCTUnwrap(result.compositionTextMap?.fieldRuns.first { $0.fieldID == 0 })
      XCTAssertEqual(first.cells.map { $0.glyph.character }, accepted.hasPrefix("aaxy") ? ["a", "a", "\n", "y"] : ["a", "a", "\n"], accepted)
      XCTAssertEqual(session.typed, before)
      XCTAssertEqual(first.cells[2].glyph.state, accepted.hasPrefix("aaxy") ? .incorrect : .correct, accepted)
    }
  }

  func testWrongInputAtTheReturnTargetDoesNotAlsoBecomeAnExtraSlot() throws {
    var session = TypingSession(configuration: .words(2), prompt: "aa\nbb")
    session.insertBatch("aax", at: start)
    let field = try XCTUnwrap(session.promptCompositionField)
    XCTAssertEqual(field.targetUTF16, Array("aa\n".utf16))
    XCTAssertEqual(field.inputUTF16, Array("aax".utf16))
    // The pinned updateWordLetters iterates three input scalars here. Its
    // third letter is the incorrect Return target, not Return plus extra x.
    let cells = try XCTUnwrap(render(session).compositionTextMap?.fieldRuns.first { $0.fieldID == 0 }).cells
    XCTAssertEqual(cells.count, 3)
    let target = try XCTUnwrap(cells.first { $0.glyph.character == "\n" })
    XCTAssertEqual(target.glyph.state, .incorrect)
    XCTAssertEqual(target.glyph.typedCharacter, "x")
  }

  func testPendingViewportCallbackCannotFireAfterStopOrRetainTheView() throws {
    let result = try render(TypingSession(configuration: .words(2), prompt: "ab cd"))
    weak var released: PromptFieldNativeView?
    var notifications = 0
    autoreleasepool {
      let view = PromptFieldNativeView(frame: .init(x: 0, y: 0, width: 400, height: 180))
      released = view
      view.configure(rendering: result, font: font, carets: config(.init()), viewportLineCount: 3,
        onViewportHeight: { _ in notifications += 1 })
      view.stop()
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    XCTAssertNil(released); XCTAssertEqual(notifications, 0)
  }

  func testThousandSlotsHaveFiniteFramesAndUnchangedMeasurementsReuseTheCache() throws {
    let prompt = Array(repeating: "abcd", count: 250).joined(separator: " ")
    let result = try render(TypingSession(configuration: .words(250), prompt: prompt))
    let view = PromptFieldNativeView(frame: .init(x: 0, y: 0, width: 400, height: 180))
    let began = ProcessInfo.processInfo.systemUptime
    view.configure(rendering: result, font: font, carets: config(.init()))
    let first = view.measure(width: 400), revision = view.geometryRevision
    for _ in 0..<10 { XCTAssertEqual(view.measure(width: 400), first) }
    XCTAssertEqual(view.geometryRevision, revision)
    XCTAssertEqual(result.compositionTextMap?.cellTexts.count, 1249)
    XCTAssertNotNil(view.measuredRect(for: 1248)); XCTAssertTrue(first.height.isFinite)
    print("field layout 1249 slots plus ten cached measurements: \(ProcessInfo.processInfo.systemUptime - began)s (not full UI/device FPS)")
    let next = try render(TypingSession(configuration: .words(250), prompt: prompt), marked: "候")
    let hot = ProcessInfo.processInfo.systemUptime
    view.configure(rendering: next, font: font, carets: config(.init()))
    print("field layout changed candidate with retained boxes: \(ProcessInfo.processInfo.systemUptime - hot)s (native configure only)")
    let fresh = PromptFieldTextLayout(map: try XCTUnwrap(next.compositionTextMap), width: 400, font: font)
    for (id, rect) in fresh.cellFrames { XCTAssertEqual(view.measuredRect(for: id), rect) }
    view.stop()
  }

  func testReuseRepositionsRetainedFieldsWithoutMutatingThePreviousSnapshot() throws {
    var session = TypingSession(configuration: .words(3), prompt: "ab cd ef")
    session.insertBatch("ab cd ", at: start)
    let before = try render(session), first = PromptFieldTextLayout(map: try XCTUnwrap(before.compositionTextMap), width: 400, font: font)
    let firstFrames = first.cellFrames
    session.retirePromptWords(.init(attemptID: session.automaticInputAttemptID, firstRetainedWordIndex: 1))
    let after = try render(session), map = try XCTUnwrap(after.compositionTextMap)
    let reused = PromptFieldTextLayout(map: map, width: 400, font: font, reusing: first)
    let fresh = PromptFieldTextLayout(map: map, width: 400, font: font)
    XCTAssertEqual(reused.cellFrames, fresh.cellFrames); XCTAssertEqual(reused.fieldFrames, fresh.fieldFrames)
    XCTAssertEqual(first.cellFrames, firstFrames); XCTAssertNil(reused.fieldFrames[0])
    for width: CGFloat in [60, 200] {
      let changed = PromptFieldTextLayout(map: map, width: width, font: font, rightToLeft: true, reusing: reused)
      let isolated = PromptFieldTextLayout(map: map, width: width, font: font, rightToLeft: true)
      XCTAssertEqual(changed.cellFrames, isolated.cellFrames)
    }
  }

  func testStoppedNativeOwnerCannotRunQueuedFieldRetirement() throws {
    let prompt = (0..<12).map { "word\($0)" }.joined(separator: " ")
    var session = TypingSession(configuration: .words(12), prompt: prompt)
    session.insertBatch((0..<10).map { "word\($0) " }.joined(), at: start)
    let result = try render(session), map = try XCTUnwrap(result.compositionTextMap), motion = PromptCaretMotionCoordinator()
    let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 130, height: 90))
    let view = PromptFieldNativeView(frame: .init(x: 0, y: 0, width: 130, height: 700))
    scroll.documentView = view
    var retired: [PromptWordRetirement] = []
    let context = PromptLineScrollContext(attemptID: session.automaticInputAttemptID,
      activeWordID: session.promptCompositionField?.index, characterOffsets: map.fieldCharacterOffsets,
      smoothScroll: false, reducesMotion: true, words: (0..<12).map { .init(index: $0, glyphID: $0) },
      onRetire: { retired.append($0) }, caretMotion: motion)
    view.configure(rendering: result, font: font, carets: config(motion, attempt: session.automaticInputAttemptID), lineScroll: context)
    view.stop()
    RunLoop.main.run(until: Date().addingTimeInterval(0.03))
    XCTAssertTrue(retired.isEmpty)
    scroll.documentView = nil
  }

  private func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
    (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
  }
  private func capture(_ result: PromptRendering, name: String, width: CGFloat = 400,
    rightToLeft: Bool = false, joinsLetters: Bool = false) throws {
    let motion = PromptCaretMotionCoordinator()
    let configuration = config(motion, rightToLeft: rightToLeft)
    let root = PromptFieldPracticePrompt(rendering: result, font: font, lineSpacing: 12,
      rightToLeft: rightToLeft, joinsLetters: joinsLetters, carets: configuration)
      .frame(width: width, alignment: .leading).frame(height: 180, alignment: .topLeading).background(Color.white)
    let host = NSHostingView(rootView: root)
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: 180),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    window.contentView = host; host.frame = .init(x: 0, y: 0, width: width, height: 180)
    defer { window.contentView = nil; window.close() }
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.03)); host.layoutSubtreeIfNeeded()
    let view = try XCTUnwrap(descendants(host, PromptFieldNativeView.self).first)
    view.present(at: 0); host.displayIfNeeded()
    XCTAssertFalse(window.isVisible); XCTAssertNotNil(motion.main.position)
    if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
        to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }
    view.stop()
  }

  func testMountedProductionFieldComponentCapturesIndependentInkAndRealCaret() throws {
    try capture(rendering("a \u{301}b tail", accepted: "a"), name: "composition-fields-fused-cancellation")
    try capture(rendering("🇺 🇸x tail"), name: "composition-fields-regional-boundaries")
    var session = TypingSession(configuration: .words(2), prompt: "abcdef gh"); session.insert("X", at: start)
    try capture(render(session, marked: "bc候", hints: true), name: "composition-fields-slots-hint")
    try capture(render(TypingSession(configuration: .words(2), prompt: "aaaaaaa b")), name: "composition-fields-wrapped", width: 65)
    try capture(render(TypingSession(configuration: .words(2, language: .arabic), prompt: "سلام عالم")),
      name: "composition-fields-joining-rtl", rightToLeft: true, joinsLetters: true)
  }

  func testProductionUsesFieldComponentAndMeasuredCustomViewportRows() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(source.contains("PromptFieldPracticePrompt(rendering: rendering"))
    XCTAssertTrue(source.contains("measuresCustomRows: practiceVisualEffect.usesASL"))
    XCTAssertTrue(source.contains("|| rendering.compositionTextMap != nil"),
      "Ordinary and Choo projected fields provide their own measured row heights")
    XCTAssertTrue(source.contains("joinsLetters: usesJoiningScript"))
  }
}
