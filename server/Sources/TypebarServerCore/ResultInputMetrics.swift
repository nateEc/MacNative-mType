import Foundation
import Vapor

public enum ResultScoringUnitBasis: String, Codable, Sendable {
    case utf16, koreanJamo
}

/// Versioned anonymous counts; never infer attempts from residual errors.
/// These are consistency checks, not an unforgeable anti-cheat attestation.
public struct ResultInputMetrics: Content, Equatable, Sendable {
    public let version: Int
    public let correctAttempts: Int
    public let totalAttempts: Int
    public let creditedUnits: Int
    public let retainedUnits: Int
    public let retainedInputUnits: Int?
    public let scoringUnitBasis: ResultScoringUnitBasis?

    public init(version: Int, correctAttempts: Int, totalAttempts: Int, creditedUnits: Int, retainedUnits: Int,
        retainedInputUnits: Int? = nil, scoringUnitBasis: ResultScoringUnitBasis? = nil) {
        self.version = version
        self.correctAttempts = correctAttempts
        self.totalAttempts = totalAttempts
        self.creditedUnits = creditedUnits
        self.retainedUnits = retainedUnits
        self.retainedInputUnits = retainedInputUnits
        self.scoringUnitBasis = scoringUnitBasis
    }

    var isValid: Bool {
        guard (0...1_800_000).contains(totalAttempts),
            (0...totalAttempts).contains(correctAttempts), retainedUnits >= 0,
            (0...retainedUnits).contains(creditedUnits) else { return false }
        if version == 1 {
            return retainedInputUnits == nil && scoringUnitBasis == nil && retainedUnits <= totalAttempts
        }
        guard version == 2, let input = retainedInputUnits, (0...totalAttempts).contains(input),
            retainedUnits >= input, let basis = scoringUnitBasis else { return false }
        switch basis {
        case .utf16: return retainedUnits == input
        case .koreanJamo: return retainedUnits <= input * 5 // input is already bounded before multiplication.
        }
    }

    var accuracyPercentage: Double {
        totalAttempts == 0 ? 0 : Double(correctAttempts) / Double(totalAttempts) * 100
    }

    var preciseAccuracy: Double {
        ((accuracyPercentage + Double.ulpOfOne) * 100).rounded() / 100
    }
}
