import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptFieldLayoutTests: XCTestCase {
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
  private let start = Date(timeIntervalSinceReferenceDate: 916_200_000)

  private func rendering(_ words: String, accepted: String = "", marked: String = "") throws -> PromptRendering {
    var session = TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces]), customText: words)
    if !accepted.isEmpty { session.insertBatch(accepted, at: start) }
    return try render(session, marked: marked)
  }

  private func render(_ session: TypingSession, marked: String = "", hints: Bool = false) throws -> PromptRendering {
    let value = try XCTUnwrap(PromptCompositionPresentation(session: session, composition: marked, style: .replace))
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
    XCTAssertTrue(source.contains("measuresCustomRows: practiceVisualEffect.usesASL || renderedPrompt.compositionTextMap != nil"))
    XCTAssertTrue(source.contains("joinsLetters: usesJoiningScript"))
  }
}
