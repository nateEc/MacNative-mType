import Foundation
import Vapor

/// Completion percentages, not replay, physical evidence, or anticheat proof.
/// WPM consistency is accepted transiently; only key consistency is retained.
public struct ResultConsistencyMetrics: Content, Equatable, Sendable {
    public let version: Int
    public let keyConsistency: Double
    public let wpmConsistency: Double?

    public init(version: Int = 1, keyConsistency: Double, wpmConsistency: Double? = nil) {
        self.version = version
        self.keyConsistency = keyConsistency
        self.wpmConsistency = wpmConsistency
    }

    var isValid: Bool {
        version == 1 && keyConsistency.isFinite && (0...100).contains(keyConsistency)
            && (wpmConsistency.map { $0.isFinite && (0...100).contains($0) } ?? true)
    }
}
