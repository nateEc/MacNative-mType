import XCTest

final class PromptRenderSnapshotTests: XCTestCase {
  func testPracticePanelSharesOneSynchronousRenderingWithoutCachingLiveProviders() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let begin = try XCTUnwrap(source.range(of: "private var typingPanel:"))
    let end = try XCTUnwrap(source.range(of: "NativeTypingInput(", range: begin.upperBound..<source.endIndex))
    let panel = String(source[begin.lowerBound..<end.lowerBound])
    XCTAssertEqual(panel.components(separatedBy: "renderedPrompt").count - 1, 1)
    XCTAssertTrue(panel.contains("let rendering = renderedPrompt"))
    XCTAssertTrue(panel.contains("text: rendering.text"))
    XCTAssertTrue(panel.contains("&& rendering.compositionTextMap == nil"))
    XCTAssertTrue(panel.contains("|| rendering.compositionTextMap != nil"))
    XCTAssertEqual(panel.components(separatedBy: "practicePrompt(rendering: rendering)").count - 1, 2)
    XCTAssertTrue(source.contains("private func practicePrompt(rendering: PromptRendering)"))
    XCTAssertTrue(source.contains("latestRendering: { renderedPrompt }"), "Native callbacks must still read fresh state")
    XCTAssertTrue(source.contains("let latest = renderedPrompt(for: current, composition: marked)"))
  }

  func testProductionUsesCapturedStyleAndSharedGlyphPainter() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let begin = try XCTUnwrap(source.range(of: "private func renderedPrompt(for session:"))
    let end = try XCTUnwrap(source.range(of: "private var completedPromptColor", range: begin.upperBound..<source.endIndex))
    let render = String(source[begin.lowerBound..<end.lowerBound])
    XCTAssertTrue(render.contains("let activeTheme = self.activeTheme"))
    XCTAssertTrue(render.contains("let style = PromptRenderStyle(theme: activeTheme"))
    XCTAssertTrue(render.contains("return PromptRenderPlan(session: session, composition: composition, style: style).render()"))
    let plan = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/PromptRenderPlan.swift"),
      encoding: .utf8)
    XCTAssertTrue(plan.contains("let sessionPolicy: PromptRenderSessionPolicy"))
    XCTAssertTrue(plan.contains("var painter = GlyphPainter(plan: self)"))
    XCTAssertFalse(plan.contains("settings."))
  }
}
