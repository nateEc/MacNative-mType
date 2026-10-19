import AppKit
import XCTest
@testable import Typebar

@MainActor final class WholePreviewViewportAdmissionTests: XCTestCase {
  private let style = PromptRenderStyle(theme: .init(background: .white, panel: .white,
    accent: .blue, colorScheme: .light))
  private func session() -> TypingSession {
    .init(configuration: .words(70), prompt: Array(repeating: "oak", count: 70).joined(separator: " "))
  }

  func testChecksEveryBoundedWindowAndRejectsLateFailure() async throws {
    var ranges: [Range<Int>] = []
    let accepted = try await WholePreviewViewportAdmission.check(session: session(), style: style) { _, _, fields, _ in
      ranges.append(fields)
      return true
    }
    XCTAssertTrue(accepted)
    XCTAssertEqual(ranges, [0..<32, 32..<64, 64..<70])
    ranges.removeAll()
    let rejected = try await WholePreviewViewportAdmission.check(session: session(), style: style) { _, _, fields, _ in
      ranges.append(fields)
      return fields.lowerBound == 0
    }
    XCTAssertFalse(rejected, "A valid opening batch must not hide an unsupported later window")
    XCTAssertEqual(ranges, [0..<32, 32..<64])
  }

  func testCancellationDuringFirstWindowStopsBeforeTheNextWindow() async throws {
    for acceptsWindow in [true, false] {
      var ranges: [Range<Int>] = []
      let running = Task {
        try await WholePreviewViewportAdmission.check(session: session(), style: style) { _, _, fields, _ in
          ranges.append(fields)
          withUnsafeCurrentTask { $0?.cancel() }
          return acceptsWindow
        }
      }
      do {
        _ = try await running.value
        XCTFail("Cancellation must win over either acceptance or fallback")
      } catch is CancellationError {}
      XCTAssertEqual(ranges, [0..<32])
    }
  }

  func testRealPainterAdmissionAndUnsupportedSourceKeepTheirBoundaries() async throws {
    let accepted = try await WholePreviewViewportAdmission.check(session: session(), style: style)
    XCTAssertTrue(accepted)
    let unicode = TypingSession(configuration: .words(2), prompt: "oak 😀")
    let rejected = try await WholePreviewViewportAdmission.check(session: unicode, style: style)
    XCTAssertFalse(rejected)
    let invalidBatch = try await WholePreviewViewportAdmission.check(session: session(), style: style, batchSize: 0)
    XCTAssertFalse(invalidBatch)
  }
}
