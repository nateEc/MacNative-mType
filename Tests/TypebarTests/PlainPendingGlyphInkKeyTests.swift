import XCTest
@testable import Typebar

final class PlainPendingGlyphInkKeyTests: XCTestCase {
  func testOnlyOrdinarySingleScalarPendingASCIIIsReusable() {
    let pending = TypingPromptGlyph(character: "a", state: .pending)
    let future = PromptGlyphAppearance(color: .future)
    let key = PlainPendingGlyphInkKey.make(glyph: pending, appearance: future,
      isCompleted: false, hasSpecialPresentation: false)
    XCTAssertEqual(key?.ascii, 97)
    XCTAssertEqual(key?.color, .future)
    XCTAssertNil(PlainPendingGlyphInkKey.make(glyph: pending, appearance: future,
      isCompleted: true, hasSpecialPresentation: false))
    XCTAssertNil(PlainPendingGlyphInkKey.make(glyph: pending, appearance: future,
      isCompleted: false, hasSpecialPresentation: true))
    for character: Character in [" ", "\n", "\t", "\r\n", "é", "e\u{301}", "候"] {
      XCTAssertNil(PlainPendingGlyphInkKey.make(glyph: .init(character: character, state: .pending),
        appearance: future, isCompleted: false, hasSpecialPresentation: false))
    }
    for state: TypingPromptCharacterState in [.current, .correct, .incorrect, .hidden, .extra] {
      XCTAssertNil(PlainPendingGlyphInkKey.make(glyph: .init(character: "a", state: state),
        appearance: future, isCompleted: false, hasSpecialPresentation: false))
    }
    XCTAssertNil(PlainPendingGlyphInkKey.make(glyph: .init(character: "a", state: .pending, typedCharacter: "x"),
      appearance: future, isCompleted: false, hasSpecialPresentation: false))
  }

  func testAppearanceAndInkDifferencesHaveDistinctKeys() {
    let glyph = TypingPromptGlyph(character: "a", state: .pending)
    let future = PlainPendingGlyphInkKey.make(glyph: glyph,
      appearance: .init(color: .future), isCompleted: false, hasSpecialPresentation: false)
    let completed = PlainPendingGlyphInkKey.make(glyph: glyph,
      appearance: .init(color: .completed), isCompleted: false, hasSpecialPresentation: false)
    let underlined = PlainPendingGlyphInkKey.make(glyph: glyph,
      appearance: .init(color: .future, hasErrorUnderline: true),
      isCompleted: false, hasSpecialPresentation: false)
    let differentCharacter = PlainPendingGlyphInkKey.make(glyph: .init(character: "b", state: .pending),
      appearance: .init(color: .future), isCompleted: false, hasSpecialPresentation: false)
    XCTAssertNotEqual(future, completed)
    XCTAssertNotEqual(future, underlined)
    XCTAssertNotEqual(future, differentCharacter)
  }
}
