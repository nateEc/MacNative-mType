import Foundation
import Observation
import Security

enum RemoteAuthenticationMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case password
    case github
    case google

    var id: Self { self }

    var displayName: String {
        switch self {
        case .password: "密码"
        case .github: "GitHub"
        case .google: "Google"
        }
    }

    var oauthProvider: RemoteOAuthProvider? {
        switch self {
        case .password: nil
        case .github: .github
        case .google: .google
        }
    }
}

enum RemoteOAuthProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case github
    case google

    var id: Self { self }

    var displayName: String {
        switch self {
        case .github: "GitHub"
        case .google: "Google"
        }
    }

    var authenticationMethod: RemoteAuthenticationMethod {
        switch self {
        case .github: .github
        case .google: .google
        }
    }
}

struct RemoteProfileDetails: Codable, Equatable, Sendable {
    let bio: String
    let keyboard: String
    let github: String
    let socialHandle: String
    let websiteURL: String
    let showActivity: Bool

    private enum CodingKeys: String, CodingKey {
        case bio, keyboard, github, socialHandle, websiteURL, showActivity
    }

    init(
        bio: String = "", keyboard: String = "", github: String = "", socialHandle: String = "",
        websiteURL: String = "", showActivity: Bool = true
    ) {
        self.bio = bio
        self.keyboard = keyboard
        self.github = github
        self.socialHandle = socialHandle
        self.websiteURL = websiteURL
        self.showActivity = showActivity
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bio = try values.decodeIfPresent(String.self, forKey: .bio) ?? ""
        keyboard = try values.decodeIfPresent(String.self, forKey: .keyboard) ?? ""
        github = try values.decodeIfPresent(String.self, forKey: .github) ?? ""
        socialHandle = try values.decodeIfPresent(String.self, forKey: .socialHandle) ?? ""
        websiteURL = try values.decodeIfPresent(String.self, forKey: .websiteURL) ?? ""
        showActivity = try values.decodeIfPresent(Bool.self, forKey: .showActivity) ?? true
    }
}

struct RemoteAccountUser: Codable, Equatable, Sendable {
    let id: UUID
    let email: String
    let emailVerified: Bool
    let displayName: String
    let totalExperience: Int
    let leaderboardOptedOut: Bool
    let profileDetails: RemoteProfileDetails
    let authenticationMethods: [RemoteAuthenticationMethod]

    private enum CodingKeys: String, CodingKey {
        case id, email, emailVerified, displayName, totalExperience, leaderboardOptedOut, profileDetails,
            authenticationMethods
    }

    init(
        id: UUID,
        email: String,
        emailVerified: Bool = false,
        displayName: String,
        totalExperience: Int,
        leaderboardOptedOut: Bool = false,
        profileDetails: RemoteProfileDetails = .init(),
        authenticationMethods: [RemoteAuthenticationMethod] = [.password]
    ) {
        self.id = id
        self.email = email
        self.emailVerified = emailVerified
        self.displayName = displayName
        self.totalExperience = totalExperience
        self.leaderboardOptedOut = leaderboardOptedOut
        self.profileDetails = profileDetails
        self.authenticationMethods = authenticationMethods
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        email = try values.decode(String.self, forKey: .email)
        emailVerified = try values.decodeIfPresent(Bool.self, forKey: .emailVerified) ?? false
        displayName = try values.decode(String.self, forKey: .displayName)
        totalExperience = try values.decodeIfPresent(Int.self, forKey: .totalExperience) ?? 0
        leaderboardOptedOut = try values.decodeIfPresent(Bool.self, forKey: .leaderboardOptedOut) ?? false
        profileDetails = try values.decodeIfPresent(RemoteProfileDetails.self, forKey: .profileDetails) ?? .init()
        authenticationMethods = try values.decodeIfPresent([RemoteAuthenticationMethod].self, forKey: .authenticationMethods) ?? [.password]
    }
}

private struct RemoteAuthSession: Codable, Sendable {
    let user: RemoteAccountUser
    let accessToken: String
    let expiresAt: Date
}

private struct RemoteRegisterRequest: Codable, Sendable {
    let email: String
    let password: String
    let displayName: String
}

private struct RemoteLoginRequest: Codable, Sendable {
    let email: String
    let password: String
}

private enum RemoteOAuthPurpose: String, Codable, Sendable {
    case signIn
    case link
    case reauthenticate
}

private struct RemoteOAuthStartRequest: Codable, Sendable {
    let purpose: RemoteOAuthPurpose
}

private struct RemoteOAuthStartResponse: Codable, Sendable {
    let authorizationURL: String
}

private enum RemoteOAuthCompletionStatus: String, Codable, Sendable {
    case pending
    case exchanging
    case registrationRequired
    case signedIn
    case linked
    case reauthenticated
    case failed
}

private struct RemoteOAuthCompletionResponse: Codable, Sendable {
    let status: RemoteOAuthCompletionStatus
    let email: String?
    let suggestedDisplayName: String?
    let session: RemoteAuthSession?
    let user: RemoteAccountUser?
    let reauthenticationToken: String?
    let message: String?
}

private struct RemoteOAuthRegistrationRequest: Codable, Sendable {
    let state: String
    let displayName: String
}

struct PendingRemoteOAuthRegistration: Equatable, Sendable {
    let provider: RemoteOAuthProvider
    let state: String
    let email: String
    let suggestedDisplayName: String?
}

private struct RemoteChangePasswordRequest: Codable, Sendable {
    let currentPassword: String
    let newPassword: String
}

private struct RemoteAddPasswordAuthenticationRequest: Codable, Sendable {
    let newPassword: String
}

private struct RemoteRemovePasswordAuthenticationRequest: Codable, Sendable {
    let currentPassword: String
}

private struct RemotePasswordResetRequest: Codable, Sendable { let email: String }
private struct RemotePasswordResetRequestResponse: Codable, Sendable { let accepted: Bool }
private struct RemoteCompletePasswordResetRequest: Codable, Sendable {
    let token: String
    let newPassword: String
}
private struct RemotePasswordResetCompletionResponse: Codable, Sendable { let reset: Bool }
private struct RemoteEmailVerificationRequestResponse: Codable, Sendable { let accepted: Bool }
private struct RemoteCompleteEmailVerificationRequest: Codable, Sendable { let token: String }
private struct RemoteEmailVerificationCompletionResponse: Codable, Sendable { let verified: Bool }

private struct RemoteChangeEmailRequest: Codable, Sendable {
    let currentPassword: String
    let newEmail: String
}

private struct RemoteDeleteAccountRequest: Codable, Sendable { let currentPassword: String? }
private struct RemoteAccountDeletionResponse: Codable, Sendable { let deleted: Bool }
private struct RemoteRevokeSessionsRequest: Codable, Sendable { let currentPassword: String? }
private struct RemoteSessionsRevocationResponse: Codable, Sendable { let revoked: Bool }
private struct RemotePasswordReauthenticationRequest: Codable, Sendable { let currentPassword: String }
private struct RemoteReauthenticationResponse: Codable, Sendable { let reauthenticationToken: String }

private struct RemoteUpdateProfileRequest: Codable, Sendable {
    let displayName: String?
    let leaderboardOptedOut: Bool?
    let profileDetails: RemoteProfileDetails?
}

struct RemoteDeveloperAccessKey: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let enabled: Bool
    let createdAt: Date
    let modifiedAt: Date
    let lastUsedAt: Date?
}

private struct RemoteDeveloperAccessKeyListResponse: Codable, Sendable {
    let keys: [RemoteDeveloperAccessKey]
}

private struct RemoteCreateDeveloperAccessKeyRequest: Codable, Sendable {
    let name: String
}

private struct RemoteCreateDeveloperAccessKeyResponse: Codable, Sendable {
    let key: RemoteDeveloperAccessKey
    let accessKey: String
}

