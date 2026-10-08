import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptWordReflowTests: XCTestCase {
  private final class Document: NSView { override var isFlipped: Bool { true } }
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)

  func testReflowUsesAnchoredTopAndTransitionStartThreshold() {
    var state = PromptWordReflowState()
    state.anchor(at: 45)
    XCTAssertNil(state.jumpFromTop(afterUpdate: 45, enabled: true, transitioning: false))
    XCTAssertEqual(state.jumpFromTop(afterUpdate: 90, enabled: true, transitioning: false), 45)
    XCTAssertEqual(state.transitionStartTop, 90)
    XCTAssertNil(state.jumpFromTop(afterUpdate: 90, enabled: true, transitioning: true))
    XCTAssertEqual(state.jumpFromTop(afterUpdate: 135, enabled: true, transitioning: true), 45)
    XCTAssertEqual(state.transitionStartTop, 90)
    // The source does not advance this threshold for a reentrant jump.
    XCTAssertEqual(state.jumpFromTop(afterUpdate: 135, enabled: true, transitioning: true), 45)
    state.anchor(at: 135)
    XCTAssertNil(state.jumpFromTop(afterUpdate: 135, enabled: true, transitioning: false))
  }

  private func fixture(width: CGFloat) -> (NSScrollView, PromptAutoScrollView) {
    let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: width, height: 135))
    let document = Document(frame: .init(x: 0, y: 0, width: width, height: 600))
    scroll.documentView = document
    let follower = PromptAutoScrollView(frame: document.bounds)
    document.addSubview(follower)
    return (scroll, follower)
  }

  private func update(_ follower: PromptAutoScrollView, text: String, word: Int, attempt: UUID,
    font: NSFont? = nil, follows: Bool = true, smooth: Bool = false, pump: Bool = true,
    onRetire: ((PromptWordRetirement) -> Void)? = nil, centers: Bool = true) {
    follower.update(text: AttributedString(text), characterOffset: word, font: font ?? self.font,
      lineSpacing: 12, isRightToLeft: false, lineScroll: .init(attemptID: attempt,
        activeWordID: word, characterOffsets: [0: 0, 3: 3, 6: 6, 9: text.count - 2],
        smoothScroll: smooth, reducesMotion: false,
        words: [.init(index: 0, glyphID: 0), .init(index: 1, glyphID: 3),
          .init(index: 2, glyphID: 6), .init(index: 3, glyphID: 9)],
        onRetire: onRetire, followsWordReflow: follows, centersActiveLine: centers))
    if pump { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
  }

  func testSameWordMovingDownRetiresOldPrefixWithoutCaretOverflow() {
    let unit = ("a" as NSString).size(withAttributes: [.font: font]).width
    let (scroll, follower) = fixture(width: unit * 6.2), attempt = UUID()
    var retirements: [PromptWordRetirement] = []
    let notify: (PromptWordRetirement) -> Void = { retirements.append($0) }
    update(follower, text: "aa\nbb cc dd", word: 0, attempt: attempt, onRetire: notify)
    update(follower, text: "aa\nbb cc dd", word: 6, attempt: attempt, onRetire: notify)
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5)
    update(follower, text: "aa\nbb ccxx dd", word: 6, attempt: attempt, onRetire: notify)
    XCTAssertEqual(scroll.contentView.bounds.minY, 45, accuracy: 0.5)
    XCTAssertEqual(retirements, [.init(attemptID: attempt, firstRetainedWordIndex: 1)])
  }

  func testEqualLengthReplacementStillMeasuresAndFollowsReflow() throws {
    let proportional = NSFont.systemFont(ofSize: 28)
    let narrow = ("bb iii" as NSString).size(withAttributes: [.font: proportional]).width
    let wide = ("bb WWW" as NSString).size(withAttributes: [.font: proportional]).width
    let width = (narrow + wide) / 2
    let (scroll, follower) = fixture(width: width), attempt = UUID()
    update(follower, text: "aa\nbb iii dd", word: 0, attempt: attempt, font: proportional)
    update(follower, text: "aa\nbb iii dd", word: 6, attempt: attempt, font: proportional)
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5)
    update(follower, text: "aa\nbb WWW dd", word: 6, attempt: attempt, font: proportional)
    let before = try XCTUnwrap(PromptLineScrollGeometry.measure(in: AttributedString("aa\nbb iii dd"),
      activeOffset: 6, previousOffset: nil, width: width, font: proportional,
      lineSpacing: 12, rightToLeft: false))
    XCTAssertEqual(scroll.contentView.bounds.minY, before.activeTop, accuracy: 0.5)
    XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
  }

  func testEnablingSlowReflowDoesNotInventAWordUpdate() {
    let unit = ("a" as NSString).size(withAttributes: [.font: font]).width
    let (scroll, follower) = fixture(width: unit * 6.2), attempt = UUID()
    update(follower, text: "aa\nbb cc dd", word: 0, attempt: attempt, follows: false)
    update(follower, text: "aa\nbb cc dd", word: 6, attempt: attempt, follows: false)
    update(follower, text: "aa\nbb ccxx dd", word: 6, attempt: attempt, follows: false)
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5)
    update(follower, text: "aa\nbb ccxx dd", word: 6, attempt: attempt)
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5)
    update(follower, text: "aa\nbb ccxxx dd", word: 6, attempt: attempt)
    XCTAssertEqual(scroll.contentView.bounds.minY, 45, accuracy: 0.5)
  }

  func testCoalescedSettingsUpdateKeepsThePendingTextUpdate() {
    let unit = ("a" as NSString).size(withAttributes: [.font: font]).width
    let (scroll, follower) = fixture(width: unit * 6.2), attempt = UUID()
    update(follower, text: "aa\nbb cc dd", word: 0, attempt: attempt)
    update(follower, text: "aa\nbb cc dd", word: 6, attempt: attempt)
    update(follower, text: "aa\nbb ccxx dd", word: 6, attempt: attempt, follows: false, pump: false)
    update(follower, text: "aa\nbb ccxx dd", word: 6, attempt: attempt)
    XCTAssertEqual(scroll.contentView.bounds.minY, 45, accuracy: 0.5)
  }

  func testFirstJumpFromWordReflowDoesNotScrollOrRetireThePrefix() {
    let unit = ("a" as NSString).size(withAttributes: [.font: font]).width
    let (scroll, follower) = fixture(width: unit * 6.2), attempt = UUID()
    var retired: [PromptWordRetirement] = []
    // Isolate updateWordLetters with no prior wrapper/resize centerActiveLine call.
    update(follower, text: "aa\nbb cc dd", word: 6, attempt: attempt, onRetire: { retired.append($0) }, centers: false)
    update(follower, text: "aa\nbb ccxx dd", word: 6, attempt: attempt, onRetire: { retired.append($0) }, centers: false)
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5)
    XCTAssertTrue(retired.isEmpty)
    update(follower, text: "aa\nbb ccxy dd", word: 6, attempt: attempt, onRetire: { retired.append($0) }, centers: false)
    XCTAssertEqual(scroll.contentView.bounds.minY, 45, accuracy: 0.5)
    XCTAssertEqual(retired, [.init(attemptID: attempt, firstRetainedWordIndex: 1)])
  }

  func testSmoothReflowWaitsToRetireAndSameTargetDoesNotRestartMotion() {
    let unit = ("a" as NSString).size(withAttributes: [.font: font]).width
    let (scroll, follower) = fixture(width: unit * 6.2), attempt = UUID()
    var retired: [PromptWordRetirement] = []
    let notify: (PromptWordRetirement) -> Void = { retired.append($0) }
    update(follower, text: "aa\nbb cc dd", word: 0, attempt: attempt, smooth: true, onRetire: notify)
    update(follower, text: "aa\nbb cc dd", word: 6, attempt: attempt, smooth: true, onRetire: notify)
    update(follower, text: "aa\nbb ccxx dd", word: 6, attempt: attempt, smooth: true, onRetire: notify)
    XCTAssertTrue(retired.isEmpty)
    XCTAssertLessThan(scroll.contentView.bounds.minY, 45)
    RunLoop.main.run(until: Date().addingTimeInterval(0.07))
    update(follower, text: "aa\nbb ccxy dd", word: 6, attempt: attempt, smooth: true, onRetire: notify)
    RunLoop.main.run(until: Date().addingTimeInterval(0.08))
    XCTAssertEqual(scroll.contentView.bounds.minY, 45, accuracy: 0.5)
    XCTAssertEqual(retired, [.init(attemptID: attempt, firstRetainedWordIndex: 1)])
  }

  func testRestartAndDetachCancelReflowRetirement() {
    for detach in [false, true] {
      let unit = ("a" as NSString).size(withAttributes: [.font: font]).width
      let (scroll, follower) = fixture(width: unit * 6.2), attempt = UUID()
      var retired: [PromptWordRetirement] = []
      let notify: (PromptWordRetirement) -> Void = { retired.append($0) }
      update(follower, text: "aa\nbb cc dd", word: 0, attempt: attempt, smooth: true, onRetire: notify)
      update(follower, text: "aa\nbb cc dd", word: 6, attempt: attempt, smooth: true, onRetire: notify)
      update(follower, text: "aa\nbb ccxx dd", word: 6, attempt: attempt, smooth: true, onRetire: notify)
      if detach { follower.removeFromSuperview() }
      else { update(follower, text: "aa\nbb cc dd", word: 0, attempt: UUID(), smooth: true) }
      let origin = scroll.contentView.bounds.origin
      RunLoop.main.run(until: Date().addingTimeInterval(0.2))
      XCTAssertEqual(scroll.contentView.bounds.origin, origin)
      XCTAssertTrue(retired.isEmpty)
    }
  }

  func testDisabledMissingAnchorAndBackwardMotionDoNotChangeThreshold() {
    var state = PromptWordReflowState()
    XCTAssertNil(state.jumpFromTop(afterUpdate: 90, enabled: true, transitioning: false))
    state.anchor(at: 45)
    XCTAssertNil(state.jumpFromTop(afterUpdate: 90, enabled: false, transitioning: false))
    XCTAssertNil(state.jumpFromTop(afterUpdate: 0, enabled: true, transitioning: false))
    XCTAssertEqual(state.transitionStartTop, 0)
    XCTAssertEqual(state.baselineTop, 45)
  }

  func testRawShowAllLinesDisablesReflowEvenWhenTimedViewportIsBounded() {
    for mode in TestMode.allCases {
      for slow in [false, true] {
        XCTAssertFalse(PromptWordReflowPolicy.isEnabled(mode: mode, slowTimer: slow, showAllLines: true))
        XCTAssertEqual(PromptWordReflowPolicy.isEnabled(mode: mode, slowTimer: slow, showAllLines: false),
          mode == .zen || slow)
      }
    }
  }

  func testPinnedCompleteWordUpdateAndRealRAFMatchNativeReflowGate() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    struct Fixture: Decodable {
      let mode: TestMode, slow: Bool, showAllLines: Bool, transitioning: Bool
      let top: Double, jumpFrom: Double?, thresholdAfter: Double
    }
    struct Jump: Decodable {
      let initialLine: Int, prefixTop: Double, willRemove: Bool
    }
    struct Evidence: Decodable { let cases: [Fixture], lineJumps: [Jump] }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      project.appendingPathComponent("Scripts/check-source-word-reflow.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let evidence = try JSONDecoder().decode(Evidence.self, from: data)
    let fixtures = evidence.cases
    XCTAssertEqual(fixtures.count, 560)
    for fixture in fixtures {
      var state = PromptWordReflowState()
      state.anchor(at: 45)
      _ = state.jumpFromTop(afterUpdate: 90, enabled: true, transitioning: false)
      let jump = state.jumpFromTop(afterUpdate: fixture.top,
        enabled: PromptWordReflowPolicy.isEnabled(mode: fixture.mode,
          slowTimer: fixture.slow, showAllLines: fixture.showAllLines), transitioning: fixture.transitioning)
      XCTAssertEqual(jump.map(Double.init), fixture.jumpFrom)
      XCTAssertEqual(state.transitionStartTop, fixture.thresholdAfter)
    }
    XCTAssertEqual(evidence.lineJumps.count, 8)
    for jump in evidence.lineJumps {
      let geometry = PromptLineScrollGeometry(activeTop: 90, previousWordTop: 90,
        previousLineTop: 45, wordTops: [0: jump.prefixTop, 1: 90])
      XCTAssertEqual(jump.initialLine > 0 && geometry.retirementBoundary(before: 1, hideBound: 45) != nil,
        jump.willRemove)
    }
  }

  func testReflowWithoutARemovablePrefixDoesNotScroll() {
    let unit = ("a" as NSString).size(withAttributes: [.font: font]).width
    let (scroll, follower) = fixture(width: unit * 6.2), attempt = UUID()
    // A restored retained-prefix context starts after the first jump, but its
    // presented words all share the active baseline. No older row can retire.
    func set(_ text: String) {
      follower.update(text: AttributedString(text), characterOffset: 6, font: font,
        lineSpacing: 12, isRightToLeft: false, lineScroll: .init(attemptID: attempt,
          activeWordID: 6, characterOffsets: [3: 3, 6: 6], smoothScroll: false,
          reducesMotion: false, words: [.init(index: 1, glyphID: 3), .init(index: 2, glyphID: 6)],
          firstRetainedWordIndex: 1, followsWordReflow: true))
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    set("  \nbb cc dd")
    set("  \nbb ccxx dd")
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5)
  }

  @Observable final class Model {
    var session = TypingSession(configuration: .words(4, rules: .init(freedomMode: true)),
      prompt: "aa\nbb cc dd")
    var rendering: PromptRendering {
      let glyphs = session.promptGlyphs
      let indices = PromptGlyphLayout.indices(glyphs: glyphs, words: session.promptWordPresentations,
        hideExtraLetters: false, firstRetainedWordIndex: session.firstRetainedPromptWordIndex)
      return PromptRendering.make(glyphs: glyphs, indices: indices) { _, glyph in
        AttributedString(PromptControlCharacterPresentation.plan(for: glyph, style: .off).text)
      }
    }
  }

  private struct Root: View {
    let model: Model
    let width: CGFloat
    var body: some View {
      let rendering = model.rendering, words = model.session.promptWordPresentations
      let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)
      PracticePromptViewport(text: rendering.text, font: font, lineSpacing: 12,
        isRightToLeft: false, lineCount: 3) {
        Text(rendering.text).font(Font(font)).lineSpacing(12)
          .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
          .overlay {
            PromptAutoScrollOverlay(text: rendering.text,
              characterOffset: rendering.characterOffset(forGlyphAt: model.session.promptCaretGlyphIndex),
              font: font, lineSpacing: 12, isRightToLeft: false,
              lineScroll: .init(attemptID: model.session.automaticInputAttemptID,
                activeWordID: words.first(where: { $0.phase == .active })?.range.lowerBound,
                characterOffsets: rendering.glyphCharacterOffsets, smoothScroll: true, reducesMotion: false,
                words: words.enumerated().map { .init(index: $0.offset, glyphID: $0.element.range.lowerBound) },
                firstRetainedWordIndex: model.session.firstRetainedPromptWordIndex,
                onRetire: { model.session.retirePromptWords($0) },
                followsWordReflow: PromptWordReflowPolicy.isEnabled(mode: model.session.configuration.mode,
                  slowTimer: true, showAllLines: false)))
          }
      }.frame(width: width).foregroundStyle(.white).background(.black)
    }
  }

  func testProductionViewportReflowsPrunesAndKeepsTheCompleteSessionTape() throws {
    let unit = ("a" as NSString).size(withAttributes: [.font: font]).width
    let model = Model(), width = unit * 6.2
    let host = NSHostingView(rootView: Root(model: model, width: width))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: 135),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    defer { window.contentView = nil }
    func pump(_ seconds: Double = 0.04) {
      host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
    let start = Date(timeIntervalSinceReferenceDate: 913_000_000)
    pump()
    model.session.insertBatch("aa\n", at: start); pump()
    model.session.insertBatch("bb ", at: start.addingTimeInterval(1)); pump()
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
    model.session.insertBatch("ccxx", at: start.addingTimeInterval(2)); pump(0.01)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
    pump(0.2); pump()
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 1)
    XCTAssertEqual(String(model.rendering.text.characters), "bb ccxx dd")
    XCTAssertEqual(model.session.typed, "aa\nbb ccxx")
    XCTAssertEqual(model.session.prompt, "aa\nbb cc dd")
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first)
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 1)
    XCTAssertFalse(window.isVisible)
    if let directory = ProcessInfo.processInfo.environment["TYPEBAR_REFLOW_QA_IMAGE_DIRECTORY"],
      let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        .write(to: URL(fileURLWithPath: directory).appendingPathComponent("same-word-reflow-pruned.png"))
    }
    model.session.insertBatch(" dd", at: start.addingTimeInterval(3)); pump()
    let result = try XCTUnwrap(model.session.result())
    XCTAssertEqual(result.prompt, "aa\nbb cc dd")
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration),
      model.session.typed)
    XCTAssertEqual(result.typedCharacterCount, 13)
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    XCTAssertEqual(archive.results, [result])
  }
}
