import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptLineRecenteringTests: XCTestCase {
  private final class Document: NSView { override var isFlipped: Bool { true } }
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)
  private let text = AttributedString("amber\nbirch\ncedar\ndelta\nelder\nflint")
  private let starts = [0, 6, 12, 18, 24, 30]

  private func fixture() -> (NSScrollView, PromptAutoScrollView) {
    let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 360, height: 135))
    let document = Document(frame: .init(x: 0, y: 0, width: 360, height: 600))
    scroll.documentView = document
    let follower = PromptAutoScrollView(frame: document.bounds)
    document.addSubview(follower)
    return (scroll, follower)
  }

  private func update(_ follower: PromptAutoScrollView, attempt: UUID, row: Int = 3,
    font: NSFont? = nil, smooth: Bool = false, reduced: Bool = false, centers: Bool = true,
    notify: ((PromptWordRetirement) -> Void)? = nil) {
    follower.update(text: text, characterOffset: starts[row], font: font ?? self.font,
      lineSpacing: 12, isRightToLeft: false,
      lineScroll: .init(attemptID: attempt, activeWordID: starts[row],
        characterOffsets: Dictionary(uniqueKeysWithValues: starts.map { ($0, $0) }),
        smoothScroll: smooth, reducesMotion: reduced,
        words: starts.enumerated().map { .init(index: $0.offset, glyphID: $0.element) },
        onRetire: notify, centersActiveLine: centers))
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
  }

  func testRecreatedBoundedViewportRetiresBeforePreviousWordRowEvenOnFirstJump() {
    let (scroll, follower) = fixture(), attempt = UUID()
    var retired: [PromptWordRetirement] = []
    update(follower, attempt: attempt, notify: { retired.append($0) })
    XCTAssertEqual(retired, [.init(attemptID: attempt, firstRetainedWordIndex: 2)])
    XCTAssertEqual(scroll.contentView.bounds.minY, 45, accuracy: 0.5,
      "The source makes one line jump, then rebases after prefix removal; it does not jump three rows")
  }

  func testFontChangeRetiresPrefixWhileTheActiveWordRemainsUnchanged() {
    let (scroll, follower) = fixture(), attempt = UUID()
    update(follower, attempt: attempt)
    var retired: [PromptWordRetirement] = []
    let larger = NSFont.monospacedSystemFont(ofSize: 40, weight: .medium)
    scroll.frame.size.height = (NSLayoutManager().defaultLineHeight(for: larger) + 12) * 3
    update(follower, attempt: attempt, font: larger, notify: { retired.append($0) })
    XCTAssertEqual(retired, [.init(attemptID: attempt, firstRetainedWordIndex: 2)])
    XCTAssertEqual(scroll.contentView.bounds.minY,
      NSLayoutManager().defaultLineHeight(for: larger) + 12, accuracy: 0.5)
  }

  func testWidthChangeMeasuresSameWordAndForcesFirstRetirement() {
    let (_, follower) = fixture(), attempt = UUID()
    update(follower, attempt: attempt)
    var retired: [PromptWordRetirement] = []
    update(follower, attempt: attempt, notify: { retired.append($0) })
    XCTAssertTrue(retired.isEmpty, "Attaching a callback is not itself a layout change")
    follower.frame.size.width = 280
    follower.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    XCTAssertEqual(retired, [.init(attemptID: attempt, firstRetainedWordIndex: 2)])
  }

  func testFirstForcedSmoothJumpWaitsAndMovesOnlyOneRowEvenFromFarBelowViewport() {
    let (scroll, follower) = fixture(), attempt = UUID()
    var retired: [PromptWordRetirement] = []
    update(follower, attempt: attempt, row: 5, smooth: true, notify: { retired.append($0) })
    XCTAssertTrue(retired.isEmpty)
    XCTAssertLessThan(scroll.contentView.bounds.minY, 45)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    XCTAssertEqual(retired, [.init(attemptID: attempt, firstRetainedWordIndex: 4)])
    XCTAssertEqual(scroll.contentView.bounds.minY, 45, accuracy: 0.5)
  }

  func testReducedMotionMakesForcedRetirementImmediate() {
    let (_, follower) = fixture(), attempt = UUID()
    var retired: [PromptWordRetirement] = []
    update(follower, attempt: attempt, smooth: true, reduced: true, notify: { retired.append($0) })
    XCTAssertEqual(retired, [.init(attemptID: attempt, firstRetainedWordIndex: 2)])
  }

  func testRawShowAllGateSuppressesLayoutRetirementUntilDisabled() {
    let (_, follower) = fixture(), attempt = UUID()
    var retired: [PromptWordRetirement] = []
    let notify: (PromptWordRetirement) -> Void = { retired.append($0) }
    update(follower, attempt: attempt, centers: false, notify: notify)
    update(follower, attempt: attempt, font: .monospacedSystemFont(ofSize: 40, weight: .medium),
      centers: false, notify: notify)
    follower.frame.size.width = 280; follower.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    XCTAssertTrue(retired.isEmpty)
    update(follower, attempt: attempt, font: .monospacedSystemFont(ofSize: 40, weight: .medium), notify: notify)
    XCTAssertEqual(retired, [.init(attemptID: attempt, firstRetainedWordIndex: 2)])
  }

  func testRawShowAllDoesNotRecenterOnFontOrWidthChangesWhenCaretIsAlreadyReachable() {
    let (scroll, follower) = fixture(), attempt = UUID()
    scroll.frame.size.height = 600
    scroll.documentView?.frame.size.height = 1_200
    follower.frame.size.height = 1_200
    update(follower, attempt: attempt, centers: false)
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5)
    update(follower, attempt: attempt, font: .monospacedSystemFont(ofSize: 40, weight: .medium), centers: false)
    follower.frame.size.width = 280; follower.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5)
  }

  func testForcedCenterWithoutRemovablePrefixStillCountsAsFirstJump() {
    let (_, follower) = fixture(), attempt = UUID()
    var retired: [PromptWordRetirement] = []
    let notify: (PromptWordRetirement) -> Void = { retired.append($0) }
    update(follower, attempt: attempt, row: 1, notify: notify)
    XCTAssertTrue(retired.isEmpty)
    update(follower, attempt: attempt, row: 2, notify: notify)
    XCTAssertEqual(retired, [.init(attemptID: attempt, firstRetainedWordIndex: 1)])
  }

  func testForcedCenterUsesPreviousWordContainerNotItsLastInternalRow() {
    let geometry = PromptLineScrollGeometry(activeTop: 225, previousWordTop: nil,
      previousLineTop: 180, wordTops: [0: 0, 1: 45, 2: 225], activeRowHeight: 45)
    XCTAssertEqual(geometry.recenterHideBound(before: 2), 45)
    XCTAssertEqual(geometry.retirementBoundary(before: 2, hideBound: geometry.recenterHideBound(before: 2)), 1)
    XCTAssertNil(geometry.recenterHideBound(before: 0))
    let sameRow = PromptLineScrollGeometry(activeTop: 45, previousWordTop: nil,
      previousLineTop: 0, wordTops: [0: 0, 1: 45, 2: 45], activeRowHeight: 45)
    XCTAssertEqual(sameRow.recenterHideBound(before: 2), 0)
    XCTAssertNil(sameRow.retirementBoundary(before: 2, hideBound: 0))
  }

  func testForcedCenterWithoutRemovablePrefixDoesNotMoveAcrossLongPreviousWord() throws {
    let value = AttributedString(String(repeating: "x", count: 30) + " aa bb")
    let width = ("a" as NSString).size(withAttributes: [.font: font]).width * 6.2
    let words = [0, 31, 34].enumerated().map { PromptLineScrollWord(index: $0.offset, glyphID: $0.element) }
    let offsets = [0: 0, 31: 31, 34: 34]
    let measured = try XCTUnwrap(PromptLineScrollGeometry.measure(in: value, activeOffset: 31,
      previousOffset: nil, width: width, font: font, lineSpacing: 12, rightToLeft: false,
      caretOffset: 31, words: words, characterOffsets: offsets))
    XCTAssertGreaterThan(measured.previousLineTop, 0)
    XCTAssertEqual(measured.recenterHideBound(before: 1), 0)
    for custom in [false, true] { for smooth in [false, true] {
      let (scroll, follower) = fixture()
      defer { follower.removeFromSuperview() }
      follower.frame.size.width = width
      var retired: [PromptWordRetirement] = []
      let customGeometry: PromptLineScrollCustomGeometry? = custom
        ? .init(revision: 1, caretGlyphID: 31, measure: { _, _, _, _ in measured }) : nil
      follower.update(text: value, characterOffset: 31, font: font, lineSpacing: 12, isRightToLeft: false,
        lineScroll: .init(attemptID: UUID(), activeWordID: 31, characterOffsets: offsets,
          smoothScroll: smooth, reducesMotion: false, words: words, onRetire: { retired.append($0) }),
        customGeometry: customGeometry)
      RunLoop.main.run(until: Date().addingTimeInterval(0.2))
      XCTAssertTrue(retired.isEmpty)
      XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5,
        "Complete source centerActiveLine only counts this jump; no prefix means no margin animation")
    } }
  }

  func testRestartAndDetachCancelForcedPendingRetirement() {
    for detach in [false, true] {
      let (_, follower) = fixture(), attempt = UUID()
      var retired: [PromptWordRetirement] = []
      update(follower, attempt: attempt, smooth: true, notify: { retired.append($0) })
      if detach { follower.removeFromSuperview() }
      else { update(follower, attempt: UUID(), row: 0, smooth: true) }
      RunLoop.main.run(until: Date().addingTimeInterval(0.2))
      XCTAssertTrue(retired.isEmpty)
    }
  }

  func testProductionPassesRawShowAllGateToSharedScrollOwner() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(app.contains("centersActiveLine: !settings.showAllPracticeLines"))
  }

  func testPinnedCompleteCenterAndForcedJumpMatchNativeWordBoundaries() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    struct Fixture: Decodable {
      let tops: [Double?], showAllLines: Bool, smooth: Bool, initialLine: Int
      let during: [Int], boundary: Int, jumps: Int, lineAfter: Int
    }
    struct Output: Decodable { let centers: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), out = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-word-retirement.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = out
    try process.run()
    let data = out.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).centers
    XCTAssertEqual(fixtures.count, 56)
    for value in fixtures {
      let active = value.tops.count - 1
      let tops = Dictionary(uniqueKeysWithValues: value.tops.enumerated().compactMap { index, top in top.map { (index, CGFloat($0)) } })
      let geometry = PromptLineScrollGeometry(activeTop: try XCTUnwrap(tops[active]), previousWordTop: nil,
        previousLineTop: 0, wordTops: tops, activeRowHeight: 45)
      let hide = value.showAllLines ? nil : geometry.recenterHideBound(before: active)
      XCTAssertEqual(hide.flatMap { geometry.retirementBoundary(before: active, hideBound: $0) } ?? 0, value.boundary)
      XCTAssertEqual(value.jumps, value.boundary > 0 ? 1 : 0)
      XCTAssertEqual(value.lineAfter, value.initialLine + (hide == nil ? 0 : 1))
      if value.smooth { XCTAssertEqual(value.during, tops.keys.sorted()) }
    }
  }

  @Observable final class Model {
    var session = TypingSession(configuration: .words(6, rules: .init(freedomMode: true)), prompt: "a\nb\nc\nd\ne\nf")
    var showAll = true
    var fontSize: CGFloat = 28
    var width: CGFloat = 240
    let asl: Bool
    init(asl: Bool) { self.asl = asl }
    var rendering: PromptRendering {
      let glyphs = session.promptGlyphs
      return PromptRendering.make(glyphs: glyphs,
        indices: PromptGlyphLayout.indices(glyphs: glyphs, words: session.promptWordPresentations,
          hideExtraLetters: false, firstRetainedWordIndex: session.firstRetainedPromptWordIndex)) { _, glyph in
        var text = AttributedString(PromptControlCharacterPresentation.plan(for: glyph, style: .off).text)
        text.foregroundColor = .black
        return text
      }
    }
  }

  private struct Root: View {
    let model: Model
    var body: some View {
      let rendering = model.rendering, words = model.session.promptWordPresentations
      let font = NSFont.monospacedSystemFont(ofSize: model.fontSize, weight: .medium)
      let showAll = PracticeLineDisplayPolicy.shouldShowAllLines(settingEnabled: model.showAll,
        tapeMode: .off, configuration: model.session.configuration)
      let context = PromptLineScrollContext(attemptID: model.session.automaticInputAttemptID,
        activeWordID: words.first(where: { $0.phase == .active })?.range.lowerBound,
        characterOffsets: rendering.glyphCharacterOffsets, smoothScroll: true, reducesMotion: false,
        words: words.enumerated().map { .init(index: $0.offset, glyphID: $0.element.range.lowerBound) },
        firstRetainedWordIndex: model.session.firstRetainedPromptWordIndex,
        onRetire: { model.session.retirePromptWords($0) }, centersActiveLine: !model.showAll)
      let prompt = Group {
        if model.asl {
          ASLPracticePrompt(glyphs: model.session.promptGlyphsInDisplayOrder,
            fontSize: model.fontSize, accent: .blue,
            glyphIDs: PromptGlyphLayout.indices(glyphs: model.session.promptGlyphs, words: words, hideExtraLetters: false),
            rendering: rendering, font: font, lineScroll: showAll ? nil : context,
            caretGlyphID: model.session.promptCaretGlyphIndex, viewportLineCount: showAll ? nil : 3, words: words)
        } else {
          Text(rendering.text).font(Font(font)).lineSpacing(12)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
              if !showAll {
                PromptAutoScrollOverlay(text: rendering.text,
                  characterOffset: rendering.characterOffset(forGlyphAt: model.session.promptCaretGlyphIndex),
                  font: font, lineSpacing: 12, isRightToLeft: false, lineScroll: context)
              }
            }
        }
      }
      Group {
        if showAll { prompt }
        else {
          PracticePromptViewport(text: rendering.text, font: font, lineSpacing: 12,
            isRightToLeft: false, lineCount: 3, measuresTextRows: !model.asl, measuresCustomRows: model.asl) { prompt }
        }
      }.frame(width: model.width).foregroundStyle(.black).background(.white)
    }
  }

  private func pump(_ host: NSView, _ duration: TimeInterval = 0.04) {
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(duration)); host.layoutSubtreeIfNeeded()
  }

  private func verifyMounted(asl: Bool, timed: Bool) throws {
    let model = Model(asl: asl), start = Date(timeIntervalSinceReferenceDate: 913_000_000)
    if timed { model.session = TypingSession(configuration: .timed(seconds: 60, rules: .init(freedomMode: true)), prompt: "a\nb\nc\nd\ne\nf") }
    model.session.insertBatch("a\nb\nc\n", at: start)
    let attempt = model.session.automaticInputAttemptID
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 320, height: 400),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    let host = NSHostingView(rootView: Root(model: model)); window.contentView = host
    defer { window.contentView = nil; window.close() }
    pump(host); pump(host, 0.2)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
    if timed {
      model.fontSize = 40; model.width = 220; pump(host); pump(host, 0.2)
      XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0,
        "Raw show-all blocks centerActiveLine even though time mode keeps a bounded viewport")
    }
    model.showAll = false; pump(host); pump(host, 0.2); pump(host)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 2)
    XCTAssertEqual(model.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(String(model.rendering.text.characters), "c↵\nd↵\ne↵\nf")
    XCTAssertEqual(model.session.typed, "a\nb\nc\n")
    XCTAssertEqual(model.session.prompt, "a\nb\nc\nd\ne\nf")
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first)
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 1)
    XCTAssertFalse(window.isVisible)
    if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
        to: URL(fileURLWithPath: directory).appendingPathComponent("recenter-\(asl ? "asl" : "text")-\(timed ? "timed" : "finite").png"))
    }
    model.session.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(model.session.typed, "a\nb\n")
    model.session.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(model.session.typed, "a\nb\n", "Retired word cannot be reopened, even in freedom mode")
    model.session.insertBatch("c\nd\ne\nf", at: start.addingTimeInterval(3))
    if timed { model.session.tick(at: start.addingTimeInterval(61)) }
    let result = try XCTUnwrap(model.session.result())
    XCTAssertEqual(result.prompt, "a\nb\nc\nd\ne\nf")
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), model.session.typed)
  }

  func testActualOrdinaryWholeToBoundedTransitionPrunesAndKeepsSessionAndReplay() throws {
    try verifyMounted(asl: false, timed: false)
  }

  func testActualASLWholeToBoundedTransitionPrunesAndKeepsSessionAndReplay() throws {
    try verifyMounted(asl: true, timed: false)
  }

  func testActualTimedBoundedViewportKeepsRawShowAllCenteringGate() throws {
    try verifyMounted(asl: false, timed: true)
    try verifyMounted(asl: true, timed: true)
  }
}
