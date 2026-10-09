import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptInputWrapTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 913_100_000)
  private func saved(_ session: TypingSession) throws -> CompletedTestResult {
    var ended = session
    ended.failForTimerHealth(at: start.addingTimeInterval(2))
    return try XCTUnwrap(ended.result())
  }

  func testBatchChecksEachExtraBeforeScoringFeedbackAndReplay() throws {
    var session = TypingSession(configuration: .words(3), prompt: "aa bb cc")
    var candidates: [String] = []
    let admission = TypingInputWrapAdmission { _, units in
      let text = String(decoding: units, as: UTF16.self)
      candidates.append(text)
      return text.count > 3
    }
    let feedback = session.insertBatch("aaxyz bb", at: start, wrapAdmission: admission)
    XCTAssertEqual(candidates, ["aax", "aaxy", "aaxz"])
    XCTAssertEqual(session.typed, "aax bb")
    XCTAssertEqual(feedback, [true])
    XCTAssertEqual(try saved(session).inputMetrics?.totalAttempts, 6)
    XCTAssertEqual(session.errors, 1)
    XCTAssertEqual(try saved(session).replayEvents.filter { $0.kind == .insert }.map(\.text).joined(), "aax bb")
  }

  func testRejectedExtraIsNotRetainedOrReplayedAsStoppedInput() throws {
    var session = TypingSession(configuration: .words(2, rules: .init(stopOnErrorMode: .letter)),
      prompt: "aa bb")
    session.insertBatch("aa", at: start)
    let before = try saved(session).replayEvents
    let feedback = session.insertBatch("x", at: start.addingTimeInterval(1),
      wrapAdmission: .init { _, _ in true })
    XCTAssertEqual(feedback, [])
    XCTAssertEqual(session.typed, "aa")
    XCTAssertEqual(try saved(session).inputMetrics?.totalAttempts, 2)
    XCTAssertEqual(try saved(session).replayEvents, before)
    XCTAssertFalse(session.promptGlyphs.contains { $0.state == .extra })
  }

  private func rendering(_ session: TypingSession) -> PromptRendering {
    let glyphs = session.promptGlyphs
    return .make(glyphs: glyphs, indices: PromptGlyphLayout.indices(glyphs: glyphs,
      words: session.promptWordPresentations, hideExtraLetters: false,
      firstRetainedWordIndex: session.firstRetainedPromptWordIndex)) { _, glyph in
        AttributedString(PromptControlCharacterPresentation.plan(for: glyph, style: .off).text)
      }
  }

  private func geometry(_ session: TypingSession, candidate: String, columns: CGFloat,
    size: CGFloat = 28, rtl: Bool = false) -> Bool {
    let font = NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
    let unit = ("a" as NSString).size(withAttributes: [.font: font]).width
    return PromptInputWrapGeometry.rejects(session: session, candidate: Array(candidate.utf16),
      rendering: rendering(session), width: unit * columns, font: font, lineSpacing: 12, isRightToLeft: rtl)
  }

  func testWholeWordTopAndFirstWordHeightGrowthAreRejected() {
    for size: CGFloat in [18, 28, 42] {
      var moved = TypingSession(configuration: .words(3), prompt: "aa bb cc")
      moved.insertBatch("aa bb", at: start)
      XCTAssertTrue(geometry(moved, candidate: "bbx", columns: 5.2, size: size))
      XCTAssertFalse(geometry(moved, candidate: "bbx", columns: 8.2, size: size))
      XCTAssertTrue(geometry(moved, candidate: "bbx", columns: 5.2, size: size, rtl: true))
      XCTAssertFalse(geometry(moved, candidate: "bbx", columns: 8.2, size: size, rtl: true))
      var first = TypingSession(configuration: .words(2), prompt: "aaaa tail")
      first.insertBatch("aaaa", at: start)
      XCTAssertTrue(geometry(first, candidate: "aaaax", columns: 4.2, size: size))
      XCTAssertFalse(geometry(first, candidate: "aaaa", columns: 4.2, size: size))
    }
  }

  func testLegacyProbeDoesNotFuseTwoTemporarySurrogateLettersIntoOneEmoji() {
    var session = TypingSession(configuration: .words(2), prompt: "😀ab tail")
    session.insertBatch("😀ab", at: start)
    XCTAssertEqual(session.promptInputWrapSourceLetterCount, 3)
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)
    let fused = ("😀abb😀" as NSString).size(withAttributes: [.font: font]).width
    let separate = ("😀abb\u{FFFD}\u{FFFD}" as NSString).size(withAttributes: [.font: font]).width
    let advance = ("a" as NSString).size(withAttributes: [.font: font]).width
    XCTAssertGreaterThan(separate, fused)
    XCTAssertTrue(geometry(session, candidate: "😀ab😀", columns: (fused + separate) / 2 / advance))
  }

  func testActualGeometryFeedsBatchAdmissionAndRetiredPrefixCoordinates() {
    var session = TypingSession(configuration: .words(4), prompt: "aa bb cc dd")
    session.insertBatch("aa bb cc", at: start)
    session.retirePromptWords(.init(attemptID: session.automaticInputAttemptID, firstRetainedWordIndex: 1))
    let feedback = session.insertBatch("xx dd", at: start.addingTimeInterval(1),
      wrapAdmission: .init { current, candidate in
        self.geometry(current, candidate: String(decoding: candidate, as: UTF16.self), columns: 5.2)
      })
    XCTAssertEqual(session.typed, "aa bb cc dd")
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(feedback, [true])
    XCTAssertEqual(session.outcome, .completed)
  }

  func testSlowBlindHiddenHardAndZenBypassBeforeGeometry() {
    for rules in [InputRules(blindMode: true), .init(hideExtraLetters: true),
      .init(deleteOnErrorMode: .letterHard), .init(deleteOnErrorMode: .wordHard), .init()] {
      var calls = 0
      var session = TypingSession(configuration: .words(2, rules: rules), prompt: "aa bb")
      session.insertBatch("aax", at: start,
        wrapAdmission: .init(slowTimer: rules == InputRules()) { _, _ in calls += 1; return true })
      XCTAssertEqual(calls, 0)
    }
    var zen = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "")
    zen.insertBatch("aax", at: start, wrapAdmission: .init { _, _ in XCTFail("Zen must bypass"); return true })
    XCTAssertEqual(zen.typed, "aax")
  }

  func testOnlyGrowthIsProbedAndARealCommitStillAdvances() {
    var session = TypingSession(configuration: .words(3), prompt: "aa bb cc")
    var candidates: [String] = []
    session.insertBatch("aa\u{3000}bbx", at: start, wrapAdmission: .init { _, units in
      candidates.append(String(decoding: units, as: UTF16.self)); return true
    })
    XCTAssertEqual(candidates, ["bbx"])
    XCTAssertEqual(session.typed, "aa bb")
    // A callback must not leak from the completed platform operation.
    session.insertBatch("x", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "aa bbx")
    let restarted = session.repeatedAttempt()
    XCTAssertFalse(restarted.hasStarted)
  }

  func testUnicodeEligibilityUsesUTF16AndNewlineDisplayIncludesCommit() {
    var unicode = TypingSession(configuration: .words(2), prompt: "😀e\u{301} tail")
    var candidates: [[UInt16]] = []
    unicode.insertBatch("😀e\u{301}x", at: start, wrapAdmission: .init { _, units in
      candidates.append(units); return true
    })
    XCTAssertEqual(candidates, [Array("😀e\u{301}x".utf16)])
    XCTAssertEqual(unicode.typed, "😀e\u{301}")
    var multiline = TypingSession(configuration: .words(2), prompt: "aa\nbb")
    var called = 0
    multiline.insertBatch("aaxy", at: start, wrapAdmission: .init { _, _ in called += 1; return true })
    XCTAssertEqual(multiline.typed, "aax")
    XCTAssertEqual(called, 1)
  }

  func testStoppedCommitIsProbedButSoftDeletionDoesNotBypass() {
    for rules in [InputRules(stopOnErrorMode: .word), .init(stopOnErrorMode: .letter),
      .init(deleteOnErrorMode: .letter), .init(deleteOnErrorMode: .word)] {
      var session = TypingSession(configuration: .words(2, rules: rules), prompt: "aa bb")
      session.insertBatch("aa", at: start)
      var candidates: [String] = []
      session.insertBatch("x", at: start.addingTimeInterval(1), wrapAdmission: .init { _, units in
        candidates.append(String(decoding: units, as: UTF16.self)); return true
      })
      XCTAssertEqual(candidates, ["aax"])
      XCTAssertEqual(session.typed, "aa")
      XCTAssertEqual(session.errors, 0)
    }
    var word = TypingSession(configuration: .words(2, rules: .init(stopOnErrorMode: .word)), prompt: "aa bb")
    word.insertBatch("zz", at: start)
    var candidates: [String] = []
    word.insertBatch(" ", at: start.addingTimeInterval(1), wrapAdmission: .init { _, units in
      candidates.append(String(decoding: units, as: UTF16.self)); return true
    })
    XCTAssertEqual(candidates, ["zz "])
    XCTAssertEqual(word.typed, "zz")
  }

  func testTargetReturnDoesNotHideFurtherWordGrowthFromGeometry() {
    var session = TypingSession(configuration: .words(2), prompt: "aa\nbb")
    session.insertBatch("aax", at: start)
    XCTAssertTrue(geometry(session, candidate: "aaxy", columns: 4.2))
    XCTAssertFalse(geometry(session, candidate: "aaxy", columns: 8.2))
  }

  func testRecursiveReplacementAndDeferredAutomaticTabShareAdmission() throws {
    var ordinary = TypingSession(configuration: .words(2), prompt: "aa bb")
    ordinary.insertBatch("aa", at: start)
    var dots: [String] = []
    XCTAssertEqual(ordinary.insertBatch("…", at: start.addingTimeInterval(1), wrapAdmission: .init { _, units in
      dots.append(String(decoding: units, as: UTF16.self)); return true
    }), [])
    XCTAssertEqual(dots, ["aa.", "aa.", "aa."])
    XCTAssertEqual(try saved(ordinary).inputMetrics?.totalAttempts, 2)

    var code = TypingSession(configuration: .words(10, language: .codeSwift), prompt: "\t\tgo() tail")
    code.insertBatch("\tXgo()", at: start, defersAutomaticInput: true)
    XCTAssertTrue(code.hasPendingAutomaticInput)
    let before = try saved(code)
    var candidates: [[UInt16]] = []
    let admission = TypingInputWrapAdmission { _, units in candidates.append(units); return true }
    XCTAssertEqual(code.processNextAutomaticInput(for: UUID(), wrapAdmission: admission), [])
    XCTAssertTrue(candidates.isEmpty)
    XCTAssertEqual(code.processNextAutomaticInput(for: code.automaticInputAttemptID, wrapAdmission: admission), [])
    XCTAssertEqual(candidates, [Array("\tXgo()\t".utf16)])
    XCTAssertFalse(code.hasPendingAutomaticInput)
    XCTAssertEqual(try saved(code).replayEvents, before.replayEvents)
    XCTAssertEqual(try saved(code).inputMetrics, before.inputMetrics)
  }

  private struct Root: View {
    let layout: PromptInputWrapLayout
    var body: some View {
      Text("aa bb cc").frame(maxWidth: .infinity)
        .overlay { PromptInputWrapOverlay(layout: layout) }
    }
  }
  func testDetachedHostingTreeCannotSupplyStalePromptWidth() {
    let layout = PromptInputWrapLayout()
    let host = NSHostingView(rootView: Root(layout: layout))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 150, height: 60),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.04))
    XCTAssertNotNil(layout.width)
    window.contentView = nil
    XCTAssertNil(layout.width)
    XCTAssertFalse(window.isVisible)
    withExtendedLifetime(host) {}
  }
  func testMountedWidthResizeAndDetachWithoutOpeningAnApplication() throws {
    let layout = PromptInputWrapLayout()
    XCTAssertNil(layout.width)
    let host = NSHostingView(rootView: Root(layout: layout))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 150, height: 60),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.04))
    XCTAssertEqual(try XCTUnwrap(layout.width), 150, accuracy: 1)
    window.setContentSize(.init(width: 260, height: 60))
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.04))
    XCTAssertEqual(try XCTUnwrap(layout.width), 260, accuracy: 1)
    XCTAssertFalse(window.isVisible)
    layout.view?.removeFromSuperview()
    XCTAssertNil(layout.width)
    window.contentView = nil
  }

  func testFullPinnedBeforeInputAndHelperModulesMatchEngineAdmission() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    struct Changes: Decodable {
      var mode: String?, blindMode: Bool?, hideExtraLetters: Bool?, slow: Bool?
      var deleteOnError: String?, stopOnError: String?, strictSpace: Bool?
    }
    struct Fixture: Decodable {
      let changes: Changes, input: String, data: String, growth: String, probes: Int
      let candidate: String?, prevented: Bool
    }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      project.appendingPathComponent("Scripts/check-source-input-wrap.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 456)
    for fixture in fixtures {
      let changes = fixture.changes
      let deletes: DeleteOnErrorMode = switch changes.deleteOnError {
      case "letter": .letter
      case "word": .word
      case "letter_hard": .letterHard
      case "word_hard": .wordHard
      default: .off
      }
      let stop: StopOnErrorMode = changes.stopOnError == "letter" ? .letter
        : changes.stopOnError == "word" ? .word : .off
      let rules = InputRules(strictSpace: changes.strictSpace ?? false, stopOnErrorMode: stop,
        deleteOnErrorMode: deletes, hideExtraLetters: changes.hideExtraLetters ?? false,
        blindMode: changes.blindMode ?? false)
      let zen = changes.mode == "zen"
      let configuration = TestConfiguration(mode: zen ? .zen : .words, duration: nil,
        wordLimit: zen ? nil : 2, difficulty: .normal, rules: rules)
      var session = TypingSession(configuration: configuration, prompt: zen ? "" : "ab \ntail")
      session.insertBatch(fixture.input, at: start)
      XCTAssertEqual(session.typed, fixture.input)
      let before = session.typed
      var candidates: [String] = []
      session.insertBatch(fixture.data, at: start.addingTimeInterval(1), wrapAdmission: .init(
        slowTimer: changes.slow ?? false) { _, units in
          candidates.append(String(decoding: units, as: UTF16.self))
          return fixture.growth != "none"
        })
      XCTAssertEqual(candidates.count, fixture.probes, "\(fixture.input.debugDescription) / \(fixture.data.debugDescription) / \(changes)")
      XCTAssertEqual(candidates.first, fixture.candidate)
      if fixture.probes > 0, fixture.prevented { XCTAssertEqual(session.typed, before) }
    }
  }
}
