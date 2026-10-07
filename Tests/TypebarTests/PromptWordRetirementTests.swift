import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptWordRetirementTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 913_000_000)

  func testRetiredPreviousWordCannotBeReopenedEvenInFreedomMode() {
    for wholeWord in [false, true] {
      var session = TypingSession(configuration: .words(4, rules: .init(freedomMode: true)),
        prompt: "amber birch cedar delta")
      session.insertBatch("amber birch ", at: start)
      session.retirePromptWords(.init(attemptID: session.automaticInputAttemptID, firstRetainedWordIndex: 1))
      XCTAssertEqual(session.firstRetainedPromptWordIndex, 1)
      session.deleteWordBackward(at: start.addingTimeInterval(1))
      XCTAssertEqual(session.typed, "amber ")
      if wholeWord { session.deleteWordBackward(at: start.addingTimeInterval(2)) }
      else { session.deleteBackward(at: start.addingTimeInterval(2)) }
      XCTAssertEqual(session.typed, "amber ")
    }
  }

  func testRetiredGlyphsAndTheirExtrasLeaveTheRenderedTextNotTheSessionTape() {
    var session = TypingSession(configuration: .words(4, rules: .init(freedomMode: true)),
      prompt: "amber birch cedar delta")
    session.insertBatch("amberxxx birch ", at: start)
    let words = session.promptWordPresentations, glyphs = session.promptGlyphs
    let indices = PromptGlyphLayout.indices(glyphs: glyphs, words: words,
      hideExtraLetters: false, firstRetainedWordIndex: 1)
    let rendering = PromptRendering.make(glyphs: glyphs, indices: indices) { _, glyph in
      AttributedString(String(glyph.character))
    }
    XCTAssertEqual(String(rendering.text.characters), "birch cedar delta")
    XCTAssertNil(rendering.characterOffset(forGlyphAt: 0))
    XCTAssertEqual(rendering.characterOffset(forGlyphAt: 6), 0)
    XCTAssertEqual(session.typed, "amberxxx birch ")
    XCTAssertEqual(session.prompt, "amber birch cedar delta")
  }

  private final class Document: NSView { override var isFlipped: Bool { true } }
  func testFollowerRetiresOnlyAfterSmoothAnimationAndNotOnFirstWrap() {
    let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 360, height: 135))
    let document = Document(frame: .init(x: 0, y: 0, width: 360, height: 500))
    scroll.documentView = document
    let follower = PromptAutoScrollView(frame: document.bounds)
    document.addSubview(follower)
    let attempt = UUID(), offsets = [0: 0, 6: 6, 12: 12, 18: 18]
    var retired: [PromptWordRetirement] = []
    for row in 0...2 {
      follower.update(text: AttributedString("amber\nbirch\ncedar\ndelta"),
        characterOffset: row * 6, font: .monospacedSystemFont(ofSize: 28, weight: .medium),
        lineSpacing: 12, isRightToLeft: false, lineScroll: .init(attemptID: attempt,
          activeWordID: row * 6, characterOffsets: offsets, smoothScroll: true, reducesMotion: false,
          words: (0...3).map { .init(index: $0, glyphID: $0 * 6) }, onRetire: { retired.append($0) }))
      RunLoop.main.run(until: Date().addingTimeInterval(0.005))
      XCTAssertTrue(retired.isEmpty)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    XCTAssertEqual(retired, [.init(attemptID: attempt, firstRetainedWordIndex: 1)])
    XCTAssertEqual(scroll.contentView.bounds.minY, 45, accuracy: 0.5)
  }

  func testANewerRetirementSurvivesAnUnchangedCaretReachabilityTarget() {
    let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 360, height: 135))
    let document = Document(frame: .init(x: 0, y: 0, width: 360, height: 500))
    scroll.documentView = document
    let follower = PromptAutoScrollView(frame: document.bounds)
    document.addSubview(follower)
    let attempt = UUID(), starts = [0, 6, 12, 18, 24, 30]
    var retired: [Int] = []
    for row in 0...3 {
      follower.update(text: AttributedString("amber\nbirch\ncedar\ndelta\nelder\nflint"),
        characterOffset: row >= 2 ? 30 : starts[row], font: .monospacedSystemFont(ofSize: 28, weight: .medium),
        lineSpacing: 12, isRightToLeft: false, lineScroll: .init(attemptID: attempt,
          activeWordID: starts[row], characterOffsets: Dictionary(uniqueKeysWithValues: starts.map { ($0, $0) }),
          smoothScroll: true, reducesMotion: false,
          words: starts.enumerated().map { .init(index: $0.offset, glyphID: $0.element) },
          onRetire: { retired.append($0.firstRetainedWordIndex) }))
      RunLoop.main.run(until: Date().addingTimeInterval(0.005))
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    XCTAssertEqual(retired.last, 2)
  }

  func testRetirementRejectsStaleRegressiveFutureAndFinishedNotifications() {
    var session = TypingSession(configuration: .words(4), prompt: "aa bb cc dd")
    session.insertBatch("aa bb ", at: start)
    let id = session.automaticInputAttemptID
    for event in [PromptWordRetirement(attemptID: UUID(), firstRetainedWordIndex: 1),
      .init(attemptID: id, firstRetainedWordIndex: 3), .init(attemptID: id, firstRetainedWordIndex: -1)] {
      session.retirePromptWords(event)
      XCTAssertEqual(session.firstRetainedPromptWordIndex, 0)
    }
    session.retirePromptWords(.init(attemptID: id, firstRetainedWordIndex: 1))
    session.retirePromptWords(.init(attemptID: id, firstRetainedWordIndex: 0))
    XCTAssertEqual(session.firstRetainedPromptWordIndex, 1)
    let repeated = session.repeatedAttempt()
    XCTAssertEqual(repeated.firstRetainedPromptWordIndex, 0)
    XCTAssertNotEqual(repeated.automaticInputAttemptID, id)
    session.insertBatch("cc dd", at: start.addingTimeInterval(1))
    session.retirePromptWords(.init(attemptID: id, firstRetainedWordIndex: 2))
    XCTAssertEqual(session.firstRetainedPromptWordIndex, 1)
  }

  func testRetirementDoesNotEraseInputReplayMetricsOrArchivedResults() throws {
    var session = TypingSession(configuration: .words(4), prompt: "aa bb cc dd")
    session.insertBatch("aa bb ", at: start)
    session.retirePromptWords(.init(attemptID: session.automaticInputAttemptID, firstRetainedWordIndex: 1))
    session.insertBatch("cc dd", at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.prompt, "aa bb cc dd")
    XCTAssertEqual(session.typed, "aa bb cc dd")
    XCTAssertEqual(result.typedCharacterCount, 11)
    XCTAssertEqual(result.errorCount, 0)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), session.typed)
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    XCTAssertEqual(archive.results, [result])
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
  }

  func testUnicodeAndNoSpaceBoundariesKeepCurrentCorrectionButBlockMissingPreviousWord() {
    var unicode = TypingSession(configuration: .words(3, rules: .init(freedomMode: true)),
      prompt: "🧑🏽‍💻 e\u{301} tail")
    unicode.insertBatch("🧑🏽‍💻 e\u{301} ", at: start)
    unicode.retirePromptWords(.init(attemptID: unicode.automaticInputAttemptID, firstRetainedWordIndex: 1))
    unicode.deleteWordBackward(at: start.addingTimeInterval(1))
    unicode.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(unicode.typed, "🧑🏽‍💻 ")
    var joined = TypingSession(configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(freedomMode: true), modifiers: [.noSpaces]),
      prompt: "abcdtail", noSpaceWordEndIndices: [2, 4, 8], noSpaceTargetWords: ["ab", "cd", "tail"])
    joined.insertBatch("abcd", at: start)
    joined.retirePromptWords(.init(attemptID: joined.automaticInputAttemptID, firstRetainedWordIndex: 1))
    joined.deleteWordBackward(at: start.addingTimeInterval(1))
    joined.deleteWordBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(joined.typed, "ab")
  }

  func testRestartOrDetachCancelsPendingRetirement() {
    for detach in [false, true] {
      let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 360, height: 135))
      let document = Document(frame: .init(x: 0, y: 0, width: 360, height: 500))
      scroll.documentView = document
      let follower = PromptAutoScrollView(frame: document.bounds)
      document.addSubview(follower)
      let id = UUID()
      var events = 0
      for row in 0...2 {
        follower.update(text: AttributedString("amber\nbirch\ncedar\ndelta"),
          characterOffset: row * 6, font: .monospacedSystemFont(ofSize: 28, weight: .medium),
          lineSpacing: 12, isRightToLeft: false, lineScroll: .init(attemptID: id,
            activeWordID: row * 6, characterOffsets: [0: 0, 6: 6, 12: 12, 18: 18],
            smoothScroll: true, reducesMotion: false,
            words: (0...3).map { .init(index: $0, glyphID: $0 * 6) }, onRetire: { _ in events += 1 }))
        RunLoop.main.run(until: Date().addingTimeInterval(0.005))
      }
      if detach { follower.removeFromSuperview() }
      else {
        follower.update(text: AttributedString("new"), characterOffset: 0,
          font: .monospacedSystemFont(ofSize: 28, weight: .medium), lineSpacing: 12, isRightToLeft: false,
          lineScroll: .init(attemptID: UUID(), activeWordID: 0, characterOffsets: [0: 0],
            smoothScroll: true, reducesMotion: false))
      }
      RunLoop.main.run(until: Date().addingTimeInterval(0.2))
      XCTAssertEqual(events, 0)
    }
  }

  @Observable final class Model {
    var session = TypingSession(configuration: .words(4, rules: .init(freedomMode: true)),
      prompt: "amber\nbirch\ncedar\ndelta")
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
      }.frame(width: 360).foregroundStyle(.white).background(.black)
    }
  }

  func testProductionViewportActuallyDropsOldTextAndRebasesWithoutLosingInput() throws {
    let model = Model()
    let host = NSHostingView(rootView: Root(model: model))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 360, height: 135),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    defer { window.contentView = nil }
    func pump(_ seconds: Double = 0.04) {
      host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
    pump()
    model.session.insertBatch("amber\n", at: start); pump()
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
    model.session.insertBatch("birch\n", at: start.addingTimeInterval(1)); pump()
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
    pump(0.2); pump()
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 1)
    XCTAssertEqual(String(model.rendering.text.characters), "birch\ncedar\ndelta")
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first)
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 1)
    XCTAssertFalse(window.isVisible)
    if let directory = ProcessInfo.processInfo.environment["TYPEBAR_RETIREMENT_QA_IMAGE_DIRECTORY"],
      let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try bitmap.representation(using: .png, properties: [:])?.write(
        to: URL(fileURLWithPath: directory).appendingPathComponent("ordinary-pruned.png"))
    }
    model.session.insertBatch("cedar\n", at: start.addingTimeInterval(2)); pump(0.3); pump()
    XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 2)
    XCTAssertEqual(String(model.rendering.text.characters), "cedar\ndelta")
    let input = TypingInputView(frame: .zero)
    input.onDeleteWord = { model.session.deleteWordBackward(at: self.start.addingTimeInterval(3)) }
    input.onDelete = { model.session.deleteBackward(at: self.start.addingTimeInterval(4)) }
    input.doCommand(by: #selector(NSResponder.deleteWordBackward(_:)))
    input.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
    XCTAssertEqual(model.session.typed, "amber\nbirch\n")
    XCTAssertEqual(model.session.prompt, "amber\nbirch\ncedar\ndelta")
    pump()
    XCTAssertFalse(String(model.rendering.text.characters).contains("amber"))
  }

  func testCompletePinnedDeletionAndLineTimingMatchNativePolicies() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    struct Case: Decodable { let freedom: Bool, confidence: String, correct: Bool, empty: Bool, present: Bool, prevented: Bool }
    struct HardCase: Decodable { let mode: String, present: Bool, returned: Bool }
    struct Step: Decodable { let activeWordIndex: Int, before: Int, during: Int, after: Int }
    struct Sequence: Decodable { let smooth: Bool, perRow: Int, rowHeight: Int, steps: [Step] }
    struct Evidence: Decodable { let sequences: [Sequence], cases: [Case], hardCases: [HardCase] }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      project.appendingPathComponent("Scripts/check-source-word-retirement.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let evidence = try JSONDecoder().decode(Evidence.self, from: data)
    XCTAssertEqual(evidence.cases.count, 32); XCTAssertEqual(evidence.hardCases.count, 8)
    for item in evidence.cases {
      for wholeWord in [false, true] {
        let confidence: ConfidenceMode = item.confidence == "max" ? .maximum : item.confidence == "on" ? .on : .off
        var session = TypingSession(configuration: .words(4,
          rules: .init(freedomMode: item.freedom, confidenceMode: confidence)), prompt: "ab cd tail end")
        session.insertBatch((item.correct ? "ab " : "ax ") + (item.empty ? "" : "c"), at: start)
        if !item.present {
          session.retirePromptWords(.init(attemptID: session.automaticInputAttemptID, firstRetainedWordIndex: 1))
        }
        let before = session.typed
        if wholeWord { session.deleteWordBackward(at: start.addingTimeInterval(1)) }
        else { session.deleteBackward(at: start.addingTimeInterval(1)) }
        XCTAssertEqual(session.typed == before, item.prevented)
      }
    }
    for item in evidence.hardCases {
      let mode: DeleteOnErrorMode = item.mode == "letter_hard" ? .letterHard
        : item.mode == "word_hard" ? .wordHard : item.mode == "word" ? .word : .letter
      var session = TypingSession(configuration: .words(4, rules: .init(deleteOnErrorMode: mode)),
        prompt: "ab cd tail end")
      session.insertBatch("ab ", at: start)
      if !item.present {
        session.retirePromptWords(.init(attemptID: session.automaticInputAttemptID, firstRetainedWordIndex: 1))
      }
      session.insert("x", at: start.addingTimeInterval(1))
      XCTAssertEqual(session.completedWordCount == 0, item.returned)
    }
    XCTAssertEqual(evidence.sequences.count, 12)
    for sequence in evidence.sequences {
      let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 360, height: 135))
      let document = Document(frame: .init(x: 0, y: 0, width: 360, height: 700))
      scroll.documentView = document
      let follower = PromptAutoScrollView(frame: document.bounds); document.addSubview(follower)
      let font = NSFont.monospacedSystemFont(ofSize: sequence.rowHeight == 25 ? 14 : sequence.rowHeight == 45 ? 28 : 40, weight: .medium)
      let spacing: CGFloat = sequence.rowHeight == 25 ? 8 : 12
      let text = AttributedString(Array(repeating: Array(repeating: "aa", count: sequence.perRow).joined(separator: " "), count: 6).joined(separator: "\n"))
      let starts = (0..<(sequence.perRow * 6)).map { $0 * 3 }, id = UUID()
      var retired = 0
      func update(_ index: Int) {
        follower.update(text: text, characterOffset: starts[index], font: font, lineSpacing: spacing,
          isRightToLeft: false, lineScroll: .init(attemptID: id, activeWordID: starts[index],
            characterOffsets: Dictionary(uniqueKeysWithValues: starts.map { ($0, $0) }),
            smoothScroll: sequence.smooth, reducesMotion: false,
            words: starts.enumerated().map { .init(index: $0.offset, glyphID: $0.element) },
            onRetire: { retired = $0.firstRetainedWordIndex }))
        RunLoop.main.run(until: Date().addingTimeInterval(0.005))
      }
      update(0)
      for step in sequence.steps {
        update(step.activeWordIndex)
        XCTAssertEqual(retired, step.during)
        RunLoop.main.run(until: Date().addingTimeInterval(sequence.smooth ? 0.15 : 0.001))
        XCTAssertEqual(retired, step.after)
      }
    }
  }
}
