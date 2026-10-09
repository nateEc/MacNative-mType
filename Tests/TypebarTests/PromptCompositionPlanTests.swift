import AppKit
import XCTest
@testable import Typebar

final class PromptCompositionPlanTests: XCTestCase {
  func testMarkedSpanConsumesMultipleTargetsWithoutRepeatingTheirSuffix() {
    let plan = PromptCompositionPlan(target: "abcde", input: "a", composition: "XY", isZen: false, style: .replace)
    XCTAssertEqual(plan.cells.map(\.text), ["X", "Y", "d", "e"])
    XCTAssertEqual(plan.cells.map(\.targetIndex), [1, 2, 3, 4])
    XCTAssertEqual(plan.replacedTargetRange, 1..<3)
    XCTAssertEqual(plan.caret, .target(3))
  }

  func testOffAndBelowKeepTargetInkButStillReserveTheWholeMarkedSpan() {
    for style in [CompositionDisplayStyle.off, .below] {
      let plan = PromptCompositionPlan(target: "abcde", input: "a", composition: "bX", isZen: false, style: style)
      XCTAssertEqual(plan.cells.map(\.text), ["b", "c", "d", "e"])
      XCTAssertEqual(plan.cells.map(\.compositionIndex), [0, 1, nil, nil])
      XCTAssertEqual(plan.cells.map(\.matchesTarget), [true, false, false, false])
      XCTAssertEqual(plan.caret, .target(3))
    }
  }

  func testOverflowStaysInTheActiveWordAndCaretFollowsTheLastMarkedCell() {
    let plan = PromptCompositionPlan(target: "ab", input: "a", composition: "XYZ", isZen: false, style: .replace)
    XCTAssertEqual(plan.cells.map(\.text), ["X", "Y", "Z"])
    XCTAssertEqual(plan.cells.map(\.targetIndex), [1, nil, nil])
    XCTAssertEqual(plan.replacedTargetRange, 1..<2)
    XCTAssertEqual(plan.caret, .afterComposition(2))
    let alreadyExtra = PromptCompositionPlan(target: "ab", input: "abcd", composition: "XY", isZen: false, style: .off)
    XCTAssertEqual(alreadyExtra.cells.map(\.text), ["X", "Y"])
    XCTAssertEqual(alreadyExtra.replacedTargetRange, 2..<2)
    XCTAssertEqual(alreadyExtra.caret, .afterComposition(1))
  }

  func testMarkedSpacesAndControlsAreNotCommittedTypoIconsOrTargetNewlines() {
    let replacement = PromptCompositionPlan(target: "a\tb\n", input: "a", composition: " \n\t", isZen: false, style: .replace)
    XCTAssertEqual(replacement.cells.map(\.text), ["_", "\n", "\t"])
    XCTAssertEqual(replacement.cells.map(\.targetIndex), [1, 2, 3])
    XCTAssertEqual(replacement.caret, .afterComposition(2))
    let below = PromptCompositionPlan(target: "a\tb\n", input: "a", composition: "XYZ", isZen: false, style: .below)
    XCTAssertEqual(below.cells.map(\.text), ["\t", "b", "\n"])
  }

  func testZenAppendsAllMarkedTextForEveryStyleAndSuppressesItsEmptyPlaceholder() {
    for style in CompositionDisplayStyle.allCases {
      let plan = PromptCompositionPlan(target: "", input: "", composition: "候选 \n", isZen: true, style: style)
      XCTAssertEqual(plan.cells.map(\.text), ["候", "选", " ", "\n"])
      XCTAssertTrue(plan.cells.allSatisfy { $0.targetIndex == nil && $0.compositionIndex != nil })
      XCTAssertFalse(plan.hasEmptyPlaceholder)
      XCTAssertEqual(plan.caret, .afterComposition(3))
    }
  }

