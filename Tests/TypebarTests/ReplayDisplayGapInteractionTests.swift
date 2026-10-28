@preconcurrency import AppKit
import XCTest
@testable import Typebar

final class ReplayDisplayGapInteractionTests: XCTestCase {
  func testClickTargetsAgainstCompletePinnedReplayAndDOMDelegation() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Letter: Decodable { let text: String; let extra, correct, incorrect: Bool }
    struct Field: Decodable { let error: Bool; let letters: [Letter] }
    struct Frame: Decodable { let word, position: Int; let fields: [Field] }
    struct Event: Decodable { let index: Int; let value, text: String; let correct, deletion: Bool? }
    struct Fixture: Decodable {
      let targets: [String]; let tape: [Event]
      let initial, marginClick, letterClick, extra, extraClick, deleted: Frame
      let extraTime, deleteTime: Double
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-replay-click.mjs").path, reference]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 4)
    func compare(_ native: FieldReplayPlan.Frame, _ source: Frame) {
      XCTAssertEqual(native.word, source.word); XCTAssertEqual(native.position, source.position)
      XCTAssertEqual(native.fields.count, source.fields.count)
      for (a, b) in zip(native.fields, source.fields) {
        XCTAssertEqual(a.isError, b.error)
        XCTAssertEqual(a.letters.map(\.text), b.letters.map(\.text))
        XCTAssertEqual(a.letters.map(\.extra), b.letters.map(\.extra))
        XCTAssertEqual(a.letters.map(\.correct), b.letters.map(\.correct))
        XCTAssertEqual(a.letters.map(\.incorrect), b.letters.map(\.incorrect))
      }
    }
    for fixture in fixtures {
      let gap = fixture.targets[0].hasSuffix(" ") ? nil : [0]
      let directory = ResultTargetWordDirectory(words: fixture.targets, noSpace: false, displayGaps: gap)
      let events = fixture.tape.enumerated().map { index, event in
        TypingReplayEvent(offset: Double(index), kind: event.deletion == true ? .delete : .insert,
          text: event.text, forceError: event.correct == false, inputField: .init(index: event.index, value: event.value))
      }
      let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: directory.displayWords.joined(), events: events,
        configuration: .words(2), targetWordDirectory: directory))
      compare(plan.initialFrame, fixture.initial); compare(plan.initialFrame, fixture.marginClick)
      let clicked = try XCTUnwrap(plan.seek(.init(word: 1, position: 0)))
      compare(clicked.frame, fixture.letterClick)
      compare(plan.frame(through: fixture.extraTime), fixture.extra)
      let extra = try XCTUnwrap(plan.seek(.init(word: 0, position: fixture.targets[0].unicodeScalars.count)))
      compare(extra.frame, fixture.extraClick)
      compare(plan.frame(through: fixture.deleteTime), fixture.deleted)
      let initial = plan.initialFrame.presentation
      let reachable = initial.reachableIndices(upTo: plan.maximumSeekCoordinate)
      XCTAssertTrue(initial.displayGapIndices.isDisjoint(with: reachable))
      XCTAssertEqual(reachable.count, initial.glyphs.count - initial.displayGapIndices.count)
      var resumed = clicked.frame
      XCTAssertFalse(plan.advance(&resumed, through: Double(events.count)).isEmpty)
      XCTAssertEqual(resumed, plan.frame(through: Double(events.count)))
    }
  }

  private func plan() throws -> FieldReplayPlan {
    let directory = ResultTargetWordDirectory(words: ["ab", "cd"], noSpace: false, displayGaps: [0])
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "a", inputField: .init(index: 0, value: "a")),
      .init(offset: 1, kind: .insert, text: "b", inputField: .init(index: 0, value: "ab")),
      .init(offset: 2, kind: .insert, text: " ", inputField: .init(index: 0, value: "ab ")),
      .init(offset: 3, kind: .delete, text: "", inputField: .init(index: 0, value: "ab")),
      .init(offset: 4, kind: .insert, text: "c", inputField: .init(index: 1, value: "c")),
      .init(offset: 5, kind: .insert, text: "d", inputField: .init(index: 1, value: "cd"))]
    return try XCTUnwrap(FieldReplayPlan.make(prompt: "ab cd", events: events,
      configuration: .words(2), targetWordDirectory: directory))
  }

  func testDisplayGapCannotBeSelectedButRealExtraSpaceCan() throws {
    let plan = try plan()
    let initial = plan.initialFrame.presentation
    XCTAssertEqual(initial.text, "ab cd")
    XCTAssertEqual(initial.reachableIndices(upTo: plan.maximumSeekCoordinate), [0, 1, 3, 4])
    XCTAssertEqual(initial.displayGapIndices, [2])
    XCTAssertNil(initial.selectedIndex(for: .init(word: 0, position: 2)))
    let extra = plan.frame(through: 2).presentation
    XCTAssertEqual(extra.text, "ab cd")
    XCTAssertEqual(extra.glyphs[2].state, .extra)
    XCTAssertTrue(extra.reachableIndices(upTo: plan.maximumSeekCoordinate).contains(2))
    XCTAssertTrue(extra.displayGapIndices.isEmpty)
    XCTAssertEqual(extra.selectedIndex(for: .init(word: 0, position: 2)), 2)
    let deleted = plan.frame(through: 3).presentation
    XCTAssertEqual(deleted.text, "ab cd")
    XCTAssertFalse(deleted.reachableIndices(upTo: plan.maximumSeekCoordinate).contains(2))
    XCTAssertNil(deleted.selectedIndex(for: .init(word: 0, position: 2)))
  }

  @MainActor func testNativeMouseHitIgnoresDisplayGapAndSelectsActualLetters() throws {
    let plan = try plan(), presentation = plan.initialFrame.presentation
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 140),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 140))
    let picker = ReplayCharacterTextView()
    scroll.documentView = picker; window.contentView = scroll
    var selected: [Int] = []
    picker.onSelect = { selected.append($0) }
    func render(_ presentation: FieldReplayPlan.Presentation) {
      picker.update(text: presentation.text, reachableIndices: presentation.reachableIndices(upTo: plan.maximumSeekCoordinate),
        selectedIndex: nil, glyphs: presentation.glyphs, errorIndices: presentation.errorIndices)
      scroll.layoutSubtreeIfNeeded()
    }
    func click(_ index: Int) throws {
      let layout = try XCTUnwrap(picker.layoutManager), container = try XCTUnwrap(picker.textContainer)
      layout.ensureLayout(for: container)
      let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
      let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
      XCTAssertGreaterThan(rect.width, 0)
      let point = picker.convert(NSPoint(x: rect.midX + picker.textContainerInset.width,
        y: rect.midY + picker.textContainerInset.height), to: nil)
      let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
        eventNumber: 1, clickCount: 1, pressure: 1))
      picker.mouseDown(with: event)
    }
    render(presentation)
    try click(2); XCTAssertTrue(selected.isEmpty)
    try click(3); XCTAssertEqual(selected, [3])
    render(plan.frame(through: 2).presentation)
    try click(2); XCTAssertEqual(selected, [3, 2])
    render(plan.frame(through: 3).presentation)
    try click(2); XCTAssertEqual(selected, [3, 2])
    XCTAssertFalse(window.isVisible)
  }
}
