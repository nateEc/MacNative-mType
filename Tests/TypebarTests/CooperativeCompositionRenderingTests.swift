import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class CooperativeCompositionRenderingTests: XCTestCase {
  private func presentation(_ prompt: String, composition: String) throws -> PromptCompositionPresentation {
    let session = TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil,
      wordLimit: nil, difficulty: .normal, rules: .init(), modifiers: []), customText: prompt)
    return try XCTUnwrap(PromptCompositionPresentation(session: session,
      composition: composition, style: .replace))
  }

  private func ink(_ index: Int, _ glyph: TypingPromptGlyph,
    _ marked: PromptCompositionProjection.Cell?) -> AttributedString {
    var value = AttributedString(marked?.text ?? String(glyph.character))
    value.foregroundColor = index.isMultiple(of: 2) ? .orange : .green
    if marked != nil { value.underlineStyle = Text.LineStyle(color: .gray) }
    return value
  }

  func testCooperativeRenderingPreservesCompleteProjectionAndExactRanges() async throws {
    for (prompt, candidate) in [
      ("alpha beta\n🙂 café", ""),
      ("alpha beta\n🙂 café", "候选"),
      ("a \u{301}b tail", "")
    ] {
      let source = try presentation(prompt, composition: candidate)
      let expected = source.render(ink)
      var progress: [Int] = []
      let actual = try await source.renderCooperatively(batchSize: 3,
        didRender: { progress.append($0) }, ink)
      XCTAssertEqual(progress.last, source.projection.cells.count)
      XCTAssertTrue(progress.dropLast().allSatisfy { $0.isMultiple(of: 3) })
      XCTAssertEqual(actual.text, expected.text)
      XCTAssertEqual(actual.glyphCharacterOffsets, expected.glyphCharacterOffsets)
      let left = try XCTUnwrap(expected.compositionTextMap)
      let right = try XCTUnwrap(actual.compositionTextMap)
      XCTAssertEqual(right.cellRanges, left.cellRanges)
      XCTAssertEqual(right.inkRanges, left.inkRanges)
      XCTAssertEqual(right.cellTexts, left.cellTexts)
      XCTAssertEqual(right.canonicalAliases, left.canonicalAliases)
      XCTAssertEqual(right.fieldCharacterOffsets, left.fieldCharacterOffsets)
      XCTAssertEqual(right.fieldRuns, left.fieldRuns)
      XCTAssertEqual(right.caret, left.caret)
      XCTAssertEqual(right.markedInputRanges, left.markedInputRanges)
      XCTAssertEqual(right.markedCellIDs, left.markedCellIDs)
    }
  }

  func testCancellationAtBatchBoundaryReturnsNoPartialRendering() async throws {
    let source = try presentation(Array(repeating: "harbor", count: 120).joined(separator: " "), composition: "")
    var rendered = 0
    let task = Task {
      try await source.renderCooperatively(batchSize: 7, didRender: { count in
        rendered = count
        if count >= 7 { withUnsafeCurrentTask { $0?.cancel() } }
      }, ink)
    }
    do {
      _ = try await task.value
      XCTFail("A cancelled render must not publish a partial prompt")
    } catch is CancellationError {
      XCTAssertEqual(rendered, 7)
    }
  }
}
