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
    public let consistency: Double
    public let errorCount: Int
    public let eventCount: Int
    public let startedAt: Date
    public let finishedAt: Date

    public init(
        id: UUID, mode: String, language: String, durationSeconds: Int?, wordLimit: Int?, wpm: Int,
        rawWpm: Int, accuracy: Int, consistency: Double = 0, errorCount: Int, eventCount: Int,
        startedAt: Date, finishedAt: Date
    ) {
        self.id = id
        self.mode = mode
        self.language = language
        self.durationSeconds = durationSeconds
        self.wordLimit = wordLimit
        self.wpm = wpm
        self.rawWpm = rawWpm
        self.accuracy = accuracy
        self.consistency = consistency
        self.errorCount = errorCount
        self.eventCount = eventCount
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, mode, language, durationSeconds, wordLimit, wpm, rawWpm, accuracy, consistency,
            errorCount, eventCount, startedAt, finishedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        mode = try values.decode(String.self, forKey: .mode)
        language = try values.decode(String.self, forKey: .language)
        durationSeconds = try values.decodeIfPresent(Int.self, forKey: .durationSeconds)
        wordLimit = try values.decodeIfPresent(Int.self, forKey: .wordLimit)
        wpm = try values.decode(Int.self, forKey: .wpm)
        rawWpm = try values.decode(Int.self, forKey: .rawWpm)
        accuracy = try values.decode(Int.self, forKey: .accuracy)
        consistency = try values.decodeIfPresent(Double.self, forKey: .consistency) ?? 0
        errorCount = try values.decode(Int.self, forKey: .errorCount)
        eventCount = try values.decode(Int.self, forKey: .eventCount)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        finishedAt = try values.decode(Date.self, forKey: .finishedAt)
    }
}

public struct ResultSubmissionResponse: Content, Equatable {
    public let id: UUID
    public let accepted: Bool
    public let leaderboardEligible: Bool
    public let experienceGained: Int
    public let totalExperience: Int
    public let weeklyExperienceRank: Int?
}

/// A compact, account-scoped view of a submitted result. It deliberately
/// excludes prompt text, input replay, and every profile or credential field.
public struct AccountResultResponse: Content, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let mode: String
    public let language: String
    public let durationSeconds: Int?
    public let wordLimit: Int?
    public let wpm: Int
    public let rawWpm: Int
    public let accuracy: Int
    public let consistency: Double
    public let errorCount: Int
    public let eventCount: Int
    public let startedAt: Date
    public let finishedAt: Date

    public init(
        id: UUID, mode: String, language: String, durationSeconds: Int?, wordLimit: Int?, wpm: Int,
        rawWpm: Int, accuracy: Int, consistency: Double, errorCount: Int, eventCount: Int,
        startedAt: Date, finishedAt: Date
    ) {
        self.id = id
        self.mode = mode
        self.language = language
        self.durationSeconds = durationSeconds
        self.wordLimit = wordLimit
        self.wpm = wpm
        self.rawWpm = rawWpm
        self.accuracy = accuracy
        self.consistency = consistency
        self.errorCount = errorCount
        self.eventCount = eventCount
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

/// `finishedOnOrAfter` is a UTC Unix timestamp in seconds. Results are always
/// scoped to the authenticated account and ordered newest first.
public struct ResultListQuery: Content, Sendable {
    public let finishedOnOrAfter: Double?
    public let offset: Int?
    public let limit: Int?

    public init(finishedOnOrAfter: Double? = nil, offset: Int? = nil, limit: Int? = nil) {
        self.finishedOnOrAfter = finishedOnOrAfter
        self.offset = offset
        self.limit = limit
    }
}

public struct ResultListResponse: Content, Equatable, Sendable {
    public let results: [AccountResultResponse]
    public let total: Int

    public init(results: [AccountResultResponse], total: Int) {
        self.results = results
        self.total = total
    }
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
    public let consistency: Double
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
