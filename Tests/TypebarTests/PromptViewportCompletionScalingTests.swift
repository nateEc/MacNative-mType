import AppKit
import XCTest
@testable import Typebar

final class PromptViewportCompletionScalingTests: XCTestCase {
  @MainActor func testLargeAdmissionVisitsEveryRealPainterWindow() async throws {
    let count = 100_001
    let session = TypingSession(configuration: .words(count),
      prompt: Array(repeating: "oak", count: count).joined(separator: " "))
    let style = PromptRenderStyle(theme: .init(background: .white, panel: .white,
      accent: .blue, colorScheme: .light))
    var visits = 0, windows = 0, nextField = 0
    let start = ProcessInfo.processInfo.systemUptime
    let accepted = try await WholePreviewViewportAdmission.check(session: session, style: style) { directory, current, fields, appearance in
      XCTAssertEqual(fields.lowerBound, nextField)
      XCTAssertEqual(directory.fieldCount, count)
      XCTAssertEqual(current.prompt, session.prompt)
      nextField = fields.upperBound; visits += fields.count; windows += 1
      return PromptRenderPlan.renderIndependentFieldWindow(directory: directory,
        session: current, fields: fields, style: appearance) != nil
    }
    print("VIEWPORT REAL ADMISSION words=\(count) fields=\(visits) windows=\(windows) elapsed=\(ProcessInfo.processInfo.systemUptime - start)")
    XCTAssertTrue(accepted)
    XCTAssertEqual(visits, count)
    XCTAssertEqual(nextField, count)
    XCTAssertEqual(windows, 3126)
  }

  func testWindowCompletionMatchesFullPolicyAfterInputErrorsAndBackspace() throws {
    for prompt in ["oak ash elm pine", "oak\nash elm pine", "oak  ash elm pine"] {
      for input in ["oak a", "oax a"] {
        var session = TypingSession(configuration: .words(4), prompt: prompt)
        let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
        func check(_ current: TypingSession) throws {
          XCTAssertFalse(current.isFinished)
          let full = current.completedPromptCharacterIndices
          for fields in [0..<1, (directory.fieldCount - 1)..<directory.fieldCount, 0..<directory.fieldCount] {
            let slice = try XCTUnwrap(directory.materialize(fields: fields))
            XCTAssertEqual(directory.completedIndices(in: slice.cells, session: current),
              full.intersection(Set(slice.cells.map(\.id))))
          }
        }
        try check(session)
        let start = Date(timeIntervalSinceReferenceDate: 920_400_000)
        for (index, character) in input.enumerated() {
          session.insert(String(character), at: start.addingTimeInterval(Double(index)))
          try check(session)
        }
        for index in 0..<4 {
          session.deleteBackward(at: start.addingTimeInterval(Double(index + 10)))
          try check(session)
        }
      }
    }
  }

  func testEmptyInputCompletionAcrossRealSmallAndLargeDirectories() throws {
    for count in [1_000, 100_001] {
      let session = TypingSession(configuration: .words(count),
        prompt: Array(repeating: "oak", count: count).joined(separator: " "))
      let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
      let first = try XCTUnwrap(directory.materialize(fields: 0..<32))
      let last = try XCTUnwrap(directory.materialize(fields: (count - 32)..<count))
      let start = ProcessInfo.processInfo.systemUptime
      for iteration in 0..<200 {
        let cells = iteration.isMultiple(of: 2) ? first.cells : last.cells
        XCTAssertEqual(directory.completedIndices(in: cells, session: session), [])
      }
      let elapsed = ProcessInfo.processInfo.systemUptime - start
      print("VIEWPORT COMPLETION EMPTY words=\(count) requests=200 elapsed=\(elapsed)")
      XCTAssertEqual(directory.fieldCount, count)
      XCTAssertEqual(directory.targetUTF16.count, session.prompt.utf16.count)
      XCTAssertEqual(first.cells.first?.id, 0)
      XCTAssertEqual(last.cells.last?.id, session.prompt.utf16.count - 1)
    }
  }
}
