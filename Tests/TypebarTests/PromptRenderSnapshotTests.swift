import XCTest

final class PromptRenderSnapshotTests: XCTestCase {
  func testProductionGlyphLoopUsesOneRenderLocalThemeAndCaretPolicy() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let begin = try XCTUnwrap(source.range(of: "private func renderedPrompt(for session:"))
    let end = try XCTUnwrap(source.range(of: "private var completedPromptColor", range: begin.upperBound..<source.endIndex))
    let render = String(source[begin.lowerBound..<end.lowerBound])
    let loop = try XCTUnwrap(render.range(of: "func renderGlyph("))
    let setup = String(render[..<loop.lowerBound])
    XCTAssertTrue(setup.contains("let activeTheme = self.activeTheme"))
    XCTAssertTrue(setup.contains("let usesIndependentPromptCarets = self.usesIndependentPromptCarets"))
    XCTAssertTrue(setup.contains("let paceGuideIndex = usesIndependentPromptCarets ? nil : self.paceGuideIndex"))
    XCTAssertTrue(setup.contains("promptTextColor(for: .completed, theme: activeTheme)"))
    XCTAssertTrue(setup.contains("promptTextColor(for: .future, theme: activeTheme)"))
    XCTAssertTrue(setup.contains("let errorFeedbackColor = activeTheme.errorColor("))
    XCTAssertTrue(setup.contains("let extraInputFeedbackColor = activeTheme.extraInputColor("))
    let glyph = String(render[loop.lowerBound...])
    XCTAssertFalse(glyph.contains("self.activeTheme"))
    XCTAssertTrue(glyph.contains("applyCaret(to: &character, theme: activeTheme)"))
    XCTAssertTrue(glyph.contains("applyPaceCaret(to: &character, theme: activeTheme)"))
  }
}
