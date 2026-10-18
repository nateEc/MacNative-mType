import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class CooperativeFieldLayoutTests: XCTestCase {
  private let font = NSFont.monospacedSystemFont(ofSize: 24, weight: .regular)

  private func map(_ prompt: String, composition: String = "") throws -> PromptCompositionTextMap {
    let session = TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil,
      wordLimit: nil, difficulty: .normal, rules: .init(), modifiers: []), customText: prompt)
    let presentation = try XCTUnwrap(PromptCompositionPresentation(session: session,
      composition: composition, style: .replace))
    let rendering = presentation.render { _, glyph, marked in
      AttributedString(marked?.text ?? String(glyph.character))
    }
    return try XCTUnwrap(rendering.compositionTextMap)
  }

  func testCooperativeLayoutMatchesSynchronousGeometryAcrossScriptsAndWidths() async throws {
    for prompt in ["amber birch\ncedar pine", "ab אב cd", "ab سلام cd", "🙂 café e\u{301}"] {
      let projection = try map(prompt, composition: "候选")
      for width: CGFloat in [48, 400] {
        for joins in [false, true] {
          for rtl in [false, true] {
            let expected = PromptFieldTextLayout(map: projection, width: width, font: font,
              rightToLeft: rtl, joinsLetters: joins)
            var progress: [Int] = []
            let actual = try await PromptFieldTextLayout.makeCooperatively(map: projection,
              width: width, font: font, rightToLeft: rtl, joinsLetters: joins,
              batchSize: 2, didPrepare: { progress.append($0) })
            XCTAssertEqual(progress.last, projection.fieldRuns.count)
            XCTAssertTrue(progress.dropLast().allSatisfy { $0.isMultiple(of: 2) })
            XCTAssertEqual(actual.size, expected.size, prompt)
            XCTAssertEqual(actual.cellFrames, expected.cellFrames, prompt)
            XCTAssertEqual(actual.fieldFrames, expected.fieldFrames, prompt)
            XCTAssertEqual(actual.shapingResourceCount, expected.shapingResourceCount, prompt)
            XCTAssertEqual(actual.preparedContentProjectionCount,
              expected.preparedContentProjectionCount, prompt)
            for id in projection.cellRanges.keys {
              XCTAssertEqual(actual.canonicalRect(id, after: false),
                expected.canonicalRect(id, after: false), prompt)
              XCTAssertEqual(actual.canonicalRect(id, after: true),
                expected.canonicalRect(id, after: true), prompt)
            }
          }
        }
      }
    }
  }

  func testCancellationAtFieldBatchBoundaryReturnsNoPartialLayout() async throws {
    let projection = try map(Array(repeating: "harbor", count: 120).joined(separator: " "))
    var prepared = 0
    let task = Task {
      try await PromptFieldTextLayout.makeCooperatively(map: projection,
        width: 400, font: font, batchSize: 3, didPrepare: { count in
          prepared = count
          if count >= 3 { withUnsafeCurrentTask { $0?.cancel() } }
        })
    }
    do {
      _ = try await task.value
      XCTFail("Cancelled layout must not publish partially prepared frames")
    } catch is CancellationError {
      XCTAssertEqual(prepared, 3)
    }
  }

  func testReusedBoxesAndRemovedReturnsMatchFreshUnboundedLayout() async throws {
    func cell(_ id: Int, _ character: Character) -> PromptFieldTextRun.Cell {
      .init(id: id, glyph: .init(character: character, state: .pending),
        text: AttributedString(String(character)), isGap: character == " ")
    }
    let first = PromptFieldTextRun(fieldID: 0, cells: [cell(0, "a"), cell(1, "b")], removedReturns: 2)
    let second = PromptFieldTextRun(fieldID: 1, cells: [cell(2, "س"), cell(3, "ل")],
      structuralReturn: true)
    let fields = [first, second, .init(fieldID: 2, cells: [cell(4, "🙂")])]
    let projection = PromptCompositionTextMap(text: AttributedString("abسل🙂"), cellRanges: [:],
      inkRanges: [:], cellTexts: [:], canonicalAliases: [:], fieldUnits: [:], caret: nil,
      fieldRuns: fields, markedInputText: "")
    let previous = PromptFieldTextLayout(fieldRuns: [first], width: 75, font: font,
      rightToLeft: true, joinsLetters: true, unbounded: true)
    let expected = PromptFieldTextLayout(map: projection, width: 75, font: font,
      rightToLeft: true, joinsLetters: true, unbounded: true)
    let actual = try await PromptFieldTextLayout.makeCooperatively(map: projection,
      width: 75, font: font, rightToLeft: true, joinsLetters: true, unbounded: true,
      reusing: previous, batchSize: 1)
    XCTAssertEqual(actual.size, expected.size)
    XCTAssertEqual(actual.cellFrames, expected.cellFrames)
    XCTAssertEqual(actual.fieldFrames, expected.fieldFrames)
    XCTAssertEqual(actual.shapingResourceCount, expected.shapingResourceCount)
    XCTAssertNotNil(actual.fieldFrames[2])
  }

  func testCancellationDuringFramePlacementReturnsNoPartialLayout() async throws {
    let projection = try map(Array(repeating: "harbor", count: 120).joined(separator: " "))
    var prepared = 0, placed = 0
    let task = Task {
      try await PromptFieldTextLayout.makeCooperatively(map: projection,
        width: 180, font: font, batchSize: 8,
        didPrepare: { prepared = $0 }, didPlace: { count in
          placed = count
          if count >= 8 { withUnsafeCurrentTask { $0?.cancel() } }
        })
    }
    do {
      _ = try await task.value
      XCTFail("Cancelled frame placement must not publish partial geometry")
    } catch is CancellationError {
      XCTAssertEqual(prepared, projection.fieldRuns.count)
      XCTAssertEqual(placed, 8)
    }
  }
}