private struct RemoteUpdateDeveloperAccessKeyRequest: Codable, Sendable {
    let name: String?
    let enabled: Bool?
}

private struct RemoteDeveloperAccessKeyDeletionResponse: Codable, Sendable {
    let deleted: Bool
}

struct RemoteAccountResult: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let mode: String
    let language: String
    let durationSeconds: Int?
    let wordLimit: Int?
    let wpm: Int
    let rawWpm: Int
    let accuracy: Int
    let consistency: Double
    let errorCount: Int
    let eventCount: Int
    let tags: [String]
    let startedAt: Date
    let finishedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, mode, language, durationSeconds, wordLimit, wpm, rawWpm, accuracy, consistency,
            errorCount, eventCount, tags, startedAt, finishedAt
    }

    init(from decoder: Decoder) throws {
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
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        finishedAt = try values.decode(Date.self, forKey: .finishedAt)
    }
}

private struct RemoteAccountResultListResponse: Codable, Sendable {
    let results: [RemoteAccountResult]
    let total: Int
}

private struct RemoteResultDeletionRequest: Codable, Sendable {
    let currentPassword: String?
}

private struct RemoteResultDeletionResponse: Codable, Sendable {
    let deleted: Bool
    let removedCount: Int
}

private struct RemoteUpdateResultTagsRequest: Codable, Sendable {
    let tags: [String]
}

private struct RemoteQuoteSubmissionRequest: Codable, Sendable {
    let language: String
    let text: String
    let attribution: String?
}

struct RemoteQuoteSubmissionResponse: Codable, Sendable {
    let id: UUID
    let status: String
    let submittedAt: Date
}

private struct RemoteQuoteSubmissionListResponse: Codable, Sendable { let submissions: [RemoteQuoteSubmissionResponse] }

enum RemoteQuoteModerationStatus: String, CaseIterable, Identifiable, Sendable {
    case pending
    case approved
    case rejected

    var id: Self { self }
    var displayName: String {
        switch self {
        case .pending: "待审核"
        case .approved: "已批准"
        case .rejected: "已拒绝"
        }
    }
}

struct RemoteModerationQuoteReport: Codable, Sendable, Identifiable {
    let reason: RemoteQuoteReportReason
    let note: String?
    let submittedAt: Date

    var id: String { "\(reason.rawValue)-\(submittedAt.timeIntervalSinceReferenceDate)-\(note ?? "")" }
}

struct RemoteModerationQuote: Codable, Identifiable, Sendable {
    let id: UUID
    let language: String
    let text: String
    let attribution: String?
    let status: String
    let submittedAt: Date
    let reports: [RemoteModerationQuoteReport]
}

private struct RemoteModerationQuoteListResponse: Codable, Sendable { let quotes: [RemoteModerationQuote] }
private struct RemoteQuoteModerationRequest: Codable, Sendable { let status: String }

struct RemotePublicQuote: Codable, Identifiable, Sendable {
    let id: UUID
    let language: String
    let text: String
    let attribution: String?
    let submittedAt: Date
    let upvotes: Int
    let downvotes: Int
    let viewerRating: Int?
}

private struct RemotePublicQuoteListResponse: Codable, Sendable { let quotes: [RemotePublicQuote] }

enum RemoteQuoteRatingValue: Int, Sendable {
    case down = -1
    case neutral = 0
    case up = 1
}

private struct RemoteQuoteRatingRequest: Codable, Sendable { let value: Int }
struct RemoteQuoteRatingResponse: Codable, Sendable {
    let quoteID: UUID
    let upvotes: Int
    let downvotes: Int
    let viewerRating: Int?
}

enum RemoteQuoteReportReason: String, CaseIterable, Codable, Sendable {
    case copyright, abusiveContent, inaccurateAttribution, other

    var displayName: String {
        switch self {
        case .copyright: "版权或授权问题"
        case .abusiveContent: "不当内容"
        case .inaccurateAttribution: "署名或来源不准确"
        case .other: "其他"
        }
    }
}
private struct RemoteQuoteReportRequest: Codable, Sendable { let quoteID: UUID; let reason: RemoteQuoteReportReason; let note: String? }
private struct RemoteQuoteReportResponse: Codable, Sendable { let id: UUID; let submittedAt: Date }

private struct RemoteSyncChange: Codable, Sendable {
    let id: UUID
    let type: String
    let version: Int
    let payload: String?
    let isDeleted: Bool
}

private struct RemoteSyncPushRequest: Codable, Sendable {
    let changes: [RemoteSyncChange]
}

private struct RemoteSyncPushResult: Codable, Sendable {
    let id: UUID
    let status: String
    let serverVersion: Int
}

private struct RemoteSyncPushResponse: Codable, Sendable {
    let results: [RemoteSyncPushResult]
    let nextCursor: Int
}

struct RemoteSyncPullChange: Codable, Sendable {
    let id: UUID
    let type: String
    let version: Int
    let payload: String?
    let isDeleted: Bool
    let cursor: Int
}

struct RemoteSyncPullResponse: Codable, Sendable {
    let changes: [RemoteSyncPullChange]
    let nextCursor: Int
    let hasMore: Bool

    private enum CodingKeys: String, CodingKey { case changes, nextCursor, hasMore }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        changes = try values.decode([RemoteSyncPullChange].self, forKey: .changes)
        nextCursor = try values.decode(Int.self, forKey: .nextCursor)
        // Self-hosted servers from before paged pulls omit this key and return the
        // entire change set, so treating it as the final page is backward-compatible.
        hasMore = try values.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
    }
}

struct RemoteArchivePull {
    let archive: TypebarArchive?
    let nextCursor: Int
    let archiveVersion: Int?
}

private struct RemoteResultSubmission: Codable, Sendable {
    let id: UUID
    let mode: String
    let language: String
    let durationSeconds: Int?
    let wordLimit: Int?
    let wpm: Int
    let rawWpm: Int
    let accuracy: Int
    let consistency: Double
    let errorCount: Int
    let eventCount: Int
    let tags: [String]
    let startedAt: Date
    let finishedAt: Date

    init(result: CompletedTestResult) {
        id = result.id
        mode = result.configuration.mode.rawValue
        language = result.configuration.language.rawValue
        durationSeconds = result.configuration.duration.map { Int($0) }
        wordLimit = result.configuration.wordLimit
        wpm = result.wpm
        rawWpm = result.rawWpm
        accuracy = result.accuracy
        consistency = ResultConsistencyPolicy.metrics(
            events: result.replayEvents, duration: result.elapsedDuration
        ).typing
        errorCount = result.errorCount
        eventCount = result.typedCharacterCount
        tags = result.tags
        startedAt = result.startedAt
        finishedAt = result.finishedAt
    }
}

struct RemoteResultSubmissionResponse: Codable, Sendable {
    let id: UUID
    let accepted: Bool
    let leaderboardEligible: Bool
    let experienceGained: Int
    let totalExperience: Int
    let weeklyExperienceRank: Int?

    private enum CodingKeys: String, CodingKey { case id, accepted, leaderboardEligible, experienceGained, totalExperience, weeklyExperienceRank }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        accepted = try values.decode(Bool.self, forKey: .accepted)
        leaderboardEligible = try values.decode(Bool.self, forKey: .leaderboardEligible)
        experienceGained = try values.decodeIfPresent(Int.self, forKey: .experienceGained) ?? 0
        totalExperience = try values.decodeIfPresent(Int.self, forKey: .totalExperience) ?? 0
        weeklyExperienceRank = try values.decodeIfPresent(Int.self, forKey: .weeklyExperienceRank)
    }
}

