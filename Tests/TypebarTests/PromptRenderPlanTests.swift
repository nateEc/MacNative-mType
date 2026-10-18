import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptRenderPlanTests: XCTestCase {
  private let theme = ResolvedTheme(background: .white, panel: .white, accent: .blue,
    colorScheme: .light)

  func testPendingInkRemainsReadableAfterCompositingOnPracticeSurfaces() {
    let session = TypingSession(configuration: .words(1), prompt: "alpha")
    for choice in AppTheme.allCases {
      let palette = choice.resolvedTheme
      let style = PromptRenderStyle(theme: palette, caretStyle: .off, highlightMode: .off)
      let rendered = PromptRenderPlan(session: session, composition: nil, style: style).render()
      guard let ink = rendered.text.runs.first?.foregroundColor else {
        XCTFail("Missing pending ink: \(choice.rawValue)")
        continue
      }
      let chooInk = ChooGlyphPalette(theme: palette, flipsCompletionAndFuture: false,
        usesColorfulMode: false).foreground(for: .pending)
      for surface in [palette.background, palette.panel] {
        XCTAssertGreaterThanOrEqual(contrast(ink, on: surface), 3.0, "Ordinary: \(choice.rawValue)")
        XCTAssertGreaterThanOrEqual(contrast(Color(nsColor: chooInk), on: surface), 3.0,
          "Choo: \(choice.rawValue)")
      }
    }
  }

  private func contrast(_ foreground: Color, on background: Color) -> Double {
    let ink = ThemeColor(color: foreground), surface = ThemeColor(color: background)
    let alpha = ink.opacity
    func linear(_ value: Double) -> Double {
      value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    func luminance(_ red: Double, _ green: Double, _ blue: Double) -> Double {
      0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    let front = luminance(ink.red * alpha + surface.red * (1 - alpha),
      ink.green * alpha + surface.green * (1 - alpha),
      ink.blue * alpha + surface.blue * (1 - alpha))
    let back = luminance(surface.red, surface.green, surface.blue)
    return (max(front, back) + 0.05) / (min(front, back) + 0.05)
  }

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
