import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptLineOverlapTests: XCTestCase {
  func testOverlapUsesTheNewestHeightTimesPendingJumpsNotSummedHeights() {
    var sequence = PromptLineScrollOverlap()
    XCTAssertEqual(sequence.begin(from: 0, rowHeight: 45), 45)
    XCTAssertEqual(sequence.begin(from: 45, rowHeight: 25), 50)
    XCTAssertEqual(sequence.begin(from: 50, rowHeight: 59), 177)
    XCTAssertEqual(sequence.pendingJumps, 3)
    sequence = .init()
    XCTAssertEqual(sequence.begin(from: 90, rowHeight: 25), 115)
    XCTAssertEqual(sequence.pendingJumps, 1)
  }

  func testAutoplayStartsTwelveMillisecondsAheadOfSeekTime() {
    XCTAssertEqual(PromptLineScrollMotion.autoplayLead, 0.012, accuracy: 1e-9)
    let progress = PromptLineScrollMotion.progress(elapsed: 0.025 + PromptLineScrollMotion.autoplayLead)
    XCTAssertEqual(progress, 0.504384, accuracy: 1e-9)
    XCTAssertEqual(PromptLineScrollMotion.progress(elapsed: 0.113 + PromptLineScrollMotion.autoplayLead), 1)
  }

  private final class Document: NSView { override var isFlipped: Bool { true } }

  private func fixture(height: CGFloat = 600) -> (NSScrollView, PromptAutoScrollView) {
    let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 360, height: 135))
    let document = Document(frame: .init(x: 0, y: 0, width: 360, height: height))
    scroll.documentView = document
    let follower = PromptAutoScrollView(frame: .init(x: 0, y: 0, width: 360, height: 600))
    document.addSubview(follower)
    return (scroll, follower)
  }

  private func update(_ follower: PromptAutoScrollView, row: Int, attempt: UUID,
    caret: Int? = nil, reduced: Bool = false, smooth: Bool = true, retained: Int = 0,
    notify: @escaping (PromptWordRetirement) -> Void) {
    let starts = [0, 6, 12, 18, 24, 30]
    follower.update(text: AttributedString("amber\nbirch\ncedar\ndelta\nelder\nflint"),
      characterOffset: caret ?? starts[row], font: .monospacedSystemFont(ofSize: 28, weight: .medium),
      lineSpacing: 12, isRightToLeft: false, lineScroll: .init(attemptID: attempt,
        activeWordID: starts[row], characterOffsets: Dictionary(uniqueKeysWithValues: starts.map { ($0, $0) }),
        smoothScroll: smooth, reducesMotion: reduced,
        words: starts.enumerated().map { .init(index: $0.offset, glyphID: $0.element) },
        firstRetainedWordIndex: retained, onRetire: notify))
    RunLoop.main.run(until: Date().addingTimeInterval(0.005))
  }

  func testANewJumpAtTheSamePhysicalTargetStillReplacesTheCompletionTime() {
    let (scroll, follower) = fixture(), attempt = UUID()
    var retired: [PromptWordRetirement] = []
    let notify: (PromptWordRetirement) -> Void = { retired.append($0) }
    for row in 0...2 {
      update(follower, row: row, attempt: attempt, caret: row == 2 ? 30 : nil, notify: notify)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.07))
    update(follower, row: 3, attempt: attempt, caret: 30, notify: notify)
    RunLoop.main.run(until: Date().addingTimeInterval(0.065))
    XCTAssertTrue(retired.isEmpty, "The canceled older animation cannot complete the newer jump")
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    XCTAssertEqual(retired, [.init(attemptID: attempt, firstRetainedWordIndex: 2)])
    XCTAssertGreaterThan(scroll.contentView.bounds.minY, 90)
  }

  func testAConstrainedZeroDistanceJumpStillDefersRetirementUntilCompletion() {
    let (scroll, follower) = fixture(height: 135), attempt = UUID()
    var retired: [PromptWordRetirement] = []
    for row in 0...2 { update(follower, row: row, attempt: attempt, notify: { retired.append($0) }) }
    XCTAssertEqual(scroll.contentView.bounds.minY, 0)
    XCTAssertTrue(retired.isEmpty)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    XCTAssertEqual(retired, [.init(attemptID: attempt, firstRetainedWordIndex: 1)])
    XCTAssertEqual(scroll.contentView.bounds.minY, 0)
  }

  func testReducedOrDisabledMotionRetiresImmediatelyAndDoesNotKeepAnOverlap() {
    for reduced in [false, true] {
      let (scroll, follower) = fixture(), attempt = UUID()
      var retired: [PromptWordRetirement] = []
      for row in 0...3 {
        update(follower, row: row, attempt: attempt, reduced: reduced, smooth: reduced,
          notify: { retired.append($0) })
      }
      XCTAssertEqual(retired.map(\.firstRetainedWordIndex), [1, 2])
      XCTAssertEqual(scroll.contentView.bounds.minY, 90, accuracy: 0.5)
      RunLoop.main.run(until: Date().addingTimeInterval(0.15))
      XCTAssertEqual(retired.count, 2)
    }
  }

  func testRestartDetachAndWidthChangeCancelTheLatestOverlapWithoutAnOldCallback() {
    for action in ["restart", "detach", "width"] {
      let (scroll, follower) = fixture(), attempt = UUID()
      var retired: [PromptWordRetirement] = []
      for row in 0...3 { update(follower, row: row, attempt: attempt, notify: { retired.append($0) }) }
      XCTAssertTrue(retired.isEmpty)
      switch action {
      case "restart": update(follower, row: 0, attempt: UUID(), notify: { retired.append($0) })
      case "detach": follower.removeFromSuperview()
      default: follower.frame.size.width = 380; follower.layout()
      }
      RunLoop.main.run(until: Date().addingTimeInterval(0.2))
      XCTAssertTrue(retired.isEmpty)
      if action == "restart" { XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5) }
    }
  }

  func testNativeLastFragmentRestoresSpacingForTheJumpHeight() throws {
    for text in ["amber\nbirch", "amber\nbirch\ncedar"] {
      let geometry = try XCTUnwrap(PromptLineScrollGeometry.measure(in: AttributedString(text),
        activeOffset: 6, previousOffset: 0, width: 360,
        font: .monospacedSystemFont(ofSize: 28, weight: .medium), lineSpacing: 12, rightToLeft: false))
      XCTAssertEqual(geometry.activeRowHeight, 45, accuracy: 0.5)
    }
  }

  @Observable final class Model {
    var session = TypingSession(configuration: .words(6), prompt: "amber\nbirch\ncedar\ndelta\nelder\nflint")
    var rendering: PromptRendering {
      let glyphs = session.promptGlyphs
      let indices = PromptGlyphLayout.indices(glyphs: glyphs, words: session.promptWordPresentations,
        hideExtraLetters: false, firstRetainedWordIndex: session.firstRetainedPromptWordIndex)
      return PromptRendering.make(glyphs: glyphs, indices: indices) { _, glyph in
        AttributedString(String(glyph.character))
      }
    }
  }

  private struct Root: View {
    let model: Model
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
                onRetire: { model.session.retirePromptWords($0) }))
          }
      }.frame(width: 360)
    }
  }

  func testProductionViewportOverlapsThenPrunesOnlyTheNewestPrefixAndKeepsReplay() throws {
    let model = Model(), host = NSHostingView(rootView: Root(model: Model()))
    host.rootView = Root(model: model)
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 360, height: 135),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    defer { window.contentView = nil }
    func pump(_ seconds: Double = 0.01) {
      host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
    let start = Date(timeIntervalSinceReferenceDate: 913_000_000)
    pump(0.04)
    model.session.insertBatch("amber\n", at: start); pump()
    model.session.insertBatch("birch\n", at: start.addingTimeInterval(1)); pump(0.03)
    model.session.insertBatch("cedar\n", at: start.addingTimeInterval(2)); pump()
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
    pump(0.2); pump(0.04)
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 2)
    XCTAssertEqual(String(model.rendering.text.characters), "cedar\ndelta\nelder\nflint")
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first)
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 1)
    XCTAssertFalse(window.isVisible)
    model.session.insertBatch("delta\nelder\nflint", at: start.addingTimeInterval(3)); pump(0.2)
    let result = try XCTUnwrap(model.session.result())
    XCTAssertEqual(result.prompt, "amber\nbirch\ncedar\ndelta\nelder\nflint")
    XCTAssertEqual(result.typedCharacterCount, 35)
    XCTAssertEqual(result.errorCount, 0)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration),
      model.session.typed)
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    XCTAssertEqual(archive.results, [result])
  }

  func testANewerJumpReplacesRatherThanMergesAnOlderRetirement() {
    let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 360, height: 135))
    let document = Document(frame: .init(x: 0, y: 0, width: 360, height: 600))
    scroll.documentView = document
    let follower = PromptAutoScrollView(frame: document.bounds)
    document.addSubview(follower)
    let attempt = UUID(), starts = [0, 6, 12, 18, 24, 30]
    var retired: [PromptWordRetirement] = []
    for row in [0, 1, 2, 3, 4, 2, 3] {
      follower.update(text: AttributedString("amber\nbirch\ncedar\ndelta\nelder\nflint"),
        characterOffset: starts[row], font: .monospacedSystemFont(ofSize: 28, weight: .medium),
        lineSpacing: 12, isRightToLeft: false, lineScroll: .init(attemptID: attempt,
          activeWordID: starts[row], characterOffsets: Dictionary(uniqueKeysWithValues: starts.map { ($0, $0) }),
          smoothScroll: true, reducesMotion: false,
          words: starts.enumerated().map { .init(index: $0.offset, glyphID: $0.element) },
          onRetire: { retired.append($0) }))
      RunLoop.main.run(until: Date().addingTimeInterval(0.005))
    }
    XCTAssertTrue(retired.isEmpty)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    XCTAssertEqual(retired, [.init(attemptID: attempt, firstRetainedWordIndex: 2)])
  }

  func testCompletePinnedEngineCompositionAndPromisesMatchNativeTargetsAndTiming() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout and QA-only Anime.js archive")
    }
    struct Sample: Decodable {
      let margin: Double, targets: [Double], resolved: [Int]
      let height: Double?
    }
    struct Motion: Decodable {
      let elapsed: Double, margin: Double, animationTime: Double, resolved: [Int]
    }
    struct Fixture: Decodable {
      let jumps: Int, samples: [Sample], motionSamples: [Motion]
    }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      project.appendingPathComponent("Scripts/check-source-line-overlap.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 12)
    for fixture in fixtures {
      var sequence = PromptLineScrollOverlap(), target: CGFloat = 0
      for sample in fixture.samples.prefix(fixture.jumps) {
        target = sequence.begin(from: target, rowHeight: try XCTUnwrap(sample.height))
        XCTAssertEqual(Double(target), -(try XCTUnwrap(sample.targets.last)), accuracy: 1e-9)
        XCTAssertTrue(sample.resolved.isEmpty)
      }
      XCTAssertEqual(try XCTUnwrap(fixture.samples.last).resolved, [fixture.jumps - 1])
      let from = try XCTUnwrap(fixture.samples.dropLast().last).margin
      for sample in fixture.motionSamples where sample.resolved.isEmpty && sample.elapsed >= 10 {
        let fraction = PromptLineScrollMotion.progress(
          elapsed: sample.elapsed / 1_000 + PromptLineScrollMotion.autoplayLead)
        XCTAssertEqual(Double(fraction) * (-Double(target) - from) + from, sample.margin, accuracy: 1e-6)
      }
    }
  }
}