struct RemoteLeaderboardEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let rank: Int
    let userID: UUID
    let displayName: String
    let mode: String
    let language: String
    let wpm: Int
    let accuracy: Int
    let consistency: Double
    let finishedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, rank, userID, displayName, mode, language, wpm, accuracy, consistency, finishedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        rank = try values.decode(Int.self, forKey: .rank)
        userID = try values.decode(UUID.self, forKey: .userID)
        displayName = try values.decode(String.self, forKey: .displayName)
        mode = try values.decode(String.self, forKey: .mode)
        language = try values.decode(String.self, forKey: .language)
        wpm = try values.decode(Int.self, forKey: .wpm)
        accuracy = try values.decode(Int.self, forKey: .accuracy)
        consistency = try values.decodeIfPresent(Double.self, forKey: .consistency) ?? 0
        finishedAt = try values.decode(Date.self, forKey: .finishedAt)
    }
}

struct RemoteLeaderboardResponse: Codable, Sendable {
    let entries: [RemoteLeaderboardEntry]
}

struct RemoteLeaderboardRankResponse: Codable, Sendable {
    let entry: RemoteLeaderboardEntry?
}

struct RemoteExperienceLeaderboardEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let rank: Int
    let userID: UUID
    let displayName: String
    let totalExperience: Int
}

private struct RemoteExperienceLeaderboardResponse: Codable, Sendable {
    let entries: [RemoteExperienceLeaderboardEntry]
}

struct RemoteExperienceLeaderboardRankResponse: Codable, Sendable {
    let entry: RemoteExperienceLeaderboardEntry?
}

struct RemotePublicProfile: Codable, Identifiable, Sendable {
    let id: UUID
    let displayName: String
    let joinedAt: Date
    let completedResultCount: Int
    let bestWPM: Int
    let highestConsistency: Double
    let personalBests: [RemotePublicProfileBest]
    let activity: RemotePublicProfileActivity?
    let totalExperience: Int
    let profileDetails: RemoteProfileDetails

    private enum CodingKeys: String, CodingKey {
        case id, displayName, joinedAt, completedResultCount, bestWPM, highestConsistency, personalBests,
            activity, totalExperience, profileDetails
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        displayName = try values.decode(String.self, forKey: .displayName)
        joinedAt = try values.decode(Date.self, forKey: .joinedAt)
        completedResultCount = try values.decode(Int.self, forKey: .completedResultCount)
        bestWPM = try values.decode(Int.self, forKey: .bestWPM)
        highestConsistency = try values.decodeIfPresent(Double.self, forKey: .highestConsistency) ?? 0
        personalBests = try values.decodeIfPresent([RemotePublicProfileBest].self, forKey: .personalBests) ?? []
        activity = try values.decodeIfPresent(RemotePublicProfileActivity.self, forKey: .activity)
        totalExperience = try values.decodeIfPresent(Int.self, forKey: .totalExperience) ?? 0
        profileDetails = try values.decodeIfPresent(RemoteProfileDetails.self, forKey: .profileDetails) ?? .init()
    }
}

struct RemotePublicProfileBest: Codable, Identifiable, Sendable {
    let id: UUID
    let mode: String
    let durationSeconds: Int?
    let wordLimit: Int?
    let language: String
    let wpm: Int
    let accuracy: Int
    let consistency: Double
    let finishedAt: Date

    var configurationLabel: String {
        if mode == "time", let durationSeconds { return "\(durationSeconds) 秒" }
        if mode == "words", let wordLimit { return "\(wordLimit) 词" }
        return mode
    }

    var languageLabel: String {
        TypingLanguage(rawValue: language)?.displayName ?? language
    }
}

struct RemotePublicProfileActivity: Codable, Sendable {
    let lastDay: Date
    let testsByDays: [Int]
}

private struct RemotePublicProfileSearchResponse: Codable, Sendable {
    let profiles: [RemotePublicProfile]
}

enum RemoteProfileReportReason: String, CaseIterable, Codable, Sendable {
    case misleadingProfile
    case abusiveName
    case inappropriateBio
    case inappropriateLinks
    case suspiciousResults
    case other

    var displayName: String {
        switch self {
        case .misleadingProfile: "资料具有误导性"
        case .abusiveName: "显示名不当"
        case .inappropriateBio: "简介不当"
        case .inappropriateLinks: "链接不当"
        case .suspiciousResults: "成绩看起来异常"
        case .other: "其他问题"
        }
    }
}

enum RemoteProfileModerationStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case open
    case resolved
    case dismissed

    var id: Self { self }
    var displayName: String {
        switch self {
        case .open: "待处理"
        case .resolved: "已处理"
        case .dismissed: "已驳回"
        }
    }
}

struct RemoteModerationProfileReport: Codable, Identifiable, Sendable {
    let id: UUID
    let profile: RemotePublicProfile
    let reason: RemoteProfileReportReason
    let note: String?
    let status: RemoteProfileModerationStatus
    let submittedAt: Date
}

private struct RemoteModerationProfileReportListResponse: Codable, Sendable { let reports: [RemoteModerationProfileReport] }
private struct RemoteProfileReportModerationRequest: Codable, Sendable { let status: RemoteProfileModerationStatus }

private struct RemoteProfileReportRequest: Codable, Sendable {
    let profileID: UUID
    let reason: RemoteProfileReportReason
    let note: String?
}

struct RemoteProfileReportResponse: Codable, Sendable {
    let id: UUID
    let submittedAt: Date
}

private struct RemoteConnectionRequest: Codable, Sendable {
    let recipientID: UUID
}

enum RemoteConnectionRelation: String, Codable, Sendable {
    case outgoingRequest
    case incomingRequest
    case friend
}

struct RemoteConnection: Codable, Identifiable, Sendable {
    let id: UUID
    let profile: RemotePublicProfile
    let relation: RemoteConnectionRelation
    let updatedAt: Date
}

private struct RemoteConnectionsResponse: Codable, Sendable {
    let connections: [RemoteConnection]
}

private struct RemoteConnectionRemovalResponse: Codable, Sendable {
    let removed: Bool
}

private struct RemoteDirectMessageRequest: Codable, Sendable {
    let recipientID: UUID
    let body: String
}

struct RemoteDirectMessage: Codable, Identifiable, Sendable {
    let id: UUID
    let senderID: UUID
    let recipientID: UUID
    let body: String
    let createdAt: Date
    let readAt: Date?
}

private struct RemoteDirectConversationResponse: Codable, Sendable {
    let messages: [RemoteDirectMessage]
}

private struct RemoteBlockedUsersResponse: Codable, Sendable { let profiles: [RemotePublicProfile] }

enum RemoteNotificationKind: String, Codable, Sendable {
    case connectionRequest
    case connectionAccepted
    case directMessage
}

struct RemoteNotification: Codable, Identifiable, Sendable {
    let id: UUID
    let kind: RemoteNotificationKind
    let actor: RemotePublicProfile
    let createdAt: Date
    let readAt: Date?
}

private struct RemoteNotificationsResponse: Codable, Sendable { let notifications: [RemoteNotification] }

enum RemoteLeaderboardPeriod: String, CaseIterable {
    case all
    case day
    case week

    var displayName: String {
        switch self {
        case .all: "全部时间"
        case .day: "今天"
        case .week: "本周"
        }
    }
}

enum RemoteLeaderboardScope: String, CaseIterable {
    case global
    case friends

    var displayName: String {
        switch self {
        case .global: "全局榜"
        case .friends: "好友榜"
        }
    }
}

enum RemoteAccountError: LocalizedError {
    case invalidServerURL
    case invalidOAuthCallback
    case oauthAuthorizationCancelled
    case oauthAuthorizationInProgress
    case serverMessage(String)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: "请输入有效的 Typebar 服务地址。"
        case .invalidOAuthCallback: "第三方登录返回了无法识别的回调。"
        case .oauthAuthorizationCancelled: "第三方登录已取消。"
        case .oauthAuthorizationInProgress: "已有一个第三方登录正在进行。"
        case .serverMessage(let message): message
        case .unexpectedResponse: "服务返回了无法识别的响应。"
        }
    }
}

