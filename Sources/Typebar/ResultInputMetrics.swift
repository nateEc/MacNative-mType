import Foundation

/// Anonymous terminal counters for a version-negotiated submission. Accuracy
/// attempts survive deletion; speed credit concerns only the retained words.
/// Neither can be reconstructed from a legacy result's visible error count.
struct ResultInputMetrics: Codable, Equatable, Sendable {
  let version: Int
  let correctAttempts: Int
  let totalAttempts: Int
  let creditedUnits: Int
  let retainedUnits: Int
}
