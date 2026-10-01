import AppKit
import SwiftUI
import XCTest
@testable import Typebar

final class PromptExtraLayoutTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  func testActiveExtraAppearsInsideItsWordBeforeThePendingSeparator() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("abcx", at: start)
    let rendering = render(session)
    XCTAssertEqual(String(rendering.text.characters), "abcx bay cedar")
    XCTAssertEqual(rendering.characterOffset(forGlyphAt: 3), 4)
    XCTAssertEqual(rendering.characterOffset(forGlyphAt: 4), 5)
    XCTAssertEqual(displayText(session), "abcx bay cedar")
    XCTAssertEqual(session.promptGlyphs[3].state, .current)
  }

  func testMultipleCommittedWordsKeepTheirOwnExtrasAndLaterCaretAlignment() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("abcx bayyz ", at: start)
    let rendering = render(session)
    XCTAssertEqual(String(rendering.text.characters), "abcx bayyz cedar")
    XCTAssertEqual(rendering.characterOffset(forGlyphAt: 8), 11)
    XCTAssertEqual(rendering.characterOffset(forGlyphAt: 12), 15)
    XCTAssertEqual(displayText(session), "abcx bayyz cedar")
    XCTAssertEqual(session.promptGlyphs[8].state, .current)
    XCTAssertEqual(session.promptWordPresentations[0].extraGlyphIndices.count, 1)
    XCTAssertEqual(session.promptWordPresentations[1].extraGlyphIndices.count, 2)
  }

  func testHiddenExtrasOccupyNoRenderedSpaceButRemainRealErrors() {
    var session = TypingSession(configuration: .words(3, rules: .init(hideExtraLetters: true)),
      prompt: "abc bay cedar")
    session.insertBatch("abcx bayyz ", at: start)
    let rendering = render(session)
    XCTAssertEqual(String(rendering.text.characters), "abc bay cedar")
    XCTAssertEqual(rendering.characterOffset(forGlyphAt: 8), 8)
    XCTAssertEqual(displayText(session), "abc bay cedar")
    XCTAssertNil(rendering.characterOffset(forGlyphAt: session.prompt.count))
    XCTAssertEqual(session.errors, 3)
    XCTAssertEqual(session.typed, "abcx bayyz ")
  }

  func testBlindToggleRestoresExtrasInsideTheOriginalWord() {
    var session = TypingSession(configuration: .words(3, rules: .init(blindMode: true)),
      prompt: "abc bay cedar")
    session.insertBatch("abcx ", at: start)
    XCTAssertEqual(String(render(session).text.characters), "abc bay cedar")
    session.setBlindMode(false)
    XCTAssertEqual(String(render(session).text.characters), "abcx bay cedar")
    XCTAssertEqual(render(session).characterOffset(forGlyphAt: 4), 5)
    session.setBlindMode(true)
    XCTAssertEqual(String(render(session).text.characters), "abc bay cedar")
    XCTAssertEqual(session.errors, 1)
  }

  func testDeletingAnExtraRestoresDisplayOrderWithoutChangingTargetIndices() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("abcxy", at: start)
    XCTAssertEqual(String(render(session).text.characters), "abcxy bay cedar")
    session.deleteBackward(at: start.addingTimeInterval(0.1))
    XCTAssertEqual(String(render(session).text.characters), "abcx bay cedar")
    session.deleteBackward(at: start.addingTimeInterval(0.2))
    XCTAssertEqual(String(render(session).text.characters), "abc bay cedar")
    XCTAssertEqual(render(session).characterOffset(forGlyphAt: 3), 3)
    XCTAssertEqual(session.promptGlyphs[3].state, .current)
  }

  func testUnicodeOffsetsUseRenderedCharactersInsteadOfBytesOrUTF16Units() {
    var session = TypingSession(configuration: .words(2), prompt: "🙂e\u{301} bay")
    session.insertBatch("🙂e\u{301}Ω", at: start)
    let rendering = render(session)
    XCTAssertEqual(String(rendering.text.characters), "🙂e\u{301}Ω bay")
    XCTAssertEqual(rendering.characterOffset(forGlyphAt: 2), 3)
    XCTAssertEqual(rendering.characterOffset(forGlyphAt: 3), 4)
    XCTAssertEqual(session.promptGlyphs[2].state, .current)
    XCTAssertEqual(session.typed.count, 3)
    XCTAssertEqual(session.typed.utf16.count, 5)
  }

  @MainActor func testNativeCaretGeometryUsesTheShiftedRenderedOffset() throws {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("abcxy", at: start)
    let rendering = render(session)
    let font = NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)
    let size = CGSize(width: 800, height: 200)
    let actual = try XCTUnwrap(PromptCaretLayout.rect(
      in: rendering.text, characterOffset: try XCTUnwrap(rendering.characterOffset(forGlyphAt: 3)),
      containerSize: size, font: font, lineSpacing: 12, isRightToLeft: false))
    let expected = try XCTUnwrap(PromptCaretLayout.rect(
      in: AttributedString("abcxy bay cedar"), characterOffset: 5,
      containerSize: size, font: font, lineSpacing: 12, isRightToLeft: false))
    XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.001)
    XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.001)
  }

  func testRenderFactoryKeepsCaretOffsetsAfterHintsAndMultiCharacterComposition() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("axcx", at: start)
    let glyphs = session.promptGlyphs
    let rendering = PromptRendering.make(glyphs: glyphs, indices: indices(session, glyphs)) { _, glyph in
      if glyph.state == .current { return AttributedString("漢字") }
      if glyph.state == .incorrect { return AttributedString("b[x]") }
      return AttributedString(String(glyph.character))
    }
    XCTAssertEqual(String(rendering.text.characters), "ab[x]cx漢字bay cedar")
    XCTAssertEqual(rendering.characterOffset(forGlyphAt: 3), 7)
    XCTAssertEqual(rendering.characterOffset(forGlyphAt: 4), 9)
  }

  func testNoExtraAndZenPromptsKeepTheirExistingDisplayOrder() {
    let normal = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    XCTAssertEqual(String(render(normal).text.characters), normal.prompt)
    var zen = TypingSession(configuration: .init(mode: .zen, duration: nil,
      wordLimit: nil, difficulty: .normal, rules: .init()), prompt: "")
    zen.insertBatch("🙂 abc", at: start)
    XCTAssertEqual(String(render(zen).text.characters), "🙂 abc ")
    XCTAssertEqual(displayText(zen), "🙂 abc ")
  }

  func testConcealedExtrasKeepTheirWordSpaceWithoutExposingPresentationColors() {
    var session = TypingSession(configuration: TestConfiguration.words(2).with(modifiers: [.memory]),
      prompt: "abc bay")
    session.insertBatch("abcx", at: start)
    XCTAssertEqual(displayText(session), "abcx bay")
    XCTAssertEqual(render(session).characterOffset(forGlyphAt: 3), 4)
    XCTAssertTrue(session.promptGlyphsInDisplayOrder.allSatisfy { $0.state == .hidden })
    let appearances = PromptGlyphAppearance.plan(glyphs: session.promptGlyphs,
      words: session.promptWordPresentations, mode: .word, blindMode: false)
    XCTAssertTrue(appearances.allSatisfy { $0.color == .hidden && !$0.hasErrorUnderline })
  }

  func testCommittedExtraSharesTheWordUnderlineBeforeTheSeparator() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("abcx ", at: start)
    let glyphs = session.promptGlyphs
    let appearances = PromptGlyphAppearance.plan(glyphs: glyphs,
      words: session.promptWordPresentations, mode: .letter, blindMode: false)
    let rendering = PromptRendering.make(glyphs: glyphs, indices: indices(session, glyphs)) { index, glyph in
      var text = AttributedString(String(glyph.character))
      appearances[index].applyErrorUnderline(to: &text, errorColor: .pink)
      return text
    }
    XCTAssertEqual(String(rendering.text.characters), "abcx bay cedar")
    for offset in 0..<6 {
      let lower = rendering.text.characters.index(rendering.text.startIndex, offsetBy: offset)
      let upper = rendering.text.characters.index(after: lower)
      XCTAssertEqual(rendering.text[lower..<upper].underlineStyle,
        offset < 4 ? Text.LineStyle(color: .pink) : nil)
    }
  }

  func testCurrentReturnMarkerAndFollowingLineIncludeTheExtraWidth() {
    var session = TypingSession(configuration: .words(3), prompt: "abc\nbay cedar")
    session.insertBatch("abcx", at: start)
    let rendering = render(session)
    XCTAssertEqual(String(rendering.text.characters), "abcx↵\nbay cedar")
    XCTAssertEqual(rendering.characterOffset(forGlyphAt: 3), 4)
    XCTAssertEqual(rendering.characterOffset(forGlyphAt: 4), 6)
  }

  func testNoSpaceRetainedWordBoundariesRemainLogicalRatherThanDisplayIndices() {
    var session = TypingSession(configuration: TestConfiguration.words(2).with(modifiers: [.noSpaces]),
      prompt: "abcbay", noSpaceWordEndIndices: [3, 6], noSpaceTargetWords: ["abc", "bay"])
    session.insertBatch("axc", at: start)
    XCTAssertEqual(displayText(session), "abcbay")
    XCTAssertEqual(render(session).characterOffset(forGlyphAt: 3), 3)
    XCTAssertEqual(session.promptWordPresentations.map(\.range), [0..<3, 3..<6])
  }

  func testDisplayTraversalCannotChangeResultsArchivesOrReplay() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "abc bay cedar")
    session.insertBatch("abcx ", at: start)
    var control = session
    _ = render(session)
    _ = session.promptGlyphsInDisplayOrder
    _ = PracticeTapePolicy.anchorCharacterIndex(session: session, rendering: render(session), mode: .letter)
    session.tick(at: start.addingTimeInterval(1))
    control.tick(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result(at: start.addingTimeInterval(1)))
    let controlResult = try XCTUnwrap(control.result(at: start.addingTimeInterval(1)))
    // Each result projection intentionally allocates a new identity. Compare
    // every portable field after replacing only that generated test identity.
    var controlJSON = try XCTUnwrap(JSONSerialization.jsonObject(
      with: JSONEncoder().encode(controlResult)) as? [String: Any])
    controlJSON["id"] = result.id.uuidString
    let normalizedControl = try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONSerialization.data(withJSONObject: controlJSON))
    XCTAssertEqual(result, normalizedControl)
    let decoded = try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONEncoder().encode(result))
    XCTAssertEqual(decoded, result)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: decoded).portableResult), result)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
      through: result.finishedAt.timeIntervalSince(result.startedAt)), session.typed)
    XCTAssertEqual(displayText(session.repeatedAttempt()), session.prompt)
  }

  func testLongLayoutTraversalIsBoundedAndContainsEachLogicalGlyphExactlyOnce() {
    var session = TypingSession(configuration: .words(8_001),
      prompt: String(repeating: "abc ", count: 8_000) + "bay")
    session.insertBatch("abcxy ", at: start)
    let glyphs = session.promptGlyphs
    let before = Date()
    let order = indices(session, glyphs)
    XCTAssertLessThan(Date().timeIntervalSince(before), 5, "Traversal guard, not full rendering or frame rate")
    XCTAssertEqual(order.count, glyphs.count)
    XCTAssertEqual(Set(order), Set(glyphs.indices))
    XCTAssertEqual(String(order.prefix(6).map { glyphs[$0].character }), "abcxy ")
    XCTAssertEqual(order.firstIndex(of: 4), 6)
  }

  private func render(_ session: TypingSession) -> PromptRendering {
    let glyphs = session.promptGlyphs
    return PromptRendering.make(glyphs: glyphs, indices: indices(session, glyphs)) { _, glyph in
      AttributedString(PromptControlCharacterPresentation.text(for: glyph.character, state: glyph.state))
    }
  }

  private func indices(_ session: TypingSession, _ glyphs: [TypingPromptGlyph]) -> [Int] {
    PromptGlyphLayout.indices(glyphs: glyphs, words: session.promptWordPresentations,
      hideExtraLetters: session.configuration.rules.hideExtraLetters)
  }

  private func displayText(_ session: TypingSession) -> String {
    String(session.promptGlyphsInDisplayOrder.map(\.character))
  }
}
