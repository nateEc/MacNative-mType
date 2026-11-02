import AppKit
import XCTest
@testable import Typebar

@MainActor final class PromptViewportCaretResolutionTests: XCTestCase {
  private let date = Date(timeIntervalSinceReferenceDate: 920_500_000)

  private func assertCanonical(_ session: TypingSession, file: StaticString = #filePath,
    line: UInt = #line) throws {
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session), file: file, line: line)
    let resolved = try XCTUnwrap(directory.resolveCaret(session: session), file: file, line: line)
    XCTAssertEqual(resolved.glyphIndex, session.promptCaretGlyphIndex, file: file, line: line)
  }

  func testOneTargetCaretMatchesCanonicalAcrossInputDeletionAndVisibilityRules() throws {
    let configurations: [TestConfiguration] = [.words(4),
      .words(4, rules: .init(blindMode: true)),
      .words(4).with(modifiers: [.memory]), .words(4).with(modifiers: [.simonSays]),
      .words(4).with(modifiers: [.readAheadEasy]), .words(4).with(modifiers: [.readAheadHard]),
      .words(4).with(modifiers: [.focusCurrentWord]), .words(4).with(modifiers: [.focusNextWord])]
    for configuration in configurations {
      var session = TypingSession(configuration: configuration, prompt: "oak ash\nelm pine")
      try assertCanonical(session)
      for (index, input) in ["o", "x", "\u{8}", "ak "].enumerated() {
        if input == "\u{8}" { session.deleteBackward(at: date.addingTimeInterval(Double(index))) }
        else { session.insertBatch(input, at: date.addingTimeInterval(Double(index))) }
        try assertCanonical(session)
      }
    }
  }

  func testProviderFieldReturnsAndEmptyFieldsUseLiteralWordOrdinals() throws {
    let fields = ["north\nsouth ", "", "harbor  ", "tail"]
    for modifier in [TestModifier.focusCurrentWord, .readAheadEasy, .memory] {
      var session = TypingSession(configuration: .words(4).with(modifiers: [modifier]),
        prompt: fields.joined(), sourceFields: fields)
      try assertCanonical(session)
      session.insert("n", at: date)
      try assertCanonical(session)
      session.insertBatch("orth\n", at: date.addingTimeInterval(1))
      try assertCanonical(session)
    }
    var blind = TypingSession(configuration: .words(4, rules: .init(blindMode: true)),
      prompt: "oak ash elm pine")
    blind.insertBatch("o ", at: date)
    try assertCanonical(blind)
    var rules = blind.configuration.rules; rules.blindMode = false
    blind.synchronizeLiveInputRules(rules)
    try assertCanonical(blind)
  }

  func testHiddenCurrentTargetIsResolvedWithoutInventingAnAnchor() throws {
    for modifier in [TestModifier.memory, .simonSays, .readAheadEasy, .readAheadHard] {
      var session = TypingSession(configuration: .words(3).with(modifiers: [modifier]),
        prompt: "oak ash elm")
      session.insert("o", at: date)
      let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
      let resolved = try XCTUnwrap(directory.resolveCaret(session: session))
      XCTAssertNil(resolved.glyphIndex)
      XCTAssertNil(session.promptCaretGlyphIndex)
    }
  }

  func testUnsupportedStoppedExtraAndTerminalInputKeepCanonicalFallback() throws {
    var stopped = TypingSession(configuration: .words(3,
      rules: .init(stopOnErrorMode: .letter)), prompt: "oak ash elm")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: stopped))
    stopped.insertBatch("x", at: date)
    XCTAssertNil(directory.resolveCaret(session: stopped))
    var extra = TypingSession(configuration: .words(3), prompt: "oak ash elm")
    let extraDirectory = try XCTUnwrap(PromptViewportTargetDirectory(session: extra))
    extra.insertBatch("oakx", at: date)
    XCTAssertNil(extraDirectory.resolveCaret(session: extra))
    extra.bailOut(at: date.addingTimeInterval(1))
    XCTAssertNil(extraDirectory.resolveCaret(session: extra))
    XCTAssertNil(extraDirectory.resolveCaret(session: extra.repeatedAttempt()))
  }

  func testRepeatedHundredThousandWordInputSnapshotsAvoidWholeTargetCaretWork() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["TYPEBAR_ENDURANCE_TESTS"] == "1",
      "Run explicitly with TYPEBAR_ENDURANCE_TESTS=1")
    let count = 100_001
    var session = TypingSession(configuration: .words(count),
      prompt: Array(repeating: "oak", count: count).joined(separator: " "))
    session.insert("o", at: Date(timeIntervalSinceReferenceDate: 920_500_000))
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    let style = PromptRenderStyle(theme: .init(background: .white, panel: .white,
      accent: .blue, colorScheme: .light))
    _ = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 800, font: font))
    let start = ProcessInfo.processInfo.systemUptime
    var snapshots: [PromptViewportFieldLayoutSequence] = []
    for _ in 0..<16 {
      snapshots.append(try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
        directory: directory, style: style, width: 800, font: font)))
    }
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    XCTAssertEqual(snapshots.count, 16)
    print("VIEWPORT CARET SNAPSHOTS words=\(count) count=16 elapsed=\(elapsed)")
    XCTAssertLessThan(elapsed, 1,
      "A one-character snapshot must not reconstruct 400,003 target glyphs for its caret")
  }
}