@MainActor
@Observable
final class AccountSession {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let endpointKey = "remoteAccount.endpoint.v1"
    @ObservationIgnored private let syncIDKey = "remoteAccount.archiveSyncID.v1"
    @ObservationIgnored private let syncVersionKey = "remoteAccount.archiveSyncVersion.v1"
    @ObservationIgnored private let syncCursorKey = "remoteAccount.syncCursor.v1"
    @ObservationIgnored private let tokenStore = AccountTokenStore()
    @ObservationIgnored private let oauthBrowser = OAuthWebAuthenticationSession()

    var endpoint = "http://127.0.0.1:8080" { didSet { defaults.set(endpoint, forKey: endpointKey) } }
    var currentUser: RemoteAccountUser? {
        didSet {
            if currentUser == nil {
                developerAccessKeys = []
                remoteResults = []
            }
        }
    }
    var developerAccessKeys: [RemoteDeveloperAccessKey] = []
    var remoteResults: [RemoteAccountResult] = []
    var pendingOAuthRegistration: PendingRemoteOAuthRegistration?
    var isWorking = false
    var statusMessage: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        endpoint = defaults.string(forKey: endpointKey) ?? "http://127.0.0.1:8080"
    }

    func restoreSession() async {
        guard tokenStore.load() != nil else { return }
        await refreshProfile()
    }

    func register(email: String, password: String, displayName: String) async {
        await performAuth(path: "v1/auth/register", body: RemoteRegisterRequest(email: email, password: password, displayName: displayName))
    }

    func login(email: String, password: String) async {
        await performAuth(path: "v1/auth/login", body: RemoteLoginRequest(email: email, password: password))
    }

    func signInWithOAuth(_ provider: RemoteOAuthProvider) async {
        await beginOAuth(provider: provider, purpose: .signIn, accessToken: nil)
    }

    func linkOAuth(_ provider: RemoteOAuthProvider) async {
        do {
            await beginOAuth(provider: provider, purpose: .link, accessToken: try accessToken())
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func completeOAuthRegistration(displayName: String) async -> Bool {
        guard let pending = pendingOAuthRegistration else {
            statusMessage = "没有等待完成的第三方注册。"
            return false
        }
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedDisplayName.count >= 2 else {
            statusMessage = "显示名至少需要 2 个字符。"
            return false
        }

        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/auth/oauth/registration",
                method: "POST",
                token: nil,
                body: RemoteOAuthRegistrationRequest(state: pending.state, displayName: normalizedDisplayName),
                response: RemoteAuthSession.self
            )
            try applyAuthenticatedSession(session)
            statusMessage = "已使用 \(pending.provider.displayName) 登录。"
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func cancelOAuthRegistration() {
        pendingOAuthRegistration = nil
    }

    func unlinkOAuth(_ provider: RemoteOAuthProvider, currentPassword: String?) async {
        guard let token = tokenStore.load(), let user = currentUser else {
            statusMessage = "请先登录自建 Typebar 服务。"
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let freshReauthenticationToken = try await reauthenticationToken(
                for: user,
                accessToken: token,
                excluding: provider.authenticationMethod,
                currentPassword: currentPassword
            )
            currentUser = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/auth/oauth/\(provider.rawValue)",
                method: "DELETE",
                token: token,
                body: Optional<String>.none,
                headers: ["X-Typebar-Reauthentication": freshReauthenticationToken],
                response: RemoteAccountUser.self
            )
            statusMessage = "已移除 \(provider.displayName) 登录方式。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func requestPasswordReset(email: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/auth/password-reset/request",
                method: "POST",
                token: nil,
                body: RemotePasswordResetRequest(email: email),
                response: RemotePasswordResetRequestResponse.self
            )
            guard response.accepted else { throw RemoteAccountError.unexpectedResponse }
            statusMessage = "若该邮箱已注册，重置码已发送；请粘贴邮件中的重置码。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func completePasswordReset(token: String, newPassword: String) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/auth/password-reset/complete",
                method: "POST",
                token: nil,
                body: RemoteCompletePasswordResetRequest(token: token, newPassword: newPassword),
                response: RemotePasswordResetCompletionResponse.self
            )
            guard response.reset else { throw RemoteAccountError.unexpectedResponse }
            tokenStore.clear()
            currentUser = nil
            statusMessage = "密码已重置；请使用新密码登录。"
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func requestEmailVerification() async {
        guard let token = tokenStore.load(), currentUser != nil else {
            statusMessage = "请先登录自建 Typebar 服务。"
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/auth/email-verification/request",
                method: "POST",
                token: token,
                body: Optional<String>.none,
                response: RemoteEmailVerificationRequestResponse.self
            )
            guard response.accepted else { throw RemoteAccountError.unexpectedResponse }
            statusMessage = "验证邮件已发送；请粘贴邮件中的验证码。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func completeEmailVerification(token: String) async -> Bool {
        guard let accessToken = tokenStore.load(), currentUser != nil else {
            statusMessage = "请先登录自建 Typebar 服务。"
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/auth/email-verification/complete",
                method: "POST",
                token: nil,
                body: RemoteCompleteEmailVerificationRequest(token: token),
                response: RemoteEmailVerificationCompletionResponse.self
            )
            guard response.verified else { throw RemoteAccountError.unexpectedResponse }
            currentUser = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/profiles/me",
                method: "GET",
                token: accessToken,
                body: Optional<String>.none,
                response: RemoteAccountUser.self
            )
            statusMessage = "邮箱已验证。"
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func changePassword(currentPassword: String, newPassword: String) async {
        guard let token = tokenStore.load(), currentUser != nil else {
            statusMessage = "请先登录自建 Typebar 服务。"
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/auth/password",
                method: "POST",
                token: token,
                body: RemoteChangePasswordRequest(currentPassword: currentPassword, newPassword: newPassword),
                response: RemoteAuthSession.self
            )
            try tokenStore.save(session.accessToken)
            currentUser = session.user
            statusMessage = "密码已更新；其他设备的登录会话已失效。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func addPasswordAuthentication(newPassword: String) async -> Bool {
        guard let token = tokenStore.load(), let user = currentUser else {
            statusMessage = "请先登录自建 Typebar 服务。"
            return false
        }
        guard newPassword.utf8.count >= 12 else {
            statusMessage = "新密码至少需要 12 个字节。"
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let freshReauthenticationToken = try await reauthenticationToken(
                for: user, accessToken: token, excluding: nil, currentPassword: nil)
            currentUser = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/auth/password/add",
                method: "POST",
                token: token,
                body: RemoteAddPasswordAuthenticationRequest(newPassword: newPassword),
                headers: ["X-Typebar-Reauthentication": freshReauthenticationToken],
                response: RemoteAccountUser.self
            )
            statusMessage = "密码登录方式已添加。"
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func removePasswordAuthentication(currentPassword: String) async {
        guard let token = tokenStore.load(), currentUser != nil else {
            statusMessage = "请先登录自建 Typebar 服务。"
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            currentUser = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/auth/password",
                method: "DELETE",
                token: token,
                body: RemoteRemovePasswordAuthenticationRequest(currentPassword: currentPassword),
                response: RemoteAccountUser.self
            )
            statusMessage = "密码登录方式已移除；其他设备的登录会话已失效。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func changeEmail(currentPassword: String, newEmail: String) async {
        guard let token = tokenStore.load(), currentUser != nil else {
            statusMessage = "请先登录自建 Typebar 服务。"
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/auth/email",
                method: "POST",
                token: token,
                body: RemoteChangeEmailRequest(currentPassword: currentPassword, newEmail: newEmail),
                response: RemoteAuthSession.self
            )
            try tokenStore.save(session.accessToken)
            currentUser = session.user
            statusMessage = "邮箱已更新；其他设备的登录会话已失效。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteAccount(currentPassword: String?) async {
        guard let token = tokenStore.load(), let user = currentUser else {
            statusMessage = "请先登录自建 Typebar 服务。"
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let usesPassword = user.authenticationMethods.contains(.password)
            let freshReauthenticationToken = usesPassword
                ? nil
                : try await reauthenticationToken(
                    for: user, accessToken: token, excluding: nil, currentPassword: nil)
            let response = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/auth/account",
                method: "DELETE",
                token: token,
                body: RemoteDeleteAccountRequest(currentPassword: currentPassword),
                headers: freshReauthenticationToken.map { ["X-Typebar-Reauthentication": $0] } ?? [:],
                response: RemoteAccountDeletionResponse.self
            )
            guard response.deleted else { throw RemoteAccountError.unexpectedResponse }
            tokenStore.clear()
            currentUser = nil
            statusMessage = "账户及其自建服务数据已删除；本机练习记录未受影响。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func revokeAllSessions(currentPassword: String?) async -> Bool {
        guard let token = tokenStore.load(), let user = currentUser else {
            statusMessage = "请先登录自建 Typebar 服务。"
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let usesPassword = user.authenticationMethods.contains(.password)
            let freshReauthenticationToken = usesPassword
                ? nil
                : try await reauthenticationToken(
                    for: user, accessToken: token, excluding: nil, currentPassword: nil)
            let response = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/auth/sessions/revoke",
                method: "POST",
                token: token,
                body: RemoteRevokeSessionsRequest(currentPassword: currentPassword),
                headers: freshReauthenticationToken.map { ["X-Typebar-Reauthentication": $0] } ?? [:],
                response: RemoteSessionsRevocationResponse.self
            )
            guard response.revoked else { throw RemoteAccountError.unexpectedResponse }
            tokenStore.clear()
            currentUser = nil
            statusMessage = "所有设备的登录会话已撤销；请重新登录。"
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func updateDisplayName(_ displayName: String) async {
        guard let token = tokenStore.load(), currentUser != nil else {
            statusMessage = "请先登录自建 Typebar 服务。"
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            currentUser = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/profiles/me",
                method: "PATCH",
                token: token,
                body: RemoteUpdateProfileRequest(
                    displayName: displayName,
                    leaderboardOptedOut: currentUser?.leaderboardOptedOut ?? false,
                    profileDetails: nil),
                response: RemoteAccountUser.self
            )
            statusMessage = "显示名已更新。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func setLeaderboardOptOut(_ optedOut: Bool) async {
        guard let token = tokenStore.load(), let user = currentUser else {
            statusMessage = "请先登录自建 Typebar 服务。"
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            currentUser = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/profiles/me",
                method: "PATCH",
                token: token,
                body: RemoteUpdateProfileRequest(
                    displayName: user.displayName, leaderboardOptedOut: optedOut, profileDetails: nil),
                response: RemoteAccountUser.self
            )
            statusMessage = optedOut
                ? "你已从自建服务的 WPM 和 XP 排行榜隐藏。"
                : "你已重新显示在自建服务的排行榜中。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func updateProfileDetails(_ details: RemoteProfileDetails) async -> Bool {
        guard let token = tokenStore.load(), currentUser != nil else {
            statusMessage = "请先登录自建 Typebar 服务。"
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            currentUser = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/profiles/me",
                method: "PATCH",
                token: token,
                body: RemoteUpdateProfileRequest(
                    displayName: nil, leaderboardOptedOut: nil, profileDetails: details),
                response: RemoteAccountUser.self
            )
            statusMessage = "公开资料已更新。"
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func refreshDeveloperAccessKeys() async {
        guard let token = tokenStore.load(), currentUser != nil else {
            developerAccessKeys = []
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            developerAccessKeys = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/developer-keys", method: "GET", token: token,
                body: Optional<String>.none, response: RemoteDeveloperAccessKeyListResponse.self
            ).keys
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshRemoteResults(limit: Int = 20) async {
        guard let token = tokenStore.load(), currentUser != nil else {
            remoteResults = []
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            remoteResults = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/results", method: "GET", token: token,
                body: Optional<String>.none,
                queryItems: [URLQueryItem(name: "limit", value: "\(min(max(limit, 1), 100))")],
                response: RemoteAccountResultListResponse.self
            ).results
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteRemoteResults(currentPassword: String?) async -> Bool {
        guard let token = tokenStore.load(), let user = currentUser else {
            statusMessage = "请先登录自建 Typebar 服务。"
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let usesPassword = user.authenticationMethods.contains(.password)
            let freshReauthenticationToken = usesPassword
                ? nil
                : try await reauthenticationToken(
                    for: user, accessToken: token, excluding: nil, currentPassword: nil)
            let response = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/results",
                method: "DELETE",
                token: token,
                body: RemoteResultDeletionRequest(currentPassword: currentPassword),
                headers: freshReauthenticationToken.map { ["X-Typebar-Reauthentication": $0] } ?? [:],
                response: RemoteResultDeletionResponse.self
            )
            guard response.deleted else { throw RemoteAccountError.unexpectedResponse }
            remoteResults = []
            currentUser = .init(
                id: user.id, email: user.email, emailVerified: user.emailVerified,
                displayName: user.displayName, totalExperience: 0,
                leaderboardOptedOut: user.leaderboardOptedOut,
                profileDetails: user.profileDetails,
                authenticationMethods: user.authenticationMethods)
            statusMessage = "已清除 (response.removedCount) 条服务端成绩；本机练习历史未受影响。"
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func updateRemoteResultTags(id: UUID, tags: [String]) async {
        guard let token = tokenStore.load(), currentUser != nil else {
            statusMessage = "请先登录自建 Typebar 服务。"
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/results/\(id.uuidString)/tags",
                method: "PATCH",
                token: token,
                body: RemoteUpdateResultTagsRequest(tags: tags),
                response: RemoteAccountResult.self
            )
            if let index = remoteResults.firstIndex(where: { $0.id == id }) {
                remoteResults[index] = result
            }
            statusMessage = "服务端成绩标签已更新。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func createDeveloperAccessKey(name: String) async -> String? {
        guard let token = tokenStore.load(), currentUser != nil else {
            statusMessage = "请先登录自建 Typebar 服务。"
            return nil
        }
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            statusMessage = "请输入开发者密钥名称。"
            return nil
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/developer-keys", method: "POST", token: token,
                body: RemoteCreateDeveloperAccessKeyRequest(name: normalizedName),
                response: RemoteCreateDeveloperAccessKeyResponse.self
            )
            developerAccessKeys.insert(response.key, at: 0)
            statusMessage = "开发者密钥已创建；请立即保存明文。"
            return response.accessKey
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    func updateDeveloperAccessKey(id: UUID, name: String? = nil, enabled: Bool? = nil) async {
        guard let token = tokenStore.load(), currentUser != nil else {
            statusMessage = "请先登录自建 Typebar 服务。"
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let key = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/developer-keys/\(id.uuidString)", method: "PATCH", token: token,
                body: RemoteUpdateDeveloperAccessKeyRequest(name: name, enabled: enabled),
                response: RemoteDeveloperAccessKey.self
            )
            if let index = developerAccessKeys.firstIndex(where: { $0.id == key.id }) {
                developerAccessKeys[index] = key
            }
            statusMessage = "开发者密钥已更新。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteDeveloperAccessKey(id: UUID) async {
        guard let token = tokenStore.load(), currentUser != nil else {
            statusMessage = "请先登录自建 Typebar 服务。"
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/developer-keys/\(id.uuidString)", method: "DELETE", token: token,
                body: Optional<String>.none, response: RemoteDeveloperAccessKeyDeletionResponse.self
            )
            guard response.deleted else { throw RemoteAccountError.unexpectedResponse }
            developerAccessKeys.removeAll { $0.id == id }
            statusMessage = "开发者密钥已删除。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func submitQuote(language: TypingLanguage, text: String, attribution: String?) async {
        guard let token = tokenStore.load(), currentUser != nil else { statusMessage = "请先登录自建 Typebar 服务。"; return }
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await RemoteAccountAPI(endpoint: endpoint).request(path: "v1/quotes", method: "POST", token: token, body: RemoteQuoteSubmissionRequest(language: language.rawValue, text: text, attribution: attribution), response: RemoteQuoteSubmissionResponse.self)
            statusMessage = response.status == "pending" ? "引语已提交，等待审核。" : "引语已提交。"
        } catch { statusMessage = error.localizedDescription }
    }

    func quoteSubmissions() async throws -> [RemoteQuoteSubmissionResponse] {
        let token = try accessToken()
        return try await RemoteAccountAPI(endpoint: endpoint).request(path: "v1/quotes/mine", method: "GET", token: token, body: Optional<String>.none, response: RemoteQuoteSubmissionListResponse.self).submissions
    }

    func withdrawQuoteSubmission(_ id: UUID) async throws {
        let token = try accessToken()
        let response = try await RemoteAccountAPI(endpoint: endpoint).request(path: "v1/quotes/\(id.uuidString)", method: "DELETE", token: token, body: Optional<String>.none, response: RemoteConnectionRemovalResponse.self)
        guard response.removed else { throw RemoteAccountError.unexpectedResponse }
    }

    func moderationQuotes(key: String, status: RemoteQuoteModerationStatus) async throws -> [RemoteModerationQuote] {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else { throw RemoteAccountError.serverMessage("请输入部署者配置的审核密钥。") }
        return try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/moderation/quotes", method: "GET", token: nil, body: Optional<String>.none,
            queryItems: [.init(name: "status", value: status.rawValue), .init(name: "limit", value: "100")],
            headers: ["X-Typebar-Moderation-Key": normalizedKey], response: RemoteModerationQuoteListResponse.self
        ).quotes
    }

    func moderateQuote(_ id: UUID, key: String, status: RemoteQuoteModerationStatus) async throws {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else { throw RemoteAccountError.serverMessage("请输入部署者配置的审核密钥。") }
        _ = try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/moderation/quotes/\(id.uuidString)", method: "PATCH", token: nil,
            body: RemoteQuoteModerationRequest(status: status.rawValue),
            headers: ["X-Typebar-Moderation-Key": normalizedKey], response: RemoteQuoteSubmissionResponse.self
        )
    }

    func moderationProfileReports(key: String, status: RemoteProfileModerationStatus) async throws -> [RemoteModerationProfileReport] {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else { throw RemoteAccountError.serverMessage("请输入部署者配置的审核密钥。") }
        return try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/moderation/profile-reports", method: "GET", token: nil, body: Optional<String>.none,
            queryItems: [.init(name: "status", value: status.rawValue), .init(name: "limit", value: "100")],
            headers: ["X-Typebar-Moderation-Key": normalizedKey], response: RemoteModerationProfileReportListResponse.self
        ).reports
    }

    func moderateProfileReport(_ id: UUID, key: String, status: RemoteProfileModerationStatus) async throws {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else { throw RemoteAccountError.serverMessage("请输入部署者配置的审核密钥。") }
        _ = try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/moderation/profile-reports/\(id.uuidString)", method: "PATCH", token: nil,
            body: RemoteProfileReportModerationRequest(status: status),
            headers: ["X-Typebar-Moderation-Key": normalizedKey], response: RemoteModerationProfileReport.self
        )
    }

    func publicQuotes(language: TypingLanguage) async throws -> [RemotePublicQuote] {
        try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/quotes", method: "GET", token: tokenStore.load(),
            body: Optional<String>.none,
            queryItems: [.init(name: "language", value: language.rawValue), .init(name: "limit", value: "100")],
            response: RemotePublicQuoteListResponse.self
        ).quotes
    }

    func rateQuote(_ quoteID: UUID, value: RemoteQuoteRatingValue) async throws -> RemoteQuoteRatingResponse {
        let token = try accessToken()
        return try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/quotes/\(quoteID.uuidString)/rating", method: "PUT", token: token,
            body: RemoteQuoteRatingRequest(value: value.rawValue), response: RemoteQuoteRatingResponse.self
        )
    }

    func reportQuote(_ quoteID: UUID, reason: RemoteQuoteReportReason, note: String?) async throws {
        let token = try accessToken()
        let normalizedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/reports/quotes", method: "POST", token: token,
            body: RemoteQuoteReportRequest(quoteID: quoteID, reason: reason, note: normalizedNote?.isEmpty == true ? nil : normalizedNote),
            response: RemoteQuoteReportResponse.self
        )
    }

    func refreshProfile() async {
        guard let token = tokenStore.load() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            currentUser = try await RemoteAccountAPI(endpoint: endpoint).request(path: "v1/profiles/me", method: "GET", token: token, body: Optional<String>.none, response: RemoteAccountUser.self)
            statusMessage = nil
        } catch {
            currentUser = nil
            statusMessage = error.localizedDescription
        }
    }

    func signOut() {
        tokenStore.clear()
        currentUser = nil
        developerAccessKeys = []
        remoteResults = []
        pendingOAuthRegistration = nil
        statusMessage = nil
    }

    func pushArchive(_ archive: TypebarArchive) async throws -> Int {
        isWorking = true
        defer { isWorking = false }
        guard let token = tokenStore.load() else { throw RemoteAccountError.serverMessage("请先登录自建 Typebar 服务。") }
        let payload = try String(decoding: JSONEncoder.remote.encode(archive), as: UTF8.self)
        let id = archiveSyncID()
        let nextVersion = defaults.integer(forKey: syncVersionKey) + 1
        let response = try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/sync",
            method: "POST",
            token: token,
            body: RemoteSyncPushRequest(changes: [.init(id: id, type: "typebar-archive", version: nextVersion, payload: payload, isDeleted: false)]),
            response: RemoteSyncPushResponse.self
        )
        guard let result = response.results.first(where: { $0.id == id }) else { throw RemoteAccountError.unexpectedResponse }
        guard result.status == "accepted" else { throw RemoteAccountError.serverMessage("服务器存在更新冲突；请先拉取同步数据。") }
        defaults.set(nextVersion, forKey: syncVersionKey)
        return response.nextCursor
    }

    func pullArchive() async throws -> RemoteArchivePull {
        isWorking = true
        defer { isWorking = false }
        guard let token = tokenStore.load() else { throw RemoteAccountError.serverMessage("请先登录自建 Typebar 服务。") }
        var cursor = defaults.integer(forKey: syncCursorKey)
        var latestArchiveChange: RemoteSyncPullChange?

        while true {
            let response = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/sync",
                method: "GET",
                token: token,
                body: Optional<String>.none,
                queryItems: [
                    URLQueryItem(name: "cursor", value: "\(cursor)"),
                    URLQueryItem(name: "limit", value: "100")
                ],
                response: RemoteSyncPullResponse.self
            )
            guard response.nextCursor >= cursor else { throw RemoteAccountError.unexpectedResponse }
            if let newest = response.changes
                .filter({ $0.type == "typebar-archive" })
                .max(by: { $0.cursor < $1.cursor })
              , (latestArchiveChange?.cursor ?? -1) < newest.cursor
            {
                latestArchiveChange = newest
            }
            guard response.hasMore else {
                let archive = try latestArchiveChange.flatMap { change -> TypebarArchive? in
                    guard !change.isDeleted, let payload = change.payload else { return nil }
                    return try TypebarDataTransfer.importArchive(from: Data(payload.utf8))
                }
                return .init(
                    archive: archive, nextCursor: response.nextCursor,
                    archiveVersion: latestArchiveChange?.version)
            }
            guard response.nextCursor > cursor else { throw RemoteAccountError.unexpectedResponse }
            cursor = response.nextCursor
        }
    }

    func confirmPulledArchive(_ pull: RemoteArchivePull) {
        defaults.set(pull.nextCursor, forKey: syncCursorKey)
        if let version = pull.archiveVersion {
            defaults.set(max(defaults.integer(forKey: syncVersionKey), version), forKey: syncVersionKey)
        }
    }

    func submitCompletedResult(_ result: CompletedTestResult) async throws -> RemoteResultSubmissionResponse {
        guard let token = tokenStore.load(), currentUser != nil else {
            throw RemoteAccountError.serverMessage("请先登录自建 Typebar 服务。")
        }
        let response = try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/results",
            method: "POST",
            token: token,
            body: RemoteResultSubmission(result: result),
            response: RemoteResultSubmissionResponse.self
        )
        guard response.id == result.id, response.accepted else { throw RemoteAccountError.unexpectedResponse }
        if let user = currentUser {
            currentUser = .init(
                id: user.id,
                email: user.email,
                emailVerified: user.emailVerified,
                displayName: user.displayName,
                totalExperience: response.totalExperience,
                leaderboardOptedOut: user.leaderboardOptedOut,
                authenticationMethods: user.authenticationMethods
            )
        }
        return response
    }

    func leaderboard(mode: TestMode?, language: TypingLanguage?, period: RemoteLeaderboardPeriod, scope: RemoteLeaderboardScope = .global, limit: Int = 25) async throws -> [RemoteLeaderboardEntry] {
        var queryItems = [
            URLQueryItem(name: "period", value: period.rawValue),
            URLQueryItem(name: "limit", value: "\(min(max(limit, 1), 100))")
        ]
        if let mode { queryItems.append(.init(name: "mode", value: mode.rawValue)) }
        if let language { queryItems.append(.init(name: "language", value: language.rawValue)) }
        let response = try await RemoteAccountAPI(endpoint: endpoint).request(
            path: scope == .friends ? "v1/leaderboards/friends" : "v1/leaderboards",
            method: "GET",
            token: scope == .friends ? try accessToken() : nil,
            body: Optional<String>.none,
            queryItems: queryItems,
            response: RemoteLeaderboardResponse.self
        )
        return response.entries
    }

    func leaderboardRank(
        mode: TestMode?, language: TypingLanguage?, period: RemoteLeaderboardPeriod,
        scope: RemoteLeaderboardScope = .global
    ) async throws -> RemoteLeaderboardEntry? {
        var queryItems = [URLQueryItem(name: "period", value: period.rawValue)]
        if let mode { queryItems.append(.init(name: "mode", value: mode.rawValue)) }
        if let language { queryItems.append(.init(name: "language", value: language.rawValue)) }
        let response = try await RemoteAccountAPI(endpoint: endpoint).request(
            path: scope == .friends ? "v1/leaderboards/friends/rank" : "v1/leaderboards/rank",
            method: "GET",
            token: try accessToken(),
            body: Optional<String>.none,
            queryItems: queryItems,
            response: RemoteLeaderboardRankResponse.self
        )
        return response.entry
    }

    func experienceLeaderboard(scope: RemoteLeaderboardScope = .global) async throws -> [RemoteExperienceLeaderboardEntry] {
        let response = try await RemoteAccountAPI(endpoint: endpoint).request(
            path: scope == .friends ? "v1/leaderboards/experience/friends" : "v1/leaderboards/experience",
            method: "GET",
            token: scope == .friends ? try accessToken() : nil,
            body: Optional<String>.none,
            response: RemoteExperienceLeaderboardResponse.self
        )
        return response.entries
    }

    func experienceLeaderboardRank(
        scope: RemoteLeaderboardScope = .global
    ) async throws -> RemoteExperienceLeaderboardEntry? {
        let response = try await RemoteAccountAPI(endpoint: endpoint).request(
            path: scope == .friends
                ? "v1/leaderboards/experience/friends/rank" : "v1/leaderboards/experience/rank",
            method: "GET",
            token: try accessToken(),
            body: Optional<String>.none,
            response: RemoteExperienceLeaderboardRankResponse.self
        )
        return response.entry
    }

    func publicProfile(id: UUID) async throws -> RemotePublicProfile {
        try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/profiles/\(id.uuidString)",
            method: "GET",
            token: nil,
            body: Optional<String>.none,
            response: RemotePublicProfile.self
        )
    }

    func searchPublicProfiles(query: String) async throws -> [RemotePublicProfile] {
        let response = try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/profiles", method: "GET", token: nil,
            body: Optional<String>.none,
            queryItems: [URLQueryItem(name: "query", value: query), URLQueryItem(name: "limit", value: "20")],
            response: RemotePublicProfileSearchResponse.self
        )
        return response.profiles
    }

    func connections() async throws -> [RemoteConnection] {
        let token = try accessToken()
        let response = try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/connections", method: "GET", token: token,
            body: Optional<String>.none, response: RemoteConnectionsResponse.self
        )
        return response.connections
    }

    func sendConnection(to recipientID: UUID) async throws -> RemoteConnection {
        let token = try accessToken()
        return try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/connections", method: "POST", token: token,
            body: RemoteConnectionRequest(recipientID: recipientID), response: RemoteConnection.self
        )
    }

    func acceptConnection(from requesterID: UUID) async throws -> RemoteConnection {
        let token = try accessToken()
        return try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/connections/\(requesterID.uuidString)/accept", method: "POST", token: token,
            body: Optional<String>.none, response: RemoteConnection.self
        )
    }

    func removeConnection(with otherUserID: UUID) async throws {
        let token = try accessToken()
        let response = try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/connections/\(otherUserID.uuidString)", method: "DELETE", token: token,
            body: Optional<String>.none, response: RemoteConnectionRemovalResponse.self
        )
        guard response.removed else { throw RemoteAccountError.unexpectedResponse }
    }

    func blockUser(_ otherUserID: UUID) async throws {
        let token = try accessToken()
        let response = try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/blocks/\(otherUserID.uuidString)", method: "POST", token: token,
            body: Optional<String>.none, response: RemoteConnectionRemovalResponse.self
        )
        guard response.removed else { throw RemoteAccountError.unexpectedResponse }
    }

    func blockedUsers() async throws -> [RemotePublicProfile] {
        let token = try accessToken()
        return try await RemoteAccountAPI(endpoint: endpoint).request(path: "v1/blocks", method: "GET", token: token, body: Optional<String>.none, response: RemoteBlockedUsersResponse.self).profiles
    }

    func unblockUser(_ otherUserID: UUID) async throws {
        let token = try accessToken()
        let response = try await RemoteAccountAPI(endpoint: endpoint).request(path: "v1/blocks/\(otherUserID.uuidString)", method: "DELETE", token: token, body: Optional<String>.none, response: RemoteConnectionRemovalResponse.self)
        guard response.removed else { throw RemoteAccountError.unexpectedResponse }
    }

    func notifications() async throws -> [RemoteNotification] {
        let token = try accessToken()
        return try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/notifications", method: "GET", token: token,
            body: Optional<String>.none, response: RemoteNotificationsResponse.self
        ).notifications
    }

    func markNotificationRead(_ id: UUID) async throws -> RemoteNotification {
        let token = try accessToken()
        return try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/notifications/\(id.uuidString)/read", method: "POST", token: token,
            body: Optional<String>.none, response: RemoteNotification.self
        )
    }

    func directConversation(with otherUserID: UUID) async throws -> [RemoteDirectMessage] {
        let token = try accessToken()
        return try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/messages/\(otherUserID.uuidString)", method: "GET", token: token,
            body: Optional<String>.none, response: RemoteDirectConversationResponse.self
        ).messages
    }

    func sendDirectMessage(to recipientID: UUID, body: String) async throws -> RemoteDirectMessage {
        let token = try accessToken()
        return try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/messages", method: "POST", token: token,
            body: RemoteDirectMessageRequest(recipientID: recipientID, body: body), response: RemoteDirectMessage.self
        )
    }

    func markDirectConversationRead(with otherUserID: UUID) async throws {
        let token = try accessToken()
        let response = try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/messages/\(otherUserID.uuidString)/read", method: "POST", token: token,
            body: Optional<String>.none, response: RemoteConnectionRemovalResponse.self
        )
        guard response.removed else { throw RemoteAccountError.unexpectedResponse }
    }

    func reportProfile(_ profileID: UUID, reason: RemoteProfileReportReason, note: String?) async throws -> RemoteProfileReportResponse {
        let token = try accessToken()
        return try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/reports/profiles", method: "POST", token: token,
            body: RemoteProfileReportRequest(profileID: profileID, reason: reason, note: note),
            response: RemoteProfileReportResponse.self
        )
    }

    private func accessToken() throws -> String {
        guard let token = tokenStore.load(), currentUser != nil else {
            throw RemoteAccountError.serverMessage("请先登录自建 Typebar 服务。")
        }
        return token
    }

    private func beginOAuth(
        provider: RemoteOAuthProvider,
        purpose: RemoteOAuthPurpose,
        accessToken: String?
    ) async {
        guard !isWorking else {
            statusMessage = RemoteAccountError.oauthAuthorizationInProgress.localizedDescription
            return
        }
        pendingOAuthRegistration = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let start = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/auth/oauth/\(provider.rawValue)/start",
                method: "POST",
                token: accessToken,
                body: RemoteOAuthStartRequest(purpose: purpose),
                response: RemoteOAuthStartResponse.self
            )
            guard let authorizationURL = URL(string: start.authorizationURL) else {
                throw RemoteAccountError.unexpectedResponse
            }
            let callbackURL = try await oauthBrowser.authorize(url: authorizationURL)
            let state = try oauthState(from: callbackURL)
            let completion = try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/auth/oauth/completion",
                method: "GET",
                token: nil,
                body: Optional<String>.none,
                queryItems: [URLQueryItem(name: "state", value: state)],
                response: RemoteOAuthCompletionResponse.self
            )
            try applyOAuthCompletion(completion, provider: provider, state: state)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func reauthenticationToken(
        for user: RemoteAccountUser,
        accessToken: String,
        excluding method: RemoteAuthenticationMethod?,
        currentPassword: String?
    ) async throws -> String {
        if user.authenticationMethods.contains(.password), method != .password {
            guard let currentPassword, !currentPassword.isEmpty else {
                throw RemoteAccountError.serverMessage("请输入当前密码以确认此项账户操作。")
            }
            return try await RemoteAccountAPI(endpoint: endpoint).request(
                path: "v1/auth/reauthentication/password",
                method: "POST",
                token: accessToken,
                body: RemotePasswordReauthenticationRequest(currentPassword: currentPassword),
                response: RemoteReauthenticationResponse.self
            ).reauthenticationToken
        }

        guard let provider = user.authenticationMethods
            .compactMap(\.oauthProvider)
            .first(where: { $0.authenticationMethod != method }) else {
            throw RemoteAccountError.serverMessage("没有可用于确认此项账户操作的其他登录方式。")
        }
        let start = try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/auth/oauth/\(provider.rawValue)/start",
            method: "POST",
            token: accessToken,
            body: RemoteOAuthStartRequest(purpose: .reauthenticate),
            response: RemoteOAuthStartResponse.self
        )
        guard let authorizationURL = URL(string: start.authorizationURL) else {
            throw RemoteAccountError.unexpectedResponse
        }
        let callbackURL = try await oauthBrowser.authorize(url: authorizationURL)
        let state = try oauthState(from: callbackURL)
        let completion = try await RemoteAccountAPI(endpoint: endpoint).request(
            path: "v1/auth/oauth/completion",
            method: "GET",
            token: nil,
            body: Optional<String>.none,
            queryItems: [URLQueryItem(name: "state", value: state)],
            response: RemoteOAuthCompletionResponse.self
        )
        guard completion.status == .reauthenticated,
              let token = completion.reauthenticationToken else {
            throw RemoteAccountError.serverMessage(
                completion.message ?? "第三方身份确认未能完成。")
        }
        return token
    }

    private func applyOAuthCompletion(
        _ completion: RemoteOAuthCompletionResponse,
        provider: RemoteOAuthProvider,
        state: String
    ) throws {
        switch completion.status {
        case .signedIn:
            guard let session = completion.session else { throw RemoteAccountError.unexpectedResponse }
            try applyAuthenticatedSession(session)
            statusMessage = "已使用 \(provider.displayName) 登录。"
        case .linked:
            guard let user = completion.user else { throw RemoteAccountError.unexpectedResponse }
            currentUser = user
            statusMessage = "已关联 \(provider.displayName) 登录方式。"
        case .reauthenticated:
            throw RemoteAccountError.unexpectedResponse
        case .registrationRequired:
            guard let email = completion.email else { throw RemoteAccountError.unexpectedResponse }
            pendingOAuthRegistration = .init(
                provider: provider,
                state: state,
                email: email,
                suggestedDisplayName: completion.suggestedDisplayName
            )
            statusMessage = "请补充显示名以完成 \(provider.displayName) 注册。"
        case .failed:
            throw RemoteAccountError.serverMessage(
                completion.message ?? "第三方登录未能完成。")
        case .pending, .exchanging:
            throw RemoteAccountError.serverMessage("第三方登录仍在完成中，请稍后重试。")
        }
    }

    private func applyAuthenticatedSession(_ session: RemoteAuthSession) throws {
        try tokenStore.save(session.accessToken)
        currentUser = session.user
        developerAccessKeys = []
        remoteResults = []
        pendingOAuthRegistration = nil
    }

    private func oauthState(from callbackURL: URL) throws -> String {
        guard callbackURL.scheme == "typebar",
              callbackURL.host == "oauth",
              callbackURL.path == "/callback",
              let state = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "state" })?.value,
              !state.isEmpty else {
            throw RemoteAccountError.invalidOAuthCallback
        }
        return state
    }

    private func performAuth<Body: Encodable & Sendable>(path: String, body: Body) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await RemoteAccountAPI(endpoint: endpoint).request(path: path, method: "POST", token: nil, body: body, response: RemoteAuthSession.self)
            try applyAuthenticatedSession(session)
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func archiveSyncID() -> UUID {
        if let stored = defaults.string(forKey: syncIDKey), let id = UUID(uuidString: stored) { return id }
        let id = UUID()
        defaults.set(id.uuidString, forKey: syncIDKey)
        return id
    }
}

