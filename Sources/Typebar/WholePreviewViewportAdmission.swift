import Foundation

/// Validate an immutable source through every local painter window before
/// omitting complete preparation. Work is still O(target); only one batch's
/// ink is retained, and cancellation is checked around every batch.
@MainActor enum WholePreviewViewportAdmission {
  static func check(session: TypingSession, style: PromptRenderStyle, batchSize: Int = 32,
    verifyWindow: (PromptViewportTargetDirectory, TypingSession, Range<Int>, PromptRenderStyle) -> Bool = {
      PromptRenderPlan.renderIndependentFieldWindow(directory: $0, session: $1, fields: $2, style: $3) != nil
    }) async throws -> Bool {
    try Task.checkCancellation()
    guard batchSize > 0, let directory = PromptViewportTargetDirectory(session: session),
      directory.fieldCount > 0 else { return false }
    var start = 0
    while start < directory.fieldCount {
      try Task.checkCancellation()
      let end = start + min(batchSize, directory.fieldCount - start)
      let accepted = verifyWindow(directory, session, start..<end, style)
      try Task.checkCancellation()
      guard accepted else { return false }
      start = end
      if start < directory.fieldCount { await Task.yield() }
    }
    return true
  }
}
