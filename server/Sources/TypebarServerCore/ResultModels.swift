import Foundation
import Vapor

public struct ResultSubmissionRequest: Content, Equatable {
    public let id: UUID
    public let mode: String
    public let language: String
    public let durationSeconds: Int?
    public let wordLimit: Int?
    public let wpm: Int
    public let rawWpm: Int
    public let accuracy: Int
    public let errorCount: Int
    public let eventCount: Int
    public let startedAt: Date
    public let finishedAt: Date
}

public struct ResultSubmissionResponse: Content, Equatable {
    public let id: UUID
    public let accepted: Bool
    public let leaderboardEligible: Bool
    public let experienceGained: Int
    public let totalExperience: Int
    public let weeklyExperienceRank: Int?
}

public struct LeaderboardQuery: Content {
    public let mode: String?
    public let language: String?
    public let period: String?
    public let limit: Int?
}

public struct LeaderboardEntry: Content, Equatable, Identifiable {
    public let id: UUID
    public let rank: Int
    public let userID: UUID
    public let displayName: String
    public let mode: String
    public let language: String
    public let wpm: Int
    public let accuracy: Int
    public let finishedAt: Date
}

public struct LeaderboardResponse: Content, Equatable {
    public let entries: [LeaderboardEntry]
}

public struct ExperienceLeaderboardEntry: Content, Equatable, Identifiable {
    public let id: UUID
    public let rank: Int
    public let userID: UUID
    public let displayName: String
    public let totalExperience: Int
}

public struct ExperienceLeaderboardResponse: Content, Equatable {
    public let entries: [ExperienceLeaderboardEntry]
}

/// Typebar's transparent experience policy. It uses only server-validated
/// result fields and is independent of the reference project's implementation.
public enum TypebarExperiencePolicy {
    public static func points(for result: ResultSubmissionRequest) -> Int {
        guard result.mode != "zen" else { return 0 }
        let seconds: Double
        if let duration = result.durationSeconds {
            seconds = Double(duration)
        } else {
            let charactersPerMinute = max(result.rawWpm, 1) * 5
            seconds = max(5, min(900, Double(result.eventCount) / Double(charactersPerMinute) * 60))
        }
        let accuracyFactor = max(0.25, Double(result.accuracy) / 100)
        let quoteFactor = result.mode == "quote" ? 1.25 : 1
        let perfectBonus = result.accuracy == 100 ? 1.2 : 1
        return max(1, Int((seconds * accuracyFactor * quoteFactor * perfectBonus).rounded()))
    }
}
