import Foundation
import Vapor

public struct ResultTimingEvidence: Content, Equatable, Sendable {
    public let version: Int
    public let keyDurationMilliseconds: [Int]
    public let keySpacingMilliseconds: [Int]
    public let keyOverlapMilliseconds: Int

    public init(
        version: Int,
        keyDurationMilliseconds: [Int],
        keySpacingMilliseconds: [Int],
        keyOverlapMilliseconds: Int
    ) {
        self.version = version
        self.keyDurationMilliseconds = keyDurationMilliseconds
        self.keySpacingMilliseconds = keySpacingMilliseconds
        self.keyOverlapMilliseconds = keyOverlapMilliseconds
    }
}

/// Optional effective-time metadata reported by a capability-negotiating
/// native client. It is separate from timing evidence: it improves profile
/// accounting but is not proof for competitive leaderboard eligibility.
public struct ResultPracticeTiming: Content, Equatable, Sendable {
    public let version: Int
    public let terminalEngagedMilliseconds: Int
    public let priorAttemptEngagedMilliseconds: Int

    public init(
        version: Int, terminalEngagedMilliseconds: Int, priorAttemptEngagedMilliseconds: Int
    ) {
        self.version = version
        self.terminalEngagedMilliseconds = terminalEngagedMilliseconds
        self.priorAttemptEngagedMilliseconds = priorAttemptEngagedMilliseconds
    }
}

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
    public let restartCount: Int
    public let tags: [String]
    public let timingEvidence: ResultTimingEvidence?
    public let practiceTiming: ResultPracticeTiming?
    public let startedAt: Date
    public let finishedAt: Date

    public init(
        id: UUID, mode: String, language: String, durationSeconds: Int?, wordLimit: Int?, wpm: Int,
        rawWpm: Int, accuracy: Int, consistency: Double = 0, errorCount: Int, eventCount: Int,
        restartCount: Int = 0, tags: [String] = [], timingEvidence: ResultTimingEvidence? = nil,
        practiceTiming: ResultPracticeTiming? = nil,
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
        self.restartCount = restartCount
        self.tags = tags
        self.timingEvidence = timingEvidence
        self.practiceTiming = practiceTiming
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, mode, language, durationSeconds, wordLimit, wpm, rawWpm, accuracy, consistency,
            errorCount, eventCount, restartCount, tags, startedAt, finishedAt
        case timingEvidence
        case practiceTiming
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
        restartCount = try values.decodeIfPresent(Int.self, forKey: .restartCount) ?? 0
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        timingEvidence = try values.decodeIfPresent(ResultTimingEvidence.self, forKey: .timingEvidence)
        practiceTiming = try values.decodeIfPresent(ResultPracticeTiming.self, forKey: .practiceTiming)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        finishedAt = try values.decode(Date.self, forKey: .finishedAt)
    }
}

public struct ResultSubmissionResponse: Content, Equatable {
    public let id: UUID
    public let accepted: Bool
    public let leaderboardEligible: Bool
    public let dailyLeaderboardRank: Int?
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
    public let tags: [String]
    public let practiceTiming: ResultPracticeTiming?
    public let startedAt: Date
    public let finishedAt: Date

