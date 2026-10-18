import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptRenderPlanTests: XCTestCase {
  private let theme = ResolvedTheme(background: .white, panel: .white, accent: .blue,
    colorScheme: .light)

  func testCapturedStyleAndCandidateSessionRemainStableAcrossBatches() async throws {
    let candidate = TypingSession(configuration: .words(3).with(modifiers: [.aslVisual]),
      prompt: "é👩‍💻 alpha\nβeta")
    var style = PromptRenderStyle(theme: theme, fontSize: 31, caretStyle: .bar,
      paceCaretStyle: .underline, highlightMode: .word)
    let plan = PromptRenderPlan(session: candidate, composition: nil, style: style)
    let expected = plan.render()
    style.caretStyle = .off
    style.highlightMode = .off
    style.fontSize = 12
    var batches: [Int] = []
    let actual = try await plan.renderCooperatively(batchSize: 2,
      didRender: { batches.append($0) })
    XCTAssertEqual(actual.text, expected.text)
    XCTAssertEqual(actual.glyphCharacterOffsets, expected.glyphCharacterOffsets)
    XCTAssertEqual(actual.structuralNewlineOffsets, expected.structuralNewlineOffsets)
    XCTAssertEqual(batches.last, candidate.promptGlyphs.count)
    let changedPlan = PromptRenderPlan(session: candidate, composition: nil, style: style)
    XCTAssertNotEqual(changedPlan.render().text, expected.text,
      "The captured plan must keep the old appearance even when a new plan would change it")
  }

  func testCompositionStylesShareOnePainterForSyncAndCooperativeRendering() async throws {
    let candidate = TypingSession(configuration: .words(3), prompt: "alpha beta\n🙂")
    for display in CompositionDisplayStyle.allCases {
      let style = PromptRenderStyle(theme: theme, fontSize: 28,
        compositionDisplayStyle: display, highlightMode: .nextWord)
      let plan = PromptRenderPlan(session: candidate, composition: "候选", style: style)
      let expected = plan.render()
      let actual = try await plan.renderCooperatively(batchSize: 2)
      XCTAssertEqual(actual.text, expected.text)
      XCTAssertEqual(actual.glyphCharacterOffsets, expected.glyphCharacterOffsets)
      XCTAssertEqual(actual.compositionTextMap?.cellRanges, expected.compositionTextMap?.cellRanges)
      XCTAssertEqual(actual.compositionTextMap?.inkRanges, expected.compositionTextMap?.inkRanges)
    }
  }

  func testCooperativePlanPreparationMatchesSynchronousRendering() async throws {
    let candidate = TypingSession(configuration: .words(3), prompt: "a \u{301}b 🙂 tail")
    for style in CompositionDisplayStyle.allCases {
      let appearance = PromptRenderStyle(theme: theme, compositionDisplayStyle: style)
      let expected = PromptRenderPlan(session: candidate, composition: "候选", style: appearance).render()
      let plan = try await PromptRenderPlan.prepareCooperatively(session: candidate,
        composition: "候选", style: appearance, batchSize: 2)
      let actual = try await plan.renderCooperatively(batchSize: 2)
      XCTAssertEqual(actual.text, expected.text)
      XCTAssertEqual(actual.compositionTextMap?.canonicalAliases, expected.compositionTextMap?.canonicalAliases)
      XCTAssertEqual(actual.compositionTextMap?.cellRanges, expected.compositionTextMap?.cellRanges)
    }
  }
}
