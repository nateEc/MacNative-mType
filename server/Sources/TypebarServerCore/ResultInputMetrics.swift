import Foundation
import Vapor

/// Versioned anonymous counts; never infer attempts from residual errors.
/// These are consistency checks, not an unforgeable anti-cheat attestation.
public struct ResultInputMetrics: Content, Equatable, Sendable {
    public let version: Int
    public let correctAttempts: Int
    public let totalAttempts: Int
    public let creditedUnits: Int
    public let retainedUnits: Int

    public init(version: Int, correctAttempts: Int, totalAttempts: Int, creditedUnits: Int, retainedUnits: Int) {
        self.version = version
        self.correctAttempts = correctAttempts
        self.totalAttempts = totalAttempts
        self.creditedUnits = creditedUnits
        self.retainedUnits = retainedUnits
    }

    var isValid: Bool {
        version == 1 && (0...1_800_000).contains(totalAttempts)
            && (0...totalAttempts).contains(correctAttempts)
            && (0...totalAttempts).contains(retainedUnits)
            && (0...retainedUnits).contains(creditedUnits)
    }

    var accuracyPercentage: Double {
        totalAttempts == 0 ? 0 : Double(correctAttempts) / Double(totalAttempts) * 100
    }

    var preciseAccuracy: Double {
        ((accuracyPercentage + Double.ulpOfOne) * 100).rounded() / 100
    }
}
