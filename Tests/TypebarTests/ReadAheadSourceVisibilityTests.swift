import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class ReadAheadSourceVisibilityTests: XCTestCase {
  struct Caret: Decodable { let wordIndex: Int; let letterIndex: Int }
  struct Fixture: Decodable {
    let words: [String]; let modifier: String; let active: Int; let entered: String
    let prefixInputs: [String]
    let priorCorrectClasses: [[Bool]]
    let firstRetained: Int; let removed: [Int]
    let highlight: String; let blind: Bool
    let caret: Caret; let hiddenFields: [Bool]
  }
  struct Key: Decodable { let key: String; let current: String; let target: String; let before: Bool; let after: Bool }
  struct ClassRetention: Decodable { let before: Bool; let after: Bool }
  struct Evidence: Decodable { let fixtures: [Fixture]; let keys: [Key]; let classRetention: [ClassRetention] }
  private let date = Date(timeIntervalSinceReferenceDate: 920_500_000)

  func evidence() throws -> Evidence {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned clean source")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-read-ahead-visibility.mjs").path,
      reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    return try JSONDecoder().decode(Evidence.self, from: data)
  }

  func testHiddenTargetInkAndIndependentCaretAgainstPinnedSelectorsAndController() throws {
    let fixtures = try evidence().fixtures
    XCTAssertEqual(fixtures.count, 816)
    let modifiers: [String: TestModifier] = ["read_ahead_easy": .readAheadEasy, "read_ahead": .readAhead,
      "read_ahead_hard": .readAheadHard, "simon_says": .simonSays]
    for fixture in fixtures {
      let fields = fixture.words.enumerated().map { $0.element + ($0.offset < fixture.words.count - 1 ? " " : "") }
      var session = TypingSession(configuration: .words(fields.count, rules: .init(blindMode: fixture.blind))
        .with(modifiers: [try XCTUnwrap(modifiers[fixture.modifier])]), prompt: fields.joined(), sourceFields: fields)
      session.insertBatch(fixture.prefixInputs.prefix(fixture.active).map { $0 + " " }.joined()
        + fixture.entered, at: date)
      if fixture.firstRetained > 0 {
        session.retirePromptWords(.init(attemptID: session.automaticInputAttemptID,
          firstRetainedWordIndex: fixture.firstRetained))
      }
      session.removeTapePromptWords(.init(attemptID: session.automaticInputAttemptID,
        wordIndices: Set(fixture.removed)))
      var style = PromptRenderStyle(theme: .init(background: .white, panel: .white,
        accent: .blue, colorScheme: .light))
      style.highlightMode = fixture.highlight == "off" ? .off : .letter
      let map = try XCTUnwrap(PromptRenderPlan(session: session, composition: "", style: style)
        .render().compositionTextMap)
      let cells = map.fieldRuns.flatMap(\.cells)
      let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
      var local: [PromptFieldTextRun.Cell]?
      if fixture.firstRetained == 0 && fixture.removed.isEmpty {
        local = try XCTUnwrap(PromptRenderPlan.renderIndependentFieldWindow(directory: directory,
          session: session, fields: 0..<directory.fieldCount, style: style)).flatMap(\.cells)
      }
      func hidden(_ text: AttributedString) throws -> Bool {
        let color = try XCTUnwrap(text.foregroundColor)
        return try XCTUnwrap(NSColor(color).usingColorSpace(.deviceRGB)).alphaComponent < 0.001
      }
      var offset = 0, actual: [Bool] = [], window: [Bool] = [], expected: [Bool] = []
      for (field, word) in fixture.words.enumerated() {
        if field < fixture.firstRetained || fixture.removed.contains(field) {
          XCTAssertFalse(cells.contains { (offset..<(offset + word.count)).contains($0.id) })
          offset += fields[field].count; continue
        }
        for (position, character) in word.enumerated() where !isPromptWordSeparator(character) {
          let id = offset + position
          actual.append(try hidden(XCTUnwrap(cells.first { $0.id == id }).text))
          if let local { window.append(try hidden(XCTUnwrap(local.first { $0.id == id }).text)) }
          let committedCorrect = field < fixture.active && fixture.priorCorrectClasses[field][position]
          let typed = committedCorrect
            || (field == fixture.active && position < fixture.entered.count)
          let correct = committedCorrect || (typed && fixture.entered.first == word.first)
          expected.append(fixture.hiddenFields[field]
            && (!typed || (fixture.highlight == "off" && (correct || fixture.blind))))
        }
        offset += fields[field].count
      }
      let label = "\(fixture.modifier) active=\(fixture.active) input=\(fixture.entered) highlight=\(fixture.highlight) blind=\(fixture.blind) first=\(fixture.firstRetained) removed=\(fixture.removed)"
      XCTAssertEqual(actual, expected, label)
      if local != nil { XCTAssertEqual(window, expected, label) }
      let caret = fields.prefix(fixture.caret.wordIndex).joined().count + fixture.caret.letterIndex
      XCTAssertEqual(session.promptCaretGlyphIndex, caret, label)
      if local != nil { XCTAssertEqual(directory.resolveCaret(session: session)?.glyphIndex, caret, label) }
      else { XCTAssertNil(directory.resolveCaret(session: session)) }
    }
  }

  func testRevealKeyStateAgainstCompletePinnedPreEditHandler() throws {
    let keys = try evidence().keys
    XCTAssertEqual(keys.count, 70)
    for modifier in [TestModifier.readAheadEasy, .readAhead, .readAheadHard] {
      for fixture in keys {
        var session = TypingSession(configuration: .words(3).with(modifiers: [modifier]),
          prompt: "oak \(fixture.target) elm")
        session.insertBatch("oak ", at: date)
        if fixture.before {
          session.insert("x", at: date)
          session.observeReadAheadKeyDown("Backspace")
          session.deleteBackward(at: date)
        }
        session.insertBatch(fixture.current, at: date)
        XCTAssertEqual(session.readAheadRevealEnabled, fixture.before)
        let typed = session.typed
        session.observeReadAheadKeyDown(fixture.key)
        XCTAssertEqual(session.readAheadRevealEnabled, fixture.after,
          "\(modifier) key=\(fixture.key) input=\(fixture.current) before=\(fixture.before)")
        XCTAssertEqual(session.typed, typed, "The source key handler does not perform the edit")
      }
    }
  }

  func testReadAheadClassRetentionMatchesWordRebuildAndRemainsPageLocal() throws {
    let records = try evidence().classRetention
    XCTAssertEqual(records.count, 2)
    for record in records {
      let page = PracticePageSessionStore()
      var state = page.state
      state.session = TypingSession(configuration: .words(3).with(modifiers: [.readAhead]), prompt: "oak ash elm")
      page.replace(state)
      state = page.state
      if record.before {
        state.session.insert("x", at: date)
        state.session.observeReadAheadKeyDown("Backspace")
        page.replace(state)
      }
      state = page.state
      state.session = state.session.repeatedAttempt()
      page.replace(state)
      XCTAssertEqual(page.state.session.readAheadRevealEnabled, record.after)
      XCTAssertFalse(PracticePageSessionStore().state.session.readAheadRevealEnabled)
    }
  }

  func testNativeLogicalBackspaceRunsBeforeDeletionAndRetirementStopsIt() throws {
    _ = NSApplication.shared
    let input = TypingInputView(frame: .zero)
    var session = TypingSession(configuration: .words(3).with(modifiers: [.readAhead]), prompt: "oak ash elm")
    session.insertBatch("oak x", at: date)
    var trace: [String] = []
    input.onLogicalKeyDown = { key in session.observeReadAheadKeyDown(key); trace.append(key) }
    input.onDelete = {
      XCTAssertTrue(session.readAheadRevealEnabled)
      session.deleteBackward(at: self.date); trace.append("deleted")
    }
    let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
      timestamp: 1, windowNumber: 0, context: nil, characters: "\u{7f}",
      charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51))
    input.keyDown(with: event)
    XCTAssertEqual(trace, ["Backspace", "deleted"])
    XCTAssertEqual(session.typed, "oak ")
    input.retirePageCallbacks()
    input.keyDown(with: event)
    XCTAssertEqual(trace, ["Backspace", "deleted"])
  }
}
