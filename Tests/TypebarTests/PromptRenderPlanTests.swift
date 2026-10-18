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

  func testLargeFirstInputSeparatesProjectionAssemblyAndAppearanceCosts() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["TYPEBAR_RENDER_ENDURANCE_TESTS"] == "1",
      "Run explicitly with TYPEBAR_RENDER_ENDURANCE_TESTS=1")
    let wordCount = 100_001
    let prompt = Array(repeating: "alpha", count: wordCount).joined(separator: " ")
    var session = TypingSession(configuration: .words(wordCount), prompt: prompt)
    session.insertBatch("a", at: Date(timeIntervalSinceReferenceDate: 916_100_000))
    let started = ProcessInfo.processInfo.systemUptime
    let presentation = try XCTUnwrap(PromptCompositionPresentation(session: session,
      composition: "", style: .replace))
    let projected = ProcessInfo.processInfo.systemUptime
    do {
      let plain = presentation.render { _, glyph, _ in AttributedString(String(glyph.character)) }
      XCTAssertEqual(String(plain.text.characters), prompt)
      XCTAssertEqual(plain.compositionTextMap?.cellRanges.count, prompt.count)
      XCTAssertNil(plain.compositionTextMap?.cellRanges.first(where: {
        $0.value.location != $0.key || $0.value.length != 1
      }), "Plain ASCII cell ranges must cover the full target at exact offsets")
    }
    let assembled = ProcessInfo.processInfo.systemUptime
    let style = PromptRenderStyle(theme: theme, compositionDisplayStyle: .replace)
    let plan = PromptRenderPlan(session: session, composition: "", style: style)
    let planned = ProcessInfo.processInfo.systemUptime
    let rendered = plan.render()
    let finished = ProcessInfo.processInfo.systemUptime
    XCTAssertEqual(String(rendered.text.characters), prompt)
    XCTAssertEqual(rendered.compositionTextMap?.cellRanges.count, prompt.count)
    XCTAssertNil(rendered.compositionTextMap?.cellRanges.first(where: {
      $0.value.location != $0.key || $0.value.length != 1
    }), "Styled ASCII cell ranges must cover the full target at exact offsets")
    let patchStarted = ProcessInfo.processInfo.systemUptime
    var patchedText = rendered.text
    let end = patchedText.characters.index(after: patchedText.startIndex)
    patchedText[patchedText.startIndex..<end].foregroundColor = .red
    let patched = ProcessInfo.processInfo.systemUptime
    XCTAssertEqual(String(patchedText.characters), prompt)
    XCTAssertNotEqual(patchedText, rendered.text)
    print("large-first-input words=\(wordCount) projection=\(projected - started) plainAssembly=\(assembled - projected) planConstruction=\(planned - assembled) fullAppearanceAndAssembly=\(finished - planned) firstGlyphAttributePatch=\(patched - patchStarted)")
  }

  func testFirstInputPatchMatchesFullNativeRenderingForOrdinaryWord() throws {
    for configuration in [TestConfiguration.words(2), .words(2).with(modifiers: [.noQuit])] {
      for colorful in [false, true] {
        for flips in [false, true] {
          var style = PromptRenderStyle(theme: theme, caretStyle: .bar,
            highlightMode: .letter)
          style.colorfulMode = colorful
          style.flipTestColors = flips
          var session = TypingSession(configuration: configuration, prompt: "alpha beta")
          let prepared = PromptRenderPlan(session: session, composition: "", style: style).render()
          session.insertBatch("a", at: Date(timeIntervalSinceReferenceDate: 916_100_000))
          let patched = try XCTUnwrap(PromptSequentialInputPatch.make(prepared: prepared,
            session: session, style: style))
          let expected = PromptRenderPlan(session: session, composition: "", style: style).render()
          XCTAssertEqual(patched.text, expected.text)
          XCTAssertEqual(patched.glyphCharacterOffsets, expected.glyphCharacterOffsets)
          XCTAssertEqual(patched.compositionTextMap?.caret, expected.compositionTextMap?.caret)
          XCTAssertEqual(patched.compositionTextMap?.cellTexts, expected.compositionTextMap?.cellTexts)
          XCTAssertEqual(patched.compositionTextMap?.fieldRuns, expected.compositionTextMap?.fieldRuns)
          XCTAssertEqual(patched.compositionTextMap?.cellRanges, expected.compositionTextMap?.cellRanges)
          XCTAssertEqual(patched.compositionTextMap?.inkRanges, expected.compositionTextMap?.inkRanges)
        }
      }
    }
  }

  func testSequentialInputPatchMatchesFullNativeRenderingWithinFirstWord() throws {
    for colorful in [false, true] {
      for flips in [false, true] {
        var style = PromptRenderStyle(theme: theme, caretStyle: .bar,
          highlightMode: .letter)
        style.colorfulMode = colorful
        style.flipTestColors = flips
        var session = TypingSession(configuration: .words(2), prompt: "alpha beta")
        var frame = PromptRenderPlan(session: session, composition: "", style: style).render()
        for (index, character) in "alph".enumerated() {
          session.insertBatch(String(character),
            at: Date(timeIntervalSinceReferenceDate: 916_100_000 + Double(index)))
          frame = try XCTUnwrap(PromptSequentialInputPatch.make(prepared: frame,
            session: session, style: style))
          let expected = PromptRenderPlan(session: session, composition: "", style: style).render()
          XCTAssertEqual(frame.text, expected.text)
          XCTAssertEqual(frame.compositionTextMap?.caret, expected.compositionTextMap?.caret)
          XCTAssertEqual(frame.compositionTextMap?.cellTexts, expected.compositionTextMap?.cellTexts)
          XCTAssertEqual(frame.compositionTextMap?.fieldRuns, expected.compositionTextMap?.fieldRuns)
        }
      }
    }
  }

  func testSequentialPatchDeclinesWrongSecondKeyAndWordBoundary() throws {
    let style = PromptRenderStyle(theme: theme, caretStyle: .bar)
    for (prompt, second, third) in [("alpha beta", "x", nil), ("abc beta", "b", "c")] {
      var session = TypingSession(configuration: .words(2), prompt: prompt)
      let original = PromptRenderPlan(session: session, composition: "", style: style).render()
      session.insertBatch("a", at: Date(timeIntervalSinceReferenceDate: 916_100_000))
      let first = try XCTUnwrap(PromptSequentialInputPatch.make(prepared: original,
        session: session, style: style))
      session.insertBatch(second, at: Date(timeIntervalSinceReferenceDate: 916_100_001))
      if let third {
        let secondFrame = try XCTUnwrap(PromptSequentialInputPatch.make(prepared: first,
          session: session, style: style))
        session.insertBatch(third, at: Date(timeIntervalSinceReferenceDate: 916_100_002))
        XCTAssertNil(PromptSequentialInputPatch.make(prepared: secondFrame,
          session: session, style: style), "Final letter before a word boundary must fall back for \(prompt)")
      } else {
        XCTAssertNil(PromptSequentialInputPatch.make(prepared: first,
          session: session, style: style), "Wrong key must fall back for \(prompt)")
      }
    }
  }

  func testFirstInputPatchDeclinesIncorrectAndStructurallyDifferentInput() {
    let style = PromptRenderStyle(theme: theme, caretStyle: .bar)
    for (prompt, input) in [("alpha beta", "x"), ("écho beta", "é"),
      ("a🙂 beta", "a"), ("a", "a")] {
      var session = TypingSession(configuration: .words(2), prompt: prompt)
      let prepared = PromptRenderPlan(session: session, composition: "", style: style).render()
      session.insertBatch(input, at: Date(timeIntervalSinceReferenceDate: 916_100_000))
      XCTAssertNil(PromptSequentialInputPatch.make(prepared: prepared, session: session,
        style: style), "Fallback required for \(prompt) / \(input)")
    }
  }
}
