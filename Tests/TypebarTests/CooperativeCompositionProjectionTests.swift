import XCTest
@testable import Typebar

@MainActor final class CooperativeCompositionProjectionTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 916_000_000)

  func testCooperativeProjectionMatchesSynchronousUnicodeAndOwnership() async throws {
    var ordinary = TypingSession(configuration: .words(4), prompt: "a \u{301}b 🙂 tail")
    ordinary.insertBatch("a ", at: start)
    var hidden = TypingSession(configuration: .words(3).with(modifiers: [.noSpaces]),
      prompt: "abxy", noSpaceWordEndIndices: [2, 2, 4], noSpaceTargetWords: ["ab", "", "xy"])
    hidden.insertBatch("ab", at: start)
    var rtl = TypingSession(configuration: .words(3, language: .arabic), prompt: "سلام عالم بيت")
    rtl.insert("س", at: start)
    for (session, marked) in [(ordinary, "候选"), (hidden, "XY"), (rtl, "ل"), (ordinary, "")] {
      for style in CompositionDisplayStyle.allCases {
        let expected = try XCTUnwrap(session.promptCompositionProjection(composition: marked, style: style))
        var progress: [Int] = []
        let prepared = try await session.promptCompositionProjectionCooperatively(
          composition: marked, style: style, batchSize: 2, didProject: { progress.append($0) })
        let actual = try XCTUnwrap(prepared)
        XCTAssertEqual(actual.cells.count, expected.cells.count)
        XCTAssertEqual(actual.fields.count, expected.fields.count)
        XCTAssertEqual(actual.replacedTargetUTF16Range, expected.replacedTargetUTF16Range)
        XCTAssertEqual(actual.referenceLetterUnitIndex, expected.referenceLetterUnitIndex)
        XCTAssertEqual(actual.canonicalAliases, expected.canonicalAliases)
        XCTAssertEqual(actual.caret, expected.caret)
        for (actual, expected) in zip(actual.cells, expected.cells) {
          XCTAssertEqual(actual.id, expected.id)
          XCTAssertEqual(actual.displayUTF16, expected.displayUTF16)
          XCTAssertEqual(actual.sourceSlices, expected.sourceSlices)
          XCTAssertEqual(actual.sourceFieldIndex, expected.sourceFieldIndex)
          XCTAssertEqual(actual.targetUTF16Range, expected.targetUTF16Range)
          XCTAssertEqual(actual.role, expected.role)
          XCTAssertEqual(actual.sourceGlyphOverride, expected.sourceGlyphOverride)
        }
        for (actual, expected) in zip(actual.fields, expected.fields) {
          XCTAssertEqual(actual.index, expected.index)
          XCTAssertEqual(actual.targetUTF16Range, expected.targetUTF16Range)
          XCTAssertEqual(actual.cellIDs, expected.cellIDs)
          XCTAssertEqual(actual.structuralReturnCount, expected.structuralReturnCount)
          XCTAssertEqual(actual.isRetired, expected.isRetired)
          XCTAssertEqual(actual.isRemoved, expected.isRemoved)
        }
        XCTAssertEqual(progress.last, session.promptGlyphs.count)
      }
    }
  }

  func testCancellationAfterFirstBatchDoesNotPublishPartialProjection() async throws {
    let session = TypingSession(configuration: .words(120),
      prompt: Array(repeating: "harbor", count: 120).joined(separator: " "))
    var projected = 0
    let task = Task {
      try await session.promptCompositionProjectionCooperatively(composition: "", style: .replace,
        batchSize: 3, didProject: { count in
          projected = count
          if count >= 3 { withUnsafeCurrentTask { $0?.cancel() } }
        })
    }
    do {
      _ = try await task.value
      XCTFail("Cancellation must not return a partial projection")
    } catch is CancellationError {
      XCTAssertEqual(projected, 3)
    }
  }

  func testLargeMixedFieldDirectoryMatchesSynchronousOwnerAndFinalCancellation() async throws {
    let words = (0..<1_001).map { index in
      switch index % 4 {
      case 0: "café"
      case 1: "候选"
      case 2: "🙂"
      default: "e\u{301}"
      }
    }
    let session = TypingSession(configuration: .words(words.count), prompt: words.joined(separator: " "))
    let expected = try XCTUnwrap(session.promptCompositionProjection(composition: "", style: .replace))
    let prepared = try await session.promptCompositionProjectionCooperatively(composition: "",
      style: .replace, batchSize: 37)
    let actual = try XCTUnwrap(prepared)
    XCTAssertEqual(actual.cells.map(\.displayUTF16), expected.cells.map(\.displayUTF16))
    XCTAssertEqual(actual.cells.map(\.sourceFieldIndex), expected.cells.map(\.sourceFieldIndex))
    XCTAssertEqual(actual.fields.map(\.cellIDs), expected.fields.map(\.cellIDs))
    XCTAssertEqual(actual.canonicalAliases, expected.canonicalAliases)
    XCTAssertEqual(actual.caret, expected.caret)

    let finalCount = session.promptGlyphs.count
    var lastBatch = 0
    let task = Task {
      try await session.promptCompositionProjectionCooperatively(composition: "", style: .replace,
        batchSize: 37, didProject: { count in
          lastBatch = count
          if count == finalCount { withUnsafeCurrentTask { $0?.cancel() } }
        })
    }
    do {
      _ = try await task.value
      XCTFail("Cancellation after the final cell batch must still reject the directory")
    } catch is CancellationError {
      XCTAssertEqual(lastBatch, finalCount)
    }
  }
}