private struct RemoteAccountAPI {
    let endpoint: String

    func request<Body: Encodable & Sendable, Response: Decodable & Sendable>(path: String, method: String, token: String?, body: Body?, queryItems: [URLQueryItem] = [], headers: [String: String] = [:], response: Response.Type) async throws -> Response {
        guard let baseURL = URL(string: endpoint) else {
            throw RemoteAccountError.invalidServerURL
        }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw RemoteAccountError.invalidServerURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.remote.encode(body)
        }

        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        guard let response = urlResponse as? HTTPURLResponse else { throw RemoteAccountError.unexpectedResponse }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 503, response.value(forHTTPHeaderField: "X-Typebar-Maintenance") == "true" {
                throw RemoteAccountError.serverMessage("自建 Typebar 服务正在维护中；本机离线练习仍可使用，请稍后重试。")
            }
            if let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let reason = message["reason"] as? String {
                throw RemoteAccountError.serverMessage(reason)
            }
            throw RemoteAccountError.serverMessage("服务请求失败（HTTP \(response.statusCode)）。")
        }
        return try JSONDecoder.remote.decode(Response.self, from: data)
    }
}

private final class AccountTokenStore {
    private let service = "app.typebar.desktop"
    private let account = "remote-access-token"

    func save(_ token: String) throws {
        clear()
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: Data(token.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    func load() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func clear() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private extension JSONEncoder {
    static var remote: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var remote: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
