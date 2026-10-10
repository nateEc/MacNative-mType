import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptCompositionRenderingTests: XCTestCase {
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
  private let start = Date(timeIntervalSinceReferenceDate: 916_100_000)

  private func presentation(_ session: TypingSession, _ marked: String,
    style: CompositionDisplayStyle = .replace) throws -> PromptCompositionPresentation {
    try XCTUnwrap(PromptCompositionPresentation(session: session, composition: marked, style: style))
  }

  private func render(_ presentation: PromptCompositionPresentation) -> PromptRendering {
    presentation.render { index, glyph, marked in
      let plan = PromptControlCharacterPresentation.plan(for: glyph, style: .both,
        isZen: presentation.isZen, isEmptyWordPlaceholder: index == presentation.emptyPlaceholderIndex)
      var text = AttributedString(marked.map { presentation.markedText(for: $0, glyph: glyph) }
        ?? plan.text)
      text.foregroundColor = glyph.state == .correct ? .green : .orange
      if marked == nil, plan.opacity != 1 { text.foregroundColor = text.foregroundColor?.opacity(plan.opacity) }
      if marked != nil { text.underlineStyle = Text.LineStyle(color: .gray) }
      if marked == nil, glyph.state == .incorrect {
        var hint = AttributedString("原"); hint.baselineOffset = -12; hint.foregroundColor = .red
        text += hint
      }
      return text
    }
  }

  func testIdenticalNativeFieldConfigurationDoesNotRequestAnotherLayout() throws {
    let session = TypingSession(configuration: .words(2), prompt: "abcdef gh")
    let result = render(try presentation(session, "中"))
    let view = PromptFieldNativeView(frame: .init(x: 0, y: 0, width: 400, height: 200))
    defer { view.stop() }
    let config = PromptCaretNativeView.Configuration(text: result.text, mainOffset: 0, paceOffset: nil,
      mainStyle: .bar, paceStyle: .off, font: font, lineSpacing: 12, rightToLeft: false,
      accent: .yellow, motion: .off, reducesMotion: true, frameRate: 30, attemptID: UUID(),
      coordinator: PromptCaretMotionCoordinator(), automaticallyPresents: false)
    view.configure(rendering: result, font: font, carets: config)
    view.layoutSubtreeIfNeeded()
    view.needsLayout = false
    let size = view.intrinsicContentSize, revision = view.geometryRevision
    view.configure(rendering: result, font: font, carets: config)
    XCTAssertFalse(view.needsLayout, "Unchanged intrinsic size must not invalidate parent layout")
    XCTAssertEqual(view.intrinsicContentSize, size)
    XCTAssertEqual(view.geometryRevision, revision)
    XCTAssertEqual(view.accessibilityValue() as? String, String(result.text.characters))
    func renderedPixels() throws -> Data {
      let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: bitmap)
      return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
    let originalPixels = try renderedPixels()
    let replacement = render(try presentation(session, "文"))
    view.configure(rendering: replacement, font: font, carets: config)
    XCTAssertEqual(view.intrinsicContentSize, size,
      "The counterexample must actually preserve measured size")
    XCTAssertFalse(view.needsLayout)
    XCTAssertGreaterThan(view.geometryRevision, revision,
      "Equal size must not suppress rebuilding changed content")
    XCTAssertEqual(view.accessibilityValue() as? String, String(replacement.text.characters))
    XCTAssertNotEqual(try renderedPixels(), originalPixels, "Changed content must still be redrawn")
    XCTAssertNotNil(view.measuredRect(for: try XCTUnwrap(replacement.compositionTextMap?.caret).cellID))
    view.configure(rendering: result, font: font.withSize(56), carets: config)
    XCTAssertTrue(view.needsLayout, "A changed measured size must still request layout")
    XCTAssertNotEqual(view.intrinsicContentSize, size)
  }

  func testFinalAttributesReplaceEverySlotAndPreserveAcceptedHints() throws {
    var session = TypingSession(configuration: .words(2), prompt: "abcdef gh")
    session.insert("X", at: start)
    let value = try presentation(session, "bc候"), result = render(value)
    XCTAssertEqual(String(result.text.characters), "X原bc候ef gh")
    let map = try XCTUnwrap(result.compositionTextMap)
    XCTAssertEqual(map.cellTexts[0].map { String($0.characters) }, "X原")
    XCTAssertEqual(map.cellRanges[1], NSRange(location: 2, length: 1))
    XCTAssertEqual(map.cellTexts[1]?.foregroundColor, .green)
    XCTAssertNotNil(map.cellTexts[3]?.underlineStyle)
    XCTAssertEqual(map.cellTexts[3]?.foregroundColor, .orange)
    XCTAssertEqual(session.typed, "X")
  }

  func testUTF16RangesStayDistinctWhenConcatenatedMarkedCellsFuseAgain() throws {
    let session = TypingSession(configuration: .words(2), prompt: "ab cd")
    // A leading combining mark joins the preceding target on concatenation.
    var active = session; active.insert("a", at: start)
    let value = try presentation(active, "\u{301}X"), result = render(value)
    let map = try XCTUnwrap(result.compositionTextMap)
    XCTAssertEqual(map.cellRanges[0], NSRange(location: 0, length: 1))
    XCTAssertEqual(map.cellRanges[1], NSRange(location: 1, length: 1))
    XCTAssertEqual(map.cellRanges[value.projection.markedCells[1].id], NSRange(location: 2, length: 1))
    XCTAssertEqual(map.cellTexts[1].map { String($0.characters) }, "\u{301}")
    XCTAssertEqual(String(result.text.characters).utf16.count, 6)
    XCTAssertLessThan(result.text.characters.count, 6)
  }

  func testOffBelowAndReplaceShareSlotIdentityWithoutCandidateHints() throws {
    let session = TypingSession(configuration: .words(2), prompt: "ab cd")
    for style in CompositionDisplayStyle.allCases {
      let value = try presentation(session, "XYZ", style: style), result = render(value)
      XCTAssertEqual(value.glyphs.count, 6)
      XCTAssertEqual(String(result.text.characters), style == .replace ? "XYZ cd" : "abZ cd")
      XCTAssertTrue(result.compositionTextMap?.cellTexts.values.allSatisfy {
        $0.runs.allSatisfy { ($0.baselineOffset ?? 0) >= 0 }
      } == true)
    }
  }

  func testFragmentPhaseDoesNotInheritTheAcceptedNeighborsCorrectState() throws {
    var session = TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces]),
      customText: "a \u{301}b tail")
    session.insert("a", at: start)
    let value = try presentation(session, "")
    XCTAssertEqual(value.glyphs.first?.state, .correct)
    XCTAssertEqual(value.glyphs[1].state, .pending)
    XCTAssertFalse(value.completedIndices.contains(1))
    XCTAssertEqual(value.words.map(\.phase), [.committed, .active, .future])
    XCTAssertEqual(render(value).compositionTextMap?.fieldCharacterOffsets[1], 0,
      "Text shaping may fuse fragments, but UTF-16 identities remain separate")
  }

  func testOverflowCaretMeasuresAfterItsOwnSlotRatherThanNextField() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd")
    session.insert("a", at: start)
    let result = render(try presentation(session, "bXYZ")), map = try XCTUnwrap(result.compositionTextMap)
    let anchor = try XCTUnwrap(map.caret), range = try XCTUnwrap(map.cellRanges[anchor.cellID])
    XCTAssertTrue(anchor.after)
    let rect = try XCTUnwrap(PromptCaretLayout.rect(in: result.text, utf16Range: range,
      containerSize: .init(width: 400, height: 200), font: font, lineSpacing: 12))
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 400, height: 200))
    var config = PromptCaretNativeView.Configuration(text: result.text, mainOffset: 0, paceOffset: nil,
      mainStyle: .bar, paceStyle: .off, font: font, lineSpacing: 12, rightToLeft: false,
      accent: .yellow, motion: .off, reducesMotion: true, frameRate: 30, attemptID: attempt,
      coordinator: motion, automaticallyPresents: false)
    config.latestRendering = { result }
    view.update(config); view.layout(); view.present(at: 0)
    XCTAssertEqual(try XCTUnwrap(motion.main.position).minX, rect.maxX, accuracy: 0.1)
    view.stop()
  }

  func testControlInkCannotInventExtraStructuralReturns() throws {
    let session = TypingSession(configuration: .words(3), prompt: "a\n\nb c")
    let result = render(try presentation(session, "X\nY"))
    XCTAssertEqual(String(result.text.characters).filter { $0 == "\n" }.count, 2)
    XCTAssertEqual(String(result.text.characters), "X \nY↵\nb c")
  }

  func testZenCandidateAndCancellationKeepAcceptedControlOpacityAndPlaceholder() throws {
    var session = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "")
    session.insertBatch("a\n", at: start)
    let marked = render(try presentation(session, "中文"))
    XCTAssertEqual(String(marked.text.characters), "a\n中文")
    XCTAssertEqual(marked.compositionTextMap?.cellTexts[1]?.foregroundColor, Color.green.opacity(0))
    let cancelled = render(try presentation(session, ""))
    XCTAssertEqual(String(cancelled.text.characters), "a\n_")
    XCTAssertNotNil(cancelled.compositionTextMap?.caret)
  }

  func testProductionNormalPromptUsesTheSharedPresentationAndLatestGeometry() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(source.contains("PromptCompositionPresentation(session: session"))
    XCTAssertTrue(source.contains("presentation.render(renderGlyph)"))
    XCTAssertTrue(source.contains("rendering.compositionTextMap?.fieldCharacterOffsets"))
    XCTAssertTrue(source.contains("rendering.mainCharacterOffset"))
  }

  func testStructuralReturnDoesNotExpandTheMainCaretIntoTheNextRow() throws {
    let session = TypingSession(configuration: .words(2), prompt: "\na")
    let result = render(try presentation(session, "X"))
    let expected = try XCTUnwrap(PromptCaretLayout.rect(in: result.text, utf16Range: .init(location: 0, length: 1),
      containerSize: .init(width: 400, height: 200), font: font, lineSpacing: 12))
    let beforeView = PromptCaretLayout.rect(in: result.text, utf16Range: .init(location: 0, length: 1),
      containerSize: .init(width: 400, height: 200), font: font, lineSpacing: 12)
    XCTAssertEqual(beforeView, expected)
    let motion = PromptCaretMotionCoordinator(), view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 400, height: 200))
    var config = PromptCaretNativeView.Configuration(text: result.text, mainOffset: 0, paceOffset: nil,
      mainStyle: .bar, paceStyle: .off, font: font, lineSpacing: 12, rightToLeft: false,
      accent: .yellow, motion: .off, reducesMotion: true, frameRate: 30, attemptID: UUID(),
      coordinator: motion, automaticallyPresents: false)
    config.latestRendering = { result }
    view.update(config); view.layout(); view.present(at: 0)
    XCTAssertEqual(try XCTUnwrap(motion.main.position).height, expected.height, accuracy: 0.1)
    XCTAssertEqual(try XCTUnwrap(motion.main.position).minX, expected.maxX, accuracy: 0.1)
    view.stop()
  }

  func testAcceptedHintIsNotPartOfTheCanonicalPaceGlyphBox() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd"); session.insert("X", at: start)
    let result = render(try presentation(session, "候"))
    XCTAssertEqual(result.compositionTextMap?.inkRanges[0], NSRange(location: 0, length: 1))
    XCTAssertEqual(result.compositionTextMap?.range(forCanonicalGlyph: 0), NSRange(location: 0, length: 1))
    let motion = PromptCaretMotionCoordinator(), view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 400, height: 200))
    var config = PromptCaretNativeView.Configuration(text: result.text, mainOffset: 0, paceOffset: nil,
      mainStyle: .off, paceStyle: .bar, font: font, lineSpacing: 12, rightToLeft: false,
      accent: .yellow, motion: .off, reducesMotion: true, frameRate: 30, attemptID: UUID(),
      coordinator: motion, automaticallyPresents: false)
    config.latestRendering = { result }
    config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil, fromAfter: false,
      targetAfter: false, fraction: 1, sequence: 1, targetGlyphID: 0) }
    view.update(config); view.layout(); view.present(at: 0)
    let ink = try XCTUnwrap(PromptCaretLayout.rect(in: result.text, utf16Range: .init(location: 0, length: 1),
      containerSize: view.bounds.size, font: config.font, lineSpacing: config.lineSpacing))
    let full = try XCTUnwrap(PromptCaretLayout.rect(in: result.text,
      utf16Range: try XCTUnwrap(result.compositionTextMap?.cellRanges[0]),
      containerSize: view.bounds.size, font: config.font, lineSpacing: config.lineSpacing))
    XCTAssertEqual(view.bounds.size, CGSize(width: 400, height: 200))
    XCTAssertEqual(config.font, font)
    XCTAssertGreaterThan(full.width, ink.width)
    XCTAssertEqual(motion.pace.position, ink)
    view.stop()
  }

  func testMarkedCellsPreserveMemoryConcealmentInsteadOfRevealingTargets() throws {
    var session = TypingSession(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.memory]), prompt: "ab cd")
    session.insert("a", at: start)
    let value = try presentation(session, "bXYZ")
    XCTAssertTrue(value.glyphs.allSatisfy { $0.state == .hidden })
  }

  func testFusedFieldWordErrorsUseTheirOwnUnitsAndRetainForcedErrors() throws {
    func attempt(forced: Bool) -> TypingSession {
      var session = TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
        difficulty: .normal, rules: .init(), modifiers: [.noSpaces]), customText: "a \u{301}b tail")
      session.insert("a", forceError: forced, at: start)
      return session
    }
    let correct = try presentation(attempt(forced: false), "X")
    XCTAssertFalse(correct.words[0].hasInputError)
    XCTAssertFalse(correct.words[0].hasCommitError)
    let forced = try presentation(attempt(forced: true), "X")
    XCTAssertTrue(forced.words[0].hasInputError)
    XCTAssertTrue(forced.words[0].hasCommitError)
    XCTAssertEqual(forced.glyphs[0].state, .incorrect)
  }

  func testCommitSpaceIsOutsideTheDenseWordAppearanceRange() throws {
    let value = try presentation(TypingSession(configuration: .words(2), prompt: "ab cd"), "XY")
    XCTAssertEqual(value.words[0].range, 0..<2)
    XCTAssertEqual(value.projection.cells[2].text, " ")
  }

  func testWrappedCommitSpaceKeepsTheExistingNextLineCaretPolicy() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd"); session.insertBatch("ab", at: start)
    let result = render(try presentation(session, "")), size = CGSize(width: 45, height: 200)
    let expected = try XCTUnwrap(PromptCaretLayout.rect(in: result.text, characterOffset: 2,
      containerSize: size, font: font, lineSpacing: 12))
    let motion = PromptCaretMotionCoordinator(), view = PromptCaretNativeView(frame: .init(origin: .zero, size: size))
    var config = PromptCaretNativeView.Configuration(text: result.text, mainOffset: 2, paceOffset: nil,
      mainStyle: .bar, paceStyle: .off, font: font, lineSpacing: 12, rightToLeft: false,
      accent: .yellow, motion: .off, reducesMotion: true, frameRate: 30, attemptID: UUID(),
      coordinator: motion, automaticallyPresents: false)
    config.latestRendering = { result }
    view.update(config); view.layout(); view.present(at: 0)
    XCTAssertEqual(motion.main.position, expected)
    view.stop()
  }

  func testInputWrapAdmissionExplicitlyExcludesTransientCandidateInk() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(source.contains("renderedPrompt(for: current, composition: \"\")"))
  }

  func testIndependentRemovedFieldRetainsEveryStructuralReturn() throws {
    var session = TypingSession(configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(freedomMode: true), modifiers: [.noSpaces]),
      prompt: "ba\n\ncd", noSpaceWordEndIndices: [1, 4, 6], noSpaceTargetWords: ["b", "a\n\n", "cd"])
    session.removeTapePromptWords(.init(attemptID: session.automaticInputAttemptID, wordIndices: [1]))
    XCTAssertEqual(session.removedTapePromptWordIndices, [1])
    let result = render(try presentation(session, "X"))
    XCTAssertEqual(String(result.text.characters), "X\n\ncd")
    XCTAssertEqual(result.structuralNewlineOffsets[1], 1)
    XCTAssertNil(result.compositionTextMap?.range(forCanonicalGlyph: 1))
  }

  func testNativeMarkedBridgeUpdatesAndCancelsWithoutAcceptingOrScoringCandidates() throws {
    var session = TypingSession(configuration: .words(2), prompt: "abcdef gh")
    let input = TypingInputView(frame: .zero)
    var composition = ""
    input.onCompositionChanged = { composition = $0 }
    input.onInsert = { text, forced in session.insertBatch(text, forceError: forced, at: self.start) }
    input.insertText("a", replacementRange: .init())
    for candidate in ["bc候", "bc候选中文"] {
      input.setMarkedText(candidate, selectedRange: .init(), replacementRange: .init())
      let result = render(try presentation(session, composition))
      XCTAssertTrue(String(result.text.characters).contains(candidate))
      XCTAssertEqual(session.typed, "a"); XCTAssertEqual(session.errors, 0)
      XCTAssertTrue(input.hasMarkedText())
    }
    input.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    XCTAssertEqual(composition, ""); XCTAssertFalse(input.hasMarkedText())
    XCTAssertEqual(String(render(try presentation(session, composition)).text.characters), session.prompt)
    XCTAssertEqual(session.typed, "a")
  }

  func testRTLBlockAfterAnchorAndCancellationReadFreshProvidersWithoutAViewUpdate() throws {
    var session = TypingSession(configuration: .words(2, language: .hebrew), prompt: "אב גד")
    session.insert("א", at: start)
    var marked = "בXYZ", result = render(try presentation(session, "בXYZ")), reads = 0
    let motion = PromptCaretMotionCoordinator(), view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 400, height: 200))
    var config = PromptCaretNativeView.Configuration(text: result.text, mainOffset: 0, paceOffset: nil,
      mainStyle: .block, paceStyle: .off, font: font, lineSpacing: 12, rightToLeft: true,
      accent: .yellow, motion: .off, reducesMotion: true, frameRate: 30, attemptID: session.automaticInputAttemptID,
      coordinator: motion, automaticallyPresents: false)
    config.latestInput = { .init(attemptID: session.automaticInputAttemptID, typed: session.typed, composition: marked, glyphID: nil) }
    config.latestRendering = { reads += 1; return result }
    view.update(config); view.layout(); view.present(at: 0)
    let map = try XCTUnwrap(result.compositionTextMap), anchor = try XCTUnwrap(map.caret)
    let rect = try XCTUnwrap(PromptCaretLayout.rect(in: result.text, utf16Range: try XCTUnwrap(map.inkRanges[anchor.cellID]),
      containerSize: view.bounds.size, font: font, lineSpacing: 12, isRightToLeft: true, followsWrappedWhitespace: false))
    XCTAssertTrue(anchor.after)
    XCTAssertEqual(try XCTUnwrap(motion.main.position).minX,
      rect.minX - (" " as NSString).size(withAttributes: [.font: font]).width, accuracy: 0.1)
    for frame in 1...5 { view.present(at: Double(frame) / 100) }
    XCTAssertEqual(reads, 1)
    marked = ""; result = render(try presentation(session, marked)); view.present(at: 0.1)
    XCTAssertEqual(reads, 2)
    XCTAssertFalse(try XCTUnwrap(result.compositionTextMap?.caret).after)
    XCTAssertEqual(session.typed, "א")
    view.stop()
  }

  private final class Panel: NSView { override var isFlipped: Bool { true } }
  private func capture(_ result: PromptRendering, name: String) throws {
    guard let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] else { return }
    let panel = Panel(frame: .init(x: 0, y: 0, width: 400, height: 180))
    panel.wantsLayer = true; panel.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    let text = NSHostingView(rootView: Text(result.text).font(Font(font)).lineSpacing(12)
      .fixedSize(horizontal: false, vertical: true).frame(width: 400, alignment: .leading)
      .frame(height: 180, alignment: .topLeading))
    text.frame = panel.bounds; panel.addSubview(text)
    let motion = PromptCaretMotionCoordinator(), caret = PromptCaretNativeView(frame: panel.bounds)
    var config = PromptCaretNativeView.Configuration(text: result.text, mainOffset: nil, paceOffset: nil,
      mainStyle: .bar, paceStyle: .off, font: font, lineSpacing: 12, rightToLeft: false,
      accent: .blue, motion: .off, reducesMotion: true, frameRate: 30, attemptID: UUID(),
      coordinator: motion, automaticallyPresents: false)
    config.latestRendering = { result }; panel.addSubview(caret); caret.update(config)
    let window = NSWindow(contentRect: panel.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = panel
    defer { caret.stop(); window.close() }
    panel.layoutSubtreeIfNeeded(); caret.present(at: 0); panel.displayIfNeeded()
    XCTAssertNotNil(motion.main.position)
    let bitmap = try XCTUnwrap(panel.bitmapImageRepForCachingDisplay(in: panel.bounds))
    panel.cacheDisplay(in: panel.bounds, to: bitmap)
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
      to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
  }

  func testNativeTextAndCaretSnapshotsCoverSlotsOverflowAndFusedCancellation() throws {
    var ordinary = TypingSession(configuration: .words(2), prompt: "abcdef gh"); ordinary.insert("X", at: start)
    try capture(render(try presentation(ordinary, "bc候")), name: "composition-normal-slots-hint")
    var overflow = TypingSession(configuration: .words(2), prompt: "ab cd"); overflow.insert("a", at: start)
    try capture(render(try presentation(overflow, "bXYZ")), name: "composition-normal-overflow-after")
    var fused = TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces]), customText: "a \u{301}b tail")
    fused.insert("a", at: start)
    try capture(render(try presentation(fused, "")), name: "composition-normal-fused-cancellation")
  }
}