    public init(
        id: UUID, mode: String, language: String, durationSeconds: Int?, wordLimit: Int?, wpm: Int,
        rawWpm: Int, accuracy: Int, consistency: Double, errorCount: Int, eventCount: Int,
        tags: [String], practiceTiming: ResultPracticeTiming? = nil, startedAt: Date, finishedAt: Date
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
        self.tags = tags
        self.practiceTiming = practiceTiming
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

public struct UpdateResultTagsRequest: Content, Equatable, Sendable {
    public let tags: [String]

    public init(tags: [String]) {
        self.tags = tags
    }
}

public struct LeaderboardQuery: Content {
    public let mode: String?
    public let language: String?
    public let period: String?
    /// The duration or word count is the native counterpart of Monkeytype's
    /// `mode2`: a speed result is comparable only with the same configured limit.
    public let durationSeconds: Int?
    public let wordLimit: Int?
    public let limit: Int?
    public let offset: Int?

    public init(
        mode: String? = nil, language: String? = nil, period: String? = nil,
        durationSeconds: Int? = nil, wordLimit: Int? = nil,
        limit: Int? = nil, offset: Int? = nil
    ) {
        self.mode = mode
        self.language = language
        self.period = period
        self.durationSeconds = durationSeconds
        self.wordLimit = wordLimit
        self.limit = limit
        self.offset = offset
    }
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
    public let selectedBadge: PublicProfileBadge?
    public let discordAvatar: PublicDiscordAvatarResponse?
}

public struct LeaderboardResponse: Content, Equatable {
    public let entries: [LeaderboardEntry]
    public let total: Int
    public let offset: Int
    public let pageSize: Int
    /// Lets newer native clients avoid sending parameter filters to an older
    /// self-hosted service that would silently ignore them.
    public let parameterFilterSupported: Bool
    /// Lets native clients use cross-device personal rank movement only when
    /// this service implements the matching account-scoped memory route.
    public let rankMemorySupported: Bool

    public init(
        entries: [LeaderboardEntry], total: Int, offset: Int, pageSize: Int,
        parameterFilterSupported: Bool = true, rankMemorySupported: Bool = true
    ) {
        self.entries = entries
        self.total = total
        self.offset = offset
        self.pageSize = pageSize
        self.parameterFilterSupported = parameterFilterSupported
        self.rankMemorySupported = rankMemorySupported
    }
}

/// Account-private practice-time qualification returned only from authenticated
/// personal-rank routes. It explains an absent rank without exposing another
/// account's practice history.
public struct LeaderboardEligibility: Content, Equatable, Sendable {
    public let isEligible: Bool
    public let completedPracticeSeconds: Int
    public let minimumPracticeSeconds: Int
    /// True only for the authenticated account when the deployment has
    /// explicitly excluded it from Typebar's shared leaderboards.
    public let isLeaderboardRestricted: Bool
    /// True only for the authenticated account when it must update its display
    /// name before it can submit another shared result.
    public let isDisplayNameChangeRequired: Bool
    /// True only for the authenticated account when the deployment has applied
    /// the bounded account suspension used by the reference project.
    public let isAccountSuspended: Bool

    public init(
        isEligible: Bool, completedPracticeSeconds: Int, minimumPracticeSeconds: Int,
        isLeaderboardRestricted: Bool = false, isDisplayNameChangeRequired: Bool = false,
        isAccountSuspended: Bool = false
    ) {
        self.isEligible = isEligible
        self.completedPracticeSeconds = completedPracticeSeconds
        self.minimumPracticeSeconds = minimumPracticeSeconds
        self.isLeaderboardRestricted = isLeaderboardRestricted
        self.isDisplayNameChangeRequired = isDisplayNameChangeRequired
        self.isAccountSuspended = isAccountSuspended
    }
}

/// Startup configuration for the account practice-time gate used by Typebar's
/// own shared leaderboards. The value never changes persisted results; it only
/// changes which existing accepted results may be ranked.
public enum TypebarLeaderboardEligibilityPolicy {
    public static let defaultMinimumPracticeSeconds = 2 * 60 * 60
    public static let maximumMinimumPracticeSeconds = 365 * 24 * 60 * 60

    public static func minimumPracticeSeconds(from environmentValue: String?) throws -> Int {
        guard let environmentValue else { return defaultMinimumPracticeSeconds }
        let trimmed = environmentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), (0...maximumMinimumPracticeSeconds).contains(value) else {
            throw TypebarLeaderboardEligibilityConfigurationError.invalidMinimumPracticeSeconds
        }
        return value
    }
}

public enum TypebarLeaderboardEligibilityConfigurationError: Error, Equatable, LocalizedError {
    case invalidMinimumPracticeSeconds

    public var errorDescription: String? {
        "TYPEBAR_LEADERBOARD_MIN_PRACTICE_SECONDS must be an integer from 0 to \(TypebarLeaderboardEligibilityPolicy.maximumMinimumPracticeSeconds)."
    }
}

public struct LeaderboardRankResponse: Content, Equatable {
    public let entry: LeaderboardEntry?
    public let eligibility: LeaderboardEligibility?

    public init(entry: LeaderboardEntry?, eligibility: LeaderboardEligibility? = nil) {
        self.entry = entry
        self.eligibility = eligibility
    }
}

public struct ExperienceLeaderboardEntry: Content, Equatable, Identifiable {
    public let id: UUID
    public let rank: Int
    public let userID: UUID
    public let displayName: String
    public let totalExperience: Int
    public let selectedBadge: PublicProfileBadge?
    public let discordAvatar: PublicDiscordAvatarResponse?
}

public struct ExperienceLeaderboardQuery: Content {
    public let period: String?
    public let limit: Int?
    public let offset: Int?

    public init(period: String? = nil, limit: Int? = nil, offset: Int? = nil) {
        self.period = period
        self.limit = limit
        self.offset = offset
    }
}

public struct ExperienceLeaderboardResponse: Content, Equatable {
    public let entries: [ExperienceLeaderboardEntry]
    public let period: String
    public let total: Int
    public let offset: Int
    public let pageSize: Int
    public let rankMemorySupported: Bool

    public init(
        entries: [ExperienceLeaderboardEntry], period: String, total: Int,
        offset: Int, pageSize: Int, rankMemorySupported: Bool = true
    ) {
        self.entries = entries
        self.period = period
        self.total = total
        self.offset = offset
        self.pageSize = pageSize
        self.rankMemorySupported = rankMemorySupported
    }
}

public struct ExperienceLeaderboardRankResponse: Content, Equatable {
    public let entry: ExperienceLeaderboardEntry?
    public let period: String
    public let eligibility: LeaderboardEligibility?

    public init(
        entry: ExperienceLeaderboardEntry?, period: String,
        eligibility: LeaderboardEligibility? = nil
    ) {
        self.entry = entry
        self.period = period
        self.eligibility = eligibility
    }
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