  func testCancelRestoresTargetsAndEmptyZenWithoutMutatingTheCommittedInput() {
    let target = "abcde", input = "a"
    let marked = PromptCompositionPlan(target: target, input: input, composition: "XYZ", isZen: false, style: .replace)
    let cancelled = PromptCompositionPlan(target: target, input: input, composition: "", isZen: false, style: .replace)
    XCTAssertEqual(marked.replacedTargetRange, 1..<4)
    XCTAssertEqual(cancelled.cells.map(\.text), ["b", "c", "d", "e"])
    XCTAssertEqual(cancelled.caret, .target(1))
    let empty = PromptCompositionPlan(target: "", input: "", composition: "", isZen: true, style: .off)
    XCTAssertTrue(empty.hasEmptyPlaceholder)
    XCTAssertEqual(empty.caret, .afterInput)
    XCTAssertEqual(target, "abcde"); XCTAssertEqual(input, "a")
  }

  func testNativeGraphemesRemainWholeAndTheirTargetIdentityDoesNotDependOnCandidateInk() {
    let plan = PromptCompositionPlan(target: "a👩‍💻e\u{301}文", input: "a", composition: "👨‍👩‍👧‍👦候", isZen: false, style: .replace)
    XCTAssertEqual(plan.cells.map(\.text), ["👨‍👩‍👧‍👦", "候", "文"])
    XCTAssertEqual(plan.cells.map(\.targetIndex), [1, 2, 3])
    XCTAssertEqual(plan.caret, .target(3))
    let rtl = PromptCompositionPlan(target: "אבגד", input: "א", composition: "בX", isZen: false, style: .replace)
    XCTAssertEqual(rtl.cells.map(\.text), ["ב", "X", "ד"])
    XCTAssertEqual(rtl.cells.map(\.matchesTarget), [true, false, false])
  }

  func testMarkedCorrectnessRequiresExactScalarIdentityNotCanonicalEquivalence() {
    for (target, candidate) in [("éz", "e\u{301}"), ("e\u{301}z", "é")] {
      let plan = PromptCompositionPlan(target: target, input: "", composition: candidate, isZen: false, style: .replace)
      XCTAssertEqual(plan.cells.first?.matchesTarget, false)
      XCTAssertEqual(plan.replacedTargetRange, 0..<1)
      XCTAssertEqual(plan.caret, .target(1))
    }
    for value in ["é", "e\u{301}"] {
      let plan = PromptCompositionPlan(target: value + "z", input: "", composition: value, isZen: false, style: .off)
      XCTAssertEqual(plan.cells.first?.matchesTarget, true)
    }
  }

  @MainActor func testNativeMarkedTextUpdatesAndCancellationDoNotBecomeAcceptedInput() {
    var session = TypingSession(configuration: .words(2), prompt: "abc def")
    let input = TypingInputView(frame: .zero)
    var composition = ""
    let start = Date(timeIntervalSinceReferenceDate: 914_100_000)
    input.onCompositionStarted = { session.beginComposition(at: start) }
    input.onCompositionChanged = { composition = $0 }
    input.onInsert = { text, forced in session.insertBatch(text, forceError: forced, at: start) }
    for candidate in ["XY", "b", "XYZW"] {
      input.setMarkedText(candidate, selectedRange: .init(), replacementRange: .init())
      let plan = PromptCompositionPlan(target: "abc", input: session.typed,
        composition: composition, isZen: false, style: .replace)
      XCTAssertEqual(plan.cells.filter { $0.compositionIndex != nil }.map(\.text), candidate.map(String.init))
      XCTAssertTrue(input.hasMarkedText()); XCTAssertTrue(session.typed.isEmpty)
      XCTAssertEqual(session.errors, 0); XCTAssertEqual(session.completedWordCount, 0)
    }
    input.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    let cancelled = PromptCompositionPlan(target: "abc", input: session.typed,
      composition: composition, isZen: false, style: .replace)
    XCTAssertEqual(cancelled.cells.map(\.text), ["a", "b", "c"])
    XCTAssertEqual(cancelled.caret, .target(0)); XCTAssertFalse(input.hasMarkedText())
    XCTAssertTrue(session.typed.isEmpty)
    input.insertText("abc ", replacementRange: .init())
    XCTAssertEqual(session.typed, "abc "); XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(session.errors, 0); XCTAssertEqual(composition, "")
  }
}
