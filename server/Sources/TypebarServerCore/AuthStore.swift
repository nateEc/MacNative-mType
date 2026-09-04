import Foundation
import Vapor

public struct RegisterRequest: Content, Equatable {
  public let email: String
  public let password: String
  public let displayName: String
}

public struct LoginRequest: Content, Equatable {
  public let email: String
  public let password: String
}

public struct ChangePasswordRequest: Content, Equatable {
  public let currentPassword: String
  public let newPassword: String
}

public struct AddPasswordAuthenticationRequest: Content, Equatable {
  public let newPassword: String
}

public struct RemovePasswordAuthenticationRequest: Content, Equatable {
  public let currentPassword: String
}

public struct PasswordResetRequest: Content, Equatable {
  public let email: String
}

public struct PasswordResetRequestResponse: Content, Equatable {
  /// This is deliberately identical for registered and unregistered emails.
  public let accepted: Bool
}

public struct CompletePasswordResetRequest: Content, Equatable {
  public let token: String
  public let newPassword: String
}

public struct PasswordResetCompletionResponse: Content, Equatable {
  public let reset: Bool
}

public struct EmailVerificationRequestResponse: Content, Equatable {
  public let accepted: Bool
}

public struct CompleteEmailVerificationRequest: Content, Equatable {
  public let token: String
}

public struct EmailVerificationCompletionResponse: Content, Equatable {
  public let verified: Bool
}

/// An opaque, one-time code that a trusted mail webhook can embed in a
/// verification email. The account store persists only its SHA-256 hash.
public struct EmailVerificationDelivery: Sendable {
  public let email: String
  public let token: String
  public let expiresAt: Date

  public init(email: String, token: String, expiresAt: Date) {
    self.email = email
    self.token = token
    self.expiresAt = expiresAt
  }
}

public typealias EmailVerificationDeliveryHandler = @Sendable (EmailVerificationDelivery) async throws -> Void

/// The only point at which a raw reset token leaves the account store. A
/// deployment supplies a trusted delivery handler; persisted state only keeps
/// the SHA-256 hash of `token`.
public struct PasswordResetDelivery: Sendable {
  public let email: String
  public let token: String
  public let expiresAt: Date

  public init(email: String, token: String, expiresAt: Date) {
    self.email = email
    self.token = token
    self.expiresAt = expiresAt
  }
}

public typealias PasswordResetDeliveryHandler = @Sendable (PasswordResetDelivery) async throws -> Void

public struct ChangeEmailRequest: Content, Equatable {
  public let currentPassword: String
  public let newEmail: String
}

public struct DeleteAccountRequest: Content, Equatable {
  public let currentPassword: String?
}

public struct AccountDeletionResponse: Content, Equatable {
  public let deleted: Bool
}

public struct DeleteResultsRequest: Content, Equatable {
  public let currentPassword: String?
}

public struct ResultDeletionResponse: Content, Equatable {
  public let deleted: Bool
  public let removedCount: Int
}

public struct RevokeSessionsRequest: Content, Equatable {
  public let currentPassword: String?
}

public struct SessionsRevocationResponse: Content, Equatable {
  public let revoked: Bool
}

public struct PasswordReauthenticationRequest: Content, Equatable {
  public let currentPassword: String
}

public struct ReauthenticationResponse: Content, Equatable {
  public let reauthenticationToken: String
}

/// Account-owned profile details. Every field is intentionally public except
/// the visibility preferences, which control optional profile data.
public struct ProfileDetails: Content, Equatable {
  public let bio: String
  public let keyboard: String
  public let github: String
  public let socialHandle: String
  public let websiteURL: String
  public let showActivity: Bool
  public let showDiscordAvatar: Bool

  public init(
    bio: String = "", keyboard: String = "", github: String = "", socialHandle: String = "",
    websiteURL: String = "", showActivity: Bool = true, showDiscordAvatar: Bool = false
  ) {
    self.bio = bio
    self.keyboard = keyboard
    self.github = github
    self.socialHandle = socialHandle
    self.websiteURL = websiteURL
    self.showActivity = showActivity
    self.showDiscordAvatar = showDiscordAvatar
  }
}

public struct UpdateProfileRequest: Content, Equatable {
  public let displayName: String?
  /// Omitted by older clients, which preserves the existing account choice.
  public let leaderboardOptedOut: Bool?
  /// Omitted by older clients, which preserves existing public details.
  public let profileDetails: ProfileDetails?
  /// Omitted by older clients, which preserves the existing badge. An empty
  /// string explicitly clears the public badge selection.
  public let selectedBadgeID: String?

  public init(
    displayName: String? = nil, leaderboardOptedOut: Bool? = nil,
    profileDetails: ProfileDetails? = nil, selectedBadgeID: String? = nil
  ) {
    self.displayName = displayName
    self.leaderboardOptedOut = leaderboardOptedOut
    self.profileDetails = profileDetails
    self.selectedBadgeID = selectedBadgeID
  }
}

/// A scoped credential for automation clients. It deliberately has no account
/// management authority: Typebar only accepts it when receiving a result.
public struct DeveloperAccessKey: Content, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let name: String
  public let enabled: Bool
  public let createdAt: Date
  public let modifiedAt: Date
  public let lastUsedAt: Date?
}

public struct DeveloperAccessKeyListResponse: Content, Equatable, Sendable {
  public let keys: [DeveloperAccessKey]
}

public struct CreateDeveloperAccessKeyRequest: Content, Equatable, Sendable {
  public let name: String
}

/// The raw key is returned only from creation. Persisted state stores only its
/// SHA-256 hash, so neither later list responses nor a server backup can
/// reveal it.
public struct CreateDeveloperAccessKeyResponse: Content, Equatable, Sendable {
  public let key: DeveloperAccessKey
  public let accessKey: String
}

public struct UpdateDeveloperAccessKeyRequest: Content, Equatable, Sendable {
  public let name: String?
  public let enabled: Bool?
}

public struct DeveloperAccessKeyDeletionResponse: Content, Equatable, Sendable {
  public let deleted: Bool
}

public enum ResultServiceCredential: Sendable {
  case accessToken(String)
  case developerAccessKey(String)
}

public struct AuthSessionResponse: Content, Equatable {
  public let user: AuthUserResponse
  public let accessToken: String
  public let expiresAt: Date
}

/// OAuth subject identifiers are accepted only after a configured provider
/// exchange has validated them.
public enum OAuthProvider: String, Content, CaseIterable, Equatable, Sendable {
  case github
  case google
  case discord
}

public enum AuthenticationMethod: String, Content, CaseIterable, Equatable, Sendable {
  case password
  case github
  case google
  case discord
}

public enum OAuthAuthorizationPurpose: String, Content, Equatable, Sendable {
  case signIn
  case link
  case reauthenticate
}

public struct OAuthAuthorizationRequest: Sendable, Equatable {
  public let provider: OAuthProvider
  public let state: String
  public let codeChallenge: String

  public init(provider: OAuthProvider, state: String, codeChallenge: String) {
    self.provider = provider
    self.state = state
    self.codeChallenge = codeChallenge
  }
}

public struct OAuthCallbackExchange: Sendable, Equatable {
  public let provider: OAuthProvider
  public let codeVerifier: String

  public init(provider: OAuthProvider, codeVerifier: String) {
    self.provider = provider
    self.codeVerifier = codeVerifier
  }
}

public enum OAuthCompletionStatus: String, Content, Equatable, Sendable {
  case pending
  case exchanging
  case registrationRequired
  case signedIn
  case linked
  case reauthenticated
  case failed
}

public struct OAuthCompletionResponse: Content, Equatable {
  public let status: OAuthCompletionStatus
  public let email: String?
  public let suggestedDisplayName: String?
  public let session: AuthSessionResponse?
  public let user: AuthUserResponse?
  public let reauthenticationToken: String?
  public let message: String?
}

public struct OAuthStartRequest: Content, Equatable {
  public let purpose: OAuthAuthorizationPurpose
}

public struct OAuthStartResponse: Content, Equatable {
  public let authorizationURL: String
}

public struct OAuthRegistrationRequest: Content, Equatable {
  public let state: String
  public let displayName: String
}

/// A verified identity returned by a configured OAuth provider. It deliberately
/// contains no provider access or refresh token; Typebar only keeps the stable
/// provider subject needed for future sign-in. Discord may also supply an
/// optional avatar hash for a separately opt-in public profile image.
public struct OAuthProviderIdentity: Sendable, Equatable {
  public let provider: OAuthProvider
  public let subject: String
  public let email: String
  public let suggestedDisplayName: String?
  public let avatarHash: String?

  public init(
    provider: OAuthProvider, subject: String, email: String, suggestedDisplayName: String? = nil,
    avatarHash: String? = nil
  ) {
    self.provider = provider
    self.subject = subject
    self.email = email
    self.suggestedDisplayName = suggestedDisplayName
    self.avatarHash = avatarHash
  }
}

public struct AuthUserResponse: Content, Equatable {
  public let id: UUID
  public let email: String
  public let emailVerified: Bool
  public let displayName: String
  public let totalExperience: Int
  public let leaderboardOptedOut: Bool
  public let profileDetails: ProfileDetails
  public let authenticationMethods: [AuthenticationMethod]
  public let availableBadges: [PublicProfileBadge]
  public let selectedBadgeID: String?
}

public struct PublicProfileResponse: Content, Equatable {
  public let id: UUID
  public let displayName: String
  public let joinedAt: Date
  public let completedResultCount: Int
  public let startedTestCount: Int
  public let totalTypingSeconds: Double
  public let bestWPM: Int
  public let highestConsistency: Double
  public let personalBests: [PublicProfileBestResponse]
  public let activity: PublicProfileActivityResponse?
  public let streak: PublicProfileStreakResponse?
  public let totalExperience: Int
  public let profileDetails: ProfileDetails
  public let discordAvatar: PublicDiscordAvatarResponse?
  public let selectedBadge: PublicProfileBadge?
}

/// A Typebar-owned badge that can be selected for public profiles and
/// leaderboards. It contains presentation metadata only, never user activity.
public struct PublicProfileBadge: Content, Equatable, Identifiable, Sendable {
  public let id: String
  public let title: String
  public let systemImage: String
}

/// An opt-in Discord CDN identifier. It deliberately excludes email, tokens,
/// and every other OAuth provider detail.
public struct PublicDiscordAvatarResponse: Content, Equatable {
  public let subject: String
  public let avatarHash: String
}

/// A public, per-standard-mode best. It intentionally excludes the prompt,
/// input replay, email, and any account-scoped data.
public struct PublicProfileBestResponse: Content, Equatable, Identifiable {
  public let id: UUID
  public let mode: String
  public let durationSeconds: Int?
  public let wordLimit: Int?
  public let language: String
  public let wpm: Int
  public let accuracy: Int
  public let consistency: Double
  public let finishedAt: Date
}

/// A UTC 12-month activity timeline. The detail endpoint returns this compact
/// aggregate only; nested profiles in lists intentionally omit it.
public struct PublicProfileActivityResponse: Content, Equatable {
  public let lastDay: Date
  public let testsByDays: [Int]
}

/// A UTC-derived public streak summary. It shares the activity visibility
/// preference and never includes individual result timestamps.
public struct PublicProfileStreakResponse: Content, Equatable {
  public let currentDays: Int
  public let longestDays: Int
}

public struct PublicProfileSearchResponse: Content, Equatable {
  public let profiles: [PublicProfileResponse]
}

public enum AuthStoreError: Error, Equatable {
  case invalidEmail
  case invalidDisplayName
  case weakPassword
  case emailAlreadyRegistered
  case invalidCredentials
  case invalidAccessToken
  case invalidPasswordResetToken
  case invalidEmailVerificationToken
  case invalidOAuthIdentity
  case oauthIdentityAlreadyLinked
  case oauthIdentityNotLinked
  case passwordAuthenticationAlreadyLinked
  case passwordAuthenticationNotLinked
  case cannotRemoveLastAuthentication
  case invalidReauthenticationToken
  case invalidProfileDetails
  case invalidOAuthTransaction
  case oauthRegistrationNotRequired
  case profileNotFound
  case cannotConnectToSelf
  case connectionAlreadyExists
  case connectionNotFound
  case connectionNotPending
  case notificationNotFound
  case invalidProfileSearch
  case invalidQuoteSubmission
  case cannotReportSelf
  case reportAlreadySubmitted
  case invalidProfileReport
  case directMessageNotAllowed
  case invalidDirectMessage
  case invalidDeveloperAccessKeyName
  case invalidDeveloperAccessKey
  case inactiveDeveloperAccessKey
  case developerAccessKeyNotFound
  case developerAccessKeyLimitReached
  case invalidResultQuery
  case resultNotFound
  case invalidResultTags
  case invalidAnnouncement
}

public actor AuthStore {
  private struct PersistedState: Codable {
    var users: [StoredUser] = []
    var sessions: [StoredSession] = []
    var developerAccessKeys: [StoredDeveloperAccessKey] = []
    var passwordResetTokens: [StoredPasswordResetToken] = []
    var emailVerificationTokens: [StoredEmailVerificationToken] = []
    var oauthIdentities: [StoredOAuthIdentity] = []
    var oauthTransactions: [StoredOAuthTransaction] = []
    var reauthenticationTokens: [StoredReauthenticationToken] = []
    var syncRecords: [StoredSyncRecord] = []
    var results: [StoredResult] = []
    var connections: [StoredConnection] = []
    var blockedUserIDs: [UUID: [UUID]] = [:]
    var quoteSubmissions: [StoredQuoteSubmission] = []
    var quoteRatings: [StoredQuoteRating] = []
    var notifications: [StoredNotification] = []
    var profileReports: [StoredProfileReport] = []
    var quoteReports: [StoredQuoteReport] = []
    var directMessages: [StoredDirectMessage] = []
    var announcements: [StoredAnnouncement] = []
    var nextSyncCursor = 0

    private enum CodingKeys: String, CodingKey {
      case users, sessions, developerAccessKeys, passwordResetTokens, emailVerificationTokens, oauthIdentities, oauthTransactions, reauthenticationTokens, syncRecords, results, connections, blockedUserIDs, quoteSubmissions,
        quoteRatings, notifications, profileReports, quoteReports, directMessages, announcements,
        nextSyncCursor
    }

    init() {}

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      users = try values.decodeIfPresent([StoredUser].self, forKey: .users) ?? []
      sessions = try values.decodeIfPresent([StoredSession].self, forKey: .sessions) ?? []
      developerAccessKeys =
        try values.decodeIfPresent([StoredDeveloperAccessKey].self, forKey: .developerAccessKeys) ?? []
      passwordResetTokens =
        try values.decodeIfPresent([StoredPasswordResetToken].self, forKey: .passwordResetTokens) ?? []
      emailVerificationTokens =
        try values.decodeIfPresent([StoredEmailVerificationToken].self, forKey: .emailVerificationTokens) ?? []
      oauthIdentities =
        try values.decodeIfPresent([StoredOAuthIdentity].self, forKey: .oauthIdentities) ?? []
      oauthTransactions =
        try values.decodeIfPresent([StoredOAuthTransaction].self, forKey: .oauthTransactions) ?? []
      reauthenticationTokens =
        try values.decodeIfPresent([StoredReauthenticationToken].self, forKey: .reauthenticationTokens) ?? []
      syncRecords = try values.decodeIfPresent([StoredSyncRecord].self, forKey: .syncRecords) ?? []
      results = try values.decodeIfPresent([StoredResult].self, forKey: .results) ?? []
      connections = try values.decodeIfPresent([StoredConnection].self, forKey: .connections) ?? []
      blockedUserIDs =
        try values.decodeIfPresent([UUID: [UUID]].self, forKey: .blockedUserIDs) ?? [:]
      quoteSubmissions =
        try values.decodeIfPresent([StoredQuoteSubmission].self, forKey: .quoteSubmissions) ?? []
      quoteRatings =
        try values.decodeIfPresent([StoredQuoteRating].self, forKey: .quoteRatings) ?? []
      notifications =
        try values.decodeIfPresent([StoredNotification].self, forKey: .notifications) ?? []
      profileReports =
        try values.decodeIfPresent([StoredProfileReport].self, forKey: .profileReports) ?? []
      quoteReports =
        try values.decodeIfPresent([StoredQuoteReport].self, forKey: .quoteReports) ?? []
      directMessages =
        try values.decodeIfPresent([StoredDirectMessage].self, forKey: .directMessages) ?? []
      announcements =
        try values.decodeIfPresent([StoredAnnouncement].self, forKey: .announcements) ?? []
      nextSyncCursor = try values.decodeIfPresent(Int.self, forKey: .nextSyncCursor) ?? 0
    }
  }

  private struct StoredUser: Codable {
    let id: UUID
    let email: String
    let displayName: String
    let passwordHash: String?
    let createdAt: Date
    let emailVerified: Bool
    let leaderboardOptedOut: Bool
    let profileDetails: ProfileDetails
    let selectedBadgeID: String?
    var startedTestCount: Int

    private enum CodingKeys: String, CodingKey {
      case id, email, displayName, passwordHash, createdAt, emailVerified, leaderboardOptedOut,
        profileDetails, selectedBadgeID, startedTestCount
    }

    init(
      id: UUID, email: String, displayName: String, passwordHash: String?, createdAt: Date,
      emailVerified: Bool = false,
      leaderboardOptedOut: Bool = false,
      profileDetails: ProfileDetails = .init(), selectedBadgeID: String? = nil,
      startedTestCount: Int = 0
    ) {
      self.id = id
      self.email = email
      self.displayName = displayName
      self.passwordHash = passwordHash
      self.createdAt = createdAt
      self.emailVerified = emailVerified
      self.leaderboardOptedOut = leaderboardOptedOut
      self.profileDetails = profileDetails
      self.selectedBadgeID = selectedBadgeID
      self.startedTestCount = startedTestCount
    }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      id = try values.decode(UUID.self, forKey: .id)
      email = try values.decode(String.self, forKey: .email)
      displayName = try values.decode(String.self, forKey: .displayName)
      passwordHash = try values.decodeIfPresent(String.self, forKey: .passwordHash)
      createdAt = try values.decode(Date.self, forKey: .createdAt)
      emailVerified = try values.decodeIfPresent(Bool.self, forKey: .emailVerified) ?? false
      leaderboardOptedOut = try values.decodeIfPresent(Bool.self, forKey: .leaderboardOptedOut) ?? false
      profileDetails = try values.decodeIfPresent(ProfileDetails.self, forKey: .profileDetails) ?? .init()
      selectedBadgeID = try values.decodeIfPresent(String.self, forKey: .selectedBadgeID)
      startedTestCount = try values.decodeIfPresent(Int.self, forKey: .startedTestCount) ?? 0
    }
  }

  private struct StoredSession: Codable {
    let tokenHash: String
    let userID: UUID
    let expiresAt: Date
  }

  private struct StoredDeveloperAccessKey: Codable {
    let id: UUID
    let userID: UUID
    let tokenHash: String
    let name: String
    let enabled: Bool
    let createdAt: Date
    let modifiedAt: Date
    let lastUsedAt: Date?

    func response() -> DeveloperAccessKey {
      .init(
        id: id, name: name, enabled: enabled, createdAt: createdAt,
        modifiedAt: modifiedAt, lastUsedAt: lastUsedAt)
    }
  }

  private struct StoredReauthenticationToken: Codable {
    let tokenHash: String
    let userID: UUID
    let expiresAt: Date
  }

  private struct StoredPasswordResetToken: Codable {
    let tokenHash: String
    let userID: UUID
    let expiresAt: Date
  }

  private struct StoredEmailVerificationToken: Codable {
    let tokenHash: String
    let userID: UUID
    let expiresAt: Date
  }

  private struct StoredOAuthIdentity: Codable {
    let provider: OAuthProvider
    let subject: String
    let userID: UUID
    let linkedAt: Date
    var avatarHash: String?
  }

  private struct StoredOAuthTransaction: Codable {
    let provider: OAuthProvider
    let stateHash: String
    let codeVerifier: String
    let purpose: OAuthAuthorizationPurpose
    let userID: UUID?
    let expiresAt: Date
    var status: OAuthCompletionStatus
    var subject: String?
    var email: String?
    var suggestedDisplayName: String?
    var avatarHash: String?
    var authenticatedUserID: UUID?
    var failureMessage: String?
  }

  private struct StoredSyncRecord: Codable {
    let userID: UUID
    let id: UUID
    let type: String
    let version: Int
    let payload: String?
    let isDeleted: Bool
    let cursor: Int
    let updatedAt: Date

    func response() -> SyncChangeResponse {
      .init(
        id: id, type: type, version: version, payload: payload, isDeleted: isDeleted,
        cursor: cursor, updatedAt: updatedAt)
    }
  }

  private struct StoredResult: Codable {
    let id: UUID
    let userID: UUID
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
    var tags: [String]
    let startedAt: Date
    let finishedAt: Date

    private enum CodingKeys: String, CodingKey {
      case id, userID, mode, language, durationSeconds, wordLimit, wpm, rawWpm, accuracy, consistency,
        errorCount, eventCount, tags, startedAt, finishedAt
    }

    init(
      id: UUID, userID: UUID, mode: String, language: String, durationSeconds: Int?,
      wordLimit: Int?, wpm: Int, rawWpm: Int, accuracy: Int, consistency: Double,
      errorCount: Int, eventCount: Int, tags: [String],
      startedAt: Date, finishedAt: Date
    ) {
      self.id = id
      self.userID = userID
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
      self.startedAt = startedAt
      self.finishedAt = finishedAt
    }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      id = try values.decode(UUID.self, forKey: .id)
      userID = try values.decode(UUID.self, forKey: .userID)
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
      finishedAt = try values.decode(Date.self, forKey: .finishedAt)
      let legacyDuration =
        durationSeconds.map(TimeInterval.init)
        ?? max(1, Double(eventCount) / Double(max(rawWpm, 1) * 5) * 60)
      startedAt =
        try values.decodeIfPresent(Date.self, forKey: .startedAt)
        ?? finishedAt.addingTimeInterval(-legacyDuration)
    }

    func response() -> AccountResultResponse {
      .init(
        id: id, mode: mode, language: language, durationSeconds: durationSeconds,
        wordLimit: wordLimit, wpm: wpm, rawWpm: rawWpm, accuracy: accuracy,
        consistency: consistency, errorCount: errorCount, eventCount: eventCount, tags: tags,
        startedAt: startedAt, finishedAt: finishedAt)
    }
  }

  private struct StoredConnection: Codable {
    let requesterID: UUID
    let recipientID: UUID
    var status: String
    var updatedAt: Date
  }

  private struct StoredQuoteSubmission: Codable {
    let id: UUID
    let userID: UUID
    let language: String
    let text: String
    let attribution: String?
    var status: String
    let submittedAt: Date
  }

  private struct StoredQuoteRating: Codable {
    let userID: UUID
    let quoteID: UUID
    var value: Int
  }

  private struct StoredNotification: Codable {
    let id: UUID
    let recipientID: UUID
    let actorID: UUID
    let kind: TypebarNotificationKind
    let createdAt: Date
    var readAt: Date?
  }

  private struct StoredProfileReport: Codable {
    let id: UUID
    let reporterID: UUID
    let profileID: UUID
    let reason: ProfileReportReason
    let note: String?
    let submittedAt: Date
    var status: ProfileReportModerationStatus

    private enum CodingKeys: String, CodingKey {
      case id, reporterID, profileID, reason, note, submittedAt, status
    }

    init(
      id: UUID, reporterID: UUID, profileID: UUID, reason: ProfileReportReason, note: String?,
      submittedAt: Date, status: ProfileReportModerationStatus = .open
    ) {
      self.id = id
      self.reporterID = reporterID
      self.profileID = profileID
      self.reason = reason
      self.note = note
      self.submittedAt = submittedAt
      self.status = status
    }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      id = try values.decode(UUID.self, forKey: .id)
      reporterID = try values.decode(UUID.self, forKey: .reporterID)
      profileID = try values.decode(UUID.self, forKey: .profileID)
      reason = try values.decode(ProfileReportReason.self, forKey: .reason)
      note = try values.decodeIfPresent(String.self, forKey: .note)
      submittedAt = try values.decode(Date.self, forKey: .submittedAt)
      status =
        try values.decodeIfPresent(ProfileReportModerationStatus.self, forKey: .status) ?? .open
    }
  }

  private struct StoredQuoteReport: Codable {
    let id: UUID
    let reporterID: UUID
    let quoteID: UUID
    let reason: QuoteReportReason
    let note: String?
    let submittedAt: Date
  }

  private struct StoredDirectMessage: Codable {
    let id: UUID
    let senderID: UUID
    let recipientID: UUID
    let body: String
    let createdAt: Date
    var readAt: Date?
  }

  private struct StoredAnnouncement: Codable {
    let id: UUID
    let message: String
    let level: TypebarAnnouncementLevel
    let sticky: Bool
    let scheduledAt: Date?
    let publishedAt: Date

    func response() -> PublicAnnouncementResponse {
      .init(
        id: id, message: message, level: level, sticky: sticky, scheduledAt: scheduledAt,
        publishedAt: publishedAt)
    }
  }

  private var state: PersistedState
  private let fileURL: URL?
  private let bcryptCost: Int

  public init(fileURL: URL?, bcryptCost: Int = 12) throws {
    self.fileURL = fileURL
    self.bcryptCost = bcryptCost
    guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
      state = .init()
      return
    }
    state = try JSONDecoder.server.decode(PersistedState.self, from: Data(contentsOf: fileURL))
  }

  public func register(_ request: RegisterRequest, now: Date = .now) throws -> AuthSessionResponse {
    let email = try validatedEmail(request.email)
    let displayName = try validatedDisplayName(request.displayName)
    try validatedPassword(request.password)
    guard !state.users.contains(where: { $0.email == email }) else {
      throw AuthStoreError.emailAlreadyRegistered
    }

    let user = StoredUser(
      id: UUID(),
      email: email,
      displayName: displayName,
      passwordHash: try Bcrypt.hash(request.password, cost: bcryptCost),
      createdAt: now
    )
    state.users.append(user)
    let response = makeSession(for: user, now: now)
    try persist()
    return response
  }

  public func login(_ request: LoginRequest, now: Date = .now) throws -> AuthSessionResponse {
    let email = try validatedEmail(request.email)
    guard let user = state.users.first(where: { $0.email == email }),
      let passwordHash = user.passwordHash
    else {
      throw AuthStoreError.invalidCredentials
    }
    guard try Bcrypt.verify(request.password, created: passwordHash) else {
      throw AuthStoreError.invalidCredentials
    }

    state.sessions.removeAll { $0.expiresAt <= now }
    let response = makeSession(for: user, now: now)
    try persist()
    return response
  }

  /// Creates a passwordless account after an OAuth provider has validated a
  /// stable provider subject and verified email address. Provider tokens are
  /// intentionally never accepted or persisted by the store.
  public func registerWithOAuth(
    _ identity: OAuthProviderIdentity, displayName: String, now: Date = .now
  ) throws -> AuthSessionResponse {
    let (subject, email) = try validatedOAuthIdentity(identity)
    let name = try validatedDisplayName(displayName)
    guard !state.oauthIdentities.contains(where: {
      $0.provider == identity.provider && $0.subject == subject
    }) else { throw AuthStoreError.oauthIdentityAlreadyLinked }
    guard !state.users.contains(where: { $0.email == email }) else {
      throw AuthStoreError.emailAlreadyRegistered
    }

    let user = StoredUser(
      id: UUID(), email: email, displayName: name, passwordHash: nil, createdAt: now,
      emailVerified: true)
    state.users.append(user)
    state.oauthIdentities.append(
      .init(
        provider: identity.provider, subject: subject, userID: user.id, linkedAt: now,
        avatarHash: Self.discordAvatarHash(from: identity)))
    let response = makeSession(for: user, now: now)
    try persist()
    return response
  }

  /// Signs in only when the exact provider subject is already linked. A
  /// matching email alone never grants access to an existing Typebar account.
  public func loginWithOAuth(
    _ identity: OAuthProviderIdentity, now: Date = .now
  ) throws -> AuthSessionResponse {
    let (subject, _) = try validatedOAuthIdentity(identity)
    guard let linkedIdentity = state.oauthIdentities.first(where: {
      $0.provider == identity.provider && $0.subject == subject
    }), let user = state.users.first(where: { $0.id == linkedIdentity.userID })
    else { throw AuthStoreError.oauthIdentityNotLinked }
    state.sessions.removeAll { $0.expiresAt <= now }
    let response = makeSession(for: user, now: now)
    try persist()
    return response
  }

  /// Attaches a provider identity to the authenticated account. The same
  /// provider subject cannot be moved between accounts through this endpoint.
  public func linkOAuth(
    _ identity: OAuthProviderIdentity, accessToken: String, now: Date = .now
  ) throws -> AuthUserResponse {
    let currentUser = try authenticatedUser(for: accessToken, now: now)
    let (subject, _) = try validatedOAuthIdentity(identity)
    if let existingIndex = state.oauthIdentities.firstIndex(where: {
      $0.provider == identity.provider && $0.subject == subject
    }) {
      guard state.oauthIdentities[existingIndex].userID == currentUser.id else {
        throw AuthStoreError.oauthIdentityAlreadyLinked
      }
      if let avatarHash = Self.discordAvatarHash(from: identity),
        state.oauthIdentities[existingIndex].avatarHash != avatarHash
      {
        state.oauthIdentities[existingIndex].avatarHash = avatarHash
        try persist()
      }
      return try userResponse(for: currentUser.id)
    }
    state.oauthIdentities.append(
      .init(
        provider: identity.provider, subject: subject, userID: currentUser.id, linkedAt: now,
        avatarHash: Self.discordAvatarHash(from: identity)))
    try persist()
    return try userResponse(for: currentUser.id)
  }

  /// Removes a linked provider only if a password or another provider remains.
  /// This prevents making the account permanently inaccessible.
  public func unlinkOAuth(
    _ provider: OAuthProvider, accessToken: String, reauthenticationToken: String, now: Date = .now
  ) throws -> AuthUserResponse {
    let currentUser = try authenticatedUser(for: accessToken, now: now)
    try consumeReauthenticationToken(reauthenticationToken, for: currentUser.id, now: now)
    guard state.oauthIdentities.contains(where: {
      $0.userID == currentUser.id && $0.provider == provider
    }) else { throw AuthStoreError.oauthIdentityNotLinked }
    guard authenticationMethods(for: currentUser.id).count > 1 else {
      throw AuthStoreError.cannotRemoveLastAuthentication
    }
    state.oauthIdentities.removeAll { $0.userID == currentUser.id && $0.provider == provider }
    try persist()
    return try userResponse(for: currentUser.id)
  }

  /// Adds password authentication to an authenticated provider-only account.
  /// A valid Typebar session is required; passwords never replace or expose a
  /// provider identity, and are stored only as bcrypt hashes.
  public func addPasswordAuthentication(
    _ request: AddPasswordAuthenticationRequest, accessToken: String, reauthenticationToken: String,
    now: Date = .now
  ) throws -> AuthUserResponse {
    let currentUser = try authenticatedUser(for: accessToken, now: now)
    try consumeReauthenticationToken(reauthenticationToken, for: currentUser.id, now: now)
    guard let index = state.users.firstIndex(where: { $0.id == currentUser.id }) else {
      throw AuthStoreError.invalidAccessToken
    }
    let user = state.users[index]
    guard user.passwordHash == nil else { throw AuthStoreError.passwordAuthenticationAlreadyLinked }
    try validatedPassword(request.newPassword)
    let updatedUser = StoredUser(
      id: user.id, email: user.email, displayName: user.displayName,
      passwordHash: try Bcrypt.hash(request.newPassword, cost: bcryptCost),
      createdAt: user.createdAt, emailVerified: user.emailVerified,
      leaderboardOptedOut: user.leaderboardOptedOut, profileDetails: user.profileDetails,
      selectedBadgeID: user.selectedBadgeID, startedTestCount: user.startedTestCount)
    state.users[index] = updatedUser
    try persist()
    return try userResponse(for: updatedUser.id)
  }

  /// Verifies a password and issues a one-time, five-minute credential for a
  /// high-risk account operation. Only the credential hash reaches persisted state.
  public func reauthenticateWithPassword(
    _ request: PasswordReauthenticationRequest, accessToken: String, now: Date = .now
  ) throws -> ReauthenticationResponse {
    let currentUser = try authenticatedUser(for: accessToken, now: now)
    guard let user = state.users.first(where: { $0.id == currentUser.id }),
      let passwordHash = user.passwordHash,
      try Bcrypt.verify(request.currentPassword, created: passwordHash)
    else { throw AuthStoreError.invalidCredentials }
    return try makeReauthenticationToken(for: user.id, now: now)
  }

  /// Removes password authentication only after verifying it and only when a
  /// provider identity still keeps the account reachable.
  public func removePasswordAuthentication(
    _ request: RemovePasswordAuthenticationRequest, accessToken: String, now: Date = .now
  ) throws -> AuthUserResponse {
    let currentUser = try authenticatedUser(for: accessToken, now: now)
    guard let index = state.users.firstIndex(where: { $0.id == currentUser.id }) else {
      throw AuthStoreError.invalidAccessToken
    }
    let user = state.users[index]
    guard let passwordHash = user.passwordHash else {
      throw AuthStoreError.passwordAuthenticationNotLinked
    }
    guard try Bcrypt.verify(request.currentPassword, created: passwordHash) else {
      throw AuthStoreError.invalidCredentials
    }
    guard authenticationMethods(for: user.id).count > 1 else {
      throw AuthStoreError.cannotRemoveLastAuthentication
    }
    state.users[index] = StoredUser(
      id: user.id, email: user.email, displayName: user.displayName,
      passwordHash: nil, createdAt: user.createdAt, emailVerified: user.emailVerified,
      leaderboardOptedOut: user.leaderboardOptedOut, profileDetails: user.profileDetails,
      selectedBadgeID: user.selectedBadgeID, startedTestCount: user.startedTestCount)
    state.passwordResetTokens.removeAll { $0.userID == user.id }
    let currentTokenHash = Self.tokenHash(accessToken)
    state.sessions.removeAll { $0.userID == user.id && $0.tokenHash != currentTokenHash }
    try persist()
    return try userResponse(for: user.id)
  }

  /// Starts a short-lived OAuth transaction. The raw state is returned only to
  /// the caller and its SHA-256 hash is all that reaches persisted state.
  public func beginOAuth(
    provider: OAuthProvider, purpose: OAuthAuthorizationPurpose, accessToken: String? = nil,
    now: Date = .now
  ) throws -> OAuthAuthorizationRequest {
    let userID: UUID?
    switch purpose {
    case .signIn:
      userID = nil
    case .link, .reauthenticate:
      guard let accessToken else { throw AuthStoreError.invalidAccessToken }
      userID = try authenticatedUser(for: accessToken, now: now).id
    }
    state.oauthTransactions.removeAll { $0.expiresAt <= now }
    let stateToken = Self.makeAccessToken()
    let codeVerifier = Self.makeAccessToken()
    state.oauthTransactions.append(
      .init(
        provider: provider, stateHash: Self.tokenHash(stateToken), codeVerifier: codeVerifier,
        purpose: purpose, userID: userID, expiresAt: now.addingTimeInterval(10 * 60), status: .pending,
        subject: nil, email: nil, suggestedDisplayName: nil, avatarHash: nil, authenticatedUserID: nil,
        failureMessage: nil))
    try persist()
    return .init(
      provider: provider, state: stateToken, codeChallenge: Self.codeChallenge(for: codeVerifier))
  }

  /// Consumes the pending state before an external exchange begins, preventing
  /// callback replay from exchanging the same code more than once.
  public func beginOAuthCallback(
    provider: OAuthProvider, stateToken: String, now: Date = .now
  ) throws -> OAuthCallbackExchange {
    let stateHash = Self.tokenHash(stateToken)
    guard let index = state.oauthTransactions.firstIndex(where: {
      $0.provider == provider && $0.stateHash == stateHash && $0.expiresAt > now && $0.status == .pending
    }) else { throw AuthStoreError.invalidOAuthTransaction }
    state.oauthTransactions[index].status = .exchanging
    let verifier = state.oauthTransactions[index].codeVerifier
    try persist()
    return .init(provider: provider, codeVerifier: verifier)
  }

  /// Records a provider-validated identity without storing its credentials.
  /// The native app later consumes this state to sign in, link, or select a
  /// display name for a new account.
  public func completeOAuthCallback(
    stateToken: String, identity: OAuthProviderIdentity, now: Date = .now
  ) throws {
    let stateHash = Self.tokenHash(stateToken)
    guard let index = state.oauthTransactions.firstIndex(where: {
      $0.provider == identity.provider && $0.stateHash == stateHash && $0.expiresAt > now && $0.status == .exchanging
    }) else { throw AuthStoreError.invalidOAuthTransaction }
    let (subject, email) = try validatedOAuthIdentity(identity)
    switch state.oauthTransactions[index].purpose {
    case .signIn:
      if let existingIndex = state.oauthIdentities.firstIndex(where: {
        $0.provider == identity.provider && $0.subject == subject
      }) {
        if let avatarHash = Self.discordAvatarHash(from: identity) {
          state.oauthIdentities[existingIndex].avatarHash = avatarHash
        }
        state.oauthTransactions[index].status = .signedIn
        state.oauthTransactions[index].subject = nil
        state.oauthTransactions[index].email = nil
        state.oauthTransactions[index].suggestedDisplayName = nil
        state.oauthTransactions[index].avatarHash = nil
        state.oauthTransactions[index].authenticatedUserID = state.oauthIdentities[existingIndex].userID
      } else if state.users.contains(where: { $0.email == email }) {
        state.oauthTransactions[index].status = .failed
        state.oauthTransactions[index].failureMessage =
          "This email already has a Typebar account. Sign in with an existing method before linking this provider."
      } else {
        state.oauthTransactions[index].status = .registrationRequired
        state.oauthTransactions[index].subject = subject
        state.oauthTransactions[index].email = email
        state.oauthTransactions[index].suggestedDisplayName = identity.suggestedDisplayName
        state.oauthTransactions[index].avatarHash = Self.discordAvatarHash(from: identity)
      }
    case .link:
      guard let userID = state.oauthTransactions[index].userID,
        state.users.contains(where: { $0.id == userID })
      else { throw AuthStoreError.invalidOAuthTransaction }
      if let existing = state.oauthIdentities.first(where: {
        $0.provider == identity.provider && $0.subject == subject
      }), existing.userID != userID {
        state.oauthTransactions[index].status = .failed
        state.oauthTransactions[index].failureMessage = "This provider identity is already linked to another Typebar account."
      } else {
        if let existingIndex = state.oauthIdentities.firstIndex(where: {
          $0.provider == identity.provider && $0.subject == subject && $0.userID == userID
        }) {
          if let avatarHash = Self.discordAvatarHash(from: identity) {
            state.oauthIdentities[existingIndex].avatarHash = avatarHash
          }
        } else {
          state.oauthIdentities.append(
            .init(
              provider: identity.provider, subject: subject, userID: userID, linkedAt: now,
              avatarHash: Self.discordAvatarHash(from: identity)))
        }
        state.oauthTransactions[index].status = .linked
      }
    case .reauthenticate:
      guard let userID = state.oauthTransactions[index].userID,
        state.users.contains(where: { $0.id == userID })
      else { throw AuthStoreError.invalidOAuthTransaction }
      guard state.oauthIdentities.contains(where: {
        $0.provider == identity.provider && $0.subject == subject && $0.userID == userID
      }) else {
        state.oauthTransactions[index].status = .failed
        state.oauthTransactions[index].failureMessage =
          "This provider identity is not linked to the current Typebar account."
        try persist()
        return
      }
      state.oauthTransactions[index].status = .reauthenticated
      state.oauthTransactions[index].authenticatedUserID = userID
    }
    try persist()
  }

  /// Lets a failed callback return a user-safe error through the same native
  /// callback path without logging provider responses or authorization codes.
  public func failOAuthCallback(stateToken: String, now: Date = .now) throws {
    let stateHash = Self.tokenHash(stateToken)
    guard let index = state.oauthTransactions.firstIndex(where: {
      $0.stateHash == stateHash && $0.expiresAt > now && $0.status == .exchanging
    }) else { throw AuthStoreError.invalidOAuthTransaction }
    state.oauthTransactions[index].status = .failed
    state.oauthTransactions[index].failureMessage = "The provider authentication was not completed."
    try persist()
  }

  public func oauthCompletion(stateToken: String, now: Date = .now) throws -> OAuthCompletionResponse {
    let stateHash = Self.tokenHash(stateToken)
    let originalCount = state.oauthTransactions.count
    state.oauthTransactions.removeAll { $0.expiresAt <= now }
    guard let index = state.oauthTransactions.firstIndex(where: { $0.stateHash == stateHash }) else {
      if state.oauthTransactions.count != originalCount { try persist() }
      throw AuthStoreError.invalidOAuthTransaction
    }
    let transaction = state.oauthTransactions[index]
    switch transaction.status {
    case .pending, .exchanging:
      return .init(
        status: .pending, email: nil, suggestedDisplayName: nil, session: nil, user: nil,
        reauthenticationToken: nil, message: nil)
    case .registrationRequired:
      return .init(
        status: .registrationRequired, email: transaction.email,
        suggestedDisplayName: transaction.suggestedDisplayName, session: nil, user: nil,
        reauthenticationToken: nil, message: nil)
    case .signedIn:
      guard let userID = transaction.authenticatedUserID,
        let user = state.users.first(where: { $0.id == userID })
      else { throw AuthStoreError.invalidOAuthTransaction }
      state.oauthTransactions.remove(at: index)
      let session = makeSession(for: user, now: now)
      try persist()
      return .init(
        status: .signedIn, email: nil, suggestedDisplayName: nil, session: session, user: nil,
        reauthenticationToken: nil, message: nil)
    case .linked:
      guard let userID = transaction.userID else { throw AuthStoreError.invalidOAuthTransaction }
      let user = try userResponse(for: userID)
      state.oauthTransactions.remove(at: index)
      try persist()
      return .init(
        status: .linked, email: nil, suggestedDisplayName: nil, session: nil, user: user,
        reauthenticationToken: nil, message: nil)
    case .reauthenticated:
      guard let userID = transaction.authenticatedUserID else {
        throw AuthStoreError.invalidOAuthTransaction
      }
      state.oauthTransactions.remove(at: index)
      let token = try makeReauthenticationToken(for: userID, now: now)
      return .init(
        status: .reauthenticated, email: nil, suggestedDisplayName: nil, session: nil, user: nil,
        reauthenticationToken: token.reauthenticationToken, message: nil)
    case .failed:
      state.oauthTransactions.remove(at: index)
      try persist()
      return .init(
        status: .failed, email: nil, suggestedDisplayName: nil, session: nil, user: nil,
        reauthenticationToken: nil,
        message: transaction.failureMessage ?? "The provider authentication was not completed.")
    }
  }

  public func completeOAuthRegistration(
    stateToken: String, displayName: String, now: Date = .now
  ) throws -> AuthSessionResponse {
    let stateHash = Self.tokenHash(stateToken)
    guard let index = state.oauthTransactions.firstIndex(where: {
      $0.stateHash == stateHash && $0.expiresAt > now && $0.status == .registrationRequired
    }), let subject = state.oauthTransactions[index].subject,
      let email = state.oauthTransactions[index].email
    else { throw AuthStoreError.oauthRegistrationNotRequired }
    let transaction = state.oauthTransactions[index]
    let name = try validatedDisplayName(displayName)
    guard !state.oauthIdentities.contains(where: {
      $0.provider == transaction.provider && $0.subject == subject
    }) else { throw AuthStoreError.oauthIdentityAlreadyLinked }
    guard !state.users.contains(where: { $0.email == email }) else {
      throw AuthStoreError.emailAlreadyRegistered
    }
    let user = StoredUser(
      id: UUID(), email: email, displayName: name, passwordHash: nil, createdAt: now,
      emailVerified: true)
    state.users.append(user)
    state.oauthIdentities.append(
      .init(
        provider: transaction.provider, subject: subject, userID: user.id, linkedAt: now,
        avatarHash: transaction.avatarHash))
    state.oauthTransactions.remove(at: index)
    let session = makeSession(for: user, now: now)
    try persist()
    return session
  }

  /// Creates a 20-minute, one-time reset token for a known account. Invalid
  /// and unknown addresses intentionally return `nil` instead of an error so
  /// the route can provide the same response to every caller.
  public func requestPasswordReset(for rawEmail: String, now: Date = .now) throws
    -> PasswordResetDelivery?
  {
    let tokenCount = state.passwordResetTokens.count
    state.passwordResetTokens.removeAll { $0.expiresAt <= now }
    guard let email = normalizedEmail(rawEmail),
      let user = state.users.first(where: { $0.email == email }), user.passwordHash != nil
    else {
      if state.passwordResetTokens.count != tokenCount { try persist() }
      return nil
    }

    state.passwordResetTokens.removeAll { $0.userID == user.id }
    let token = Self.makeAccessToken()
    let expiresAt = now.addingTimeInterval(20 * 60)
    state.passwordResetTokens.append(
      .init(tokenHash: Self.tokenHash(token), userID: user.id, expiresAt: expiresAt))
    try persist()
    return .init(email: user.email, token: token, expiresAt: expiresAt)
  }

  /// Revokes a newly-issued reset token if the configured delivery mechanism
  /// fails. It intentionally accepts the opaque raw token only transiently.
  public func cancelPasswordReset(token: String) throws {
    let tokenHash = Self.tokenHash(token)
    let count = state.passwordResetTokens.count
    state.passwordResetTokens.removeAll { $0.tokenHash == tokenHash }
    if state.passwordResetTokens.count != count { try persist() }
  }

  /// Replaces a password through a short-lived reset token. It never creates a
  /// new session: every current device is signed out and the person must log in
  /// again using the new password.
  public func completePasswordReset(
    _ request: CompletePasswordResetRequest, now: Date = .now
  ) throws {
    let tokenCount = state.passwordResetTokens.count
    state.passwordResetTokens.removeAll { $0.expiresAt <= now }
    let tokenHash = Self.tokenHash(request.token)
    guard let reset = state.passwordResetTokens.first(where: { $0.tokenHash == tokenHash }),
      let userIndex = state.users.firstIndex(where: { $0.id == reset.userID })
    else {
      if state.passwordResetTokens.count != tokenCount { try persist() }
      throw AuthStoreError.invalidPasswordResetToken
    }
    try validatedPassword(request.newPassword)

    let user = state.users[userIndex]
    state.users[userIndex] = StoredUser(
      id: user.id, email: user.email, displayName: user.displayName,
      passwordHash: try Bcrypt.hash(request.newPassword, cost: bcryptCost),
      createdAt: user.createdAt, emailVerified: user.emailVerified,
      leaderboardOptedOut: user.leaderboardOptedOut, profileDetails: user.profileDetails,
      selectedBadgeID: user.selectedBadgeID, startedTestCount: user.startedTestCount)
    state.sessions.removeAll { $0.userID == user.id }
    state.passwordResetTokens.removeAll { $0.userID == user.id }
    try persist()
  }

  /// Creates a 24-hour, one-time email verification token for the current
  /// account. Already verified accounts do not receive another token.
  public func requestEmailVerification(accessToken: String, now: Date = .now) throws
    -> EmailVerificationDelivery?
  {
    let currentUser = try authenticatedUser(for: accessToken, now: now)
    guard let user = state.users.first(where: { $0.id == currentUser.id }) else {
      throw AuthStoreError.invalidAccessToken
    }
    let tokenCount = state.emailVerificationTokens.count
    state.emailVerificationTokens.removeAll { $0.expiresAt <= now }
    guard !user.emailVerified else {
      if state.emailVerificationTokens.count != tokenCount { try persist() }
      return nil
    }

    state.emailVerificationTokens.removeAll { $0.userID == user.id }
    let token = Self.makeAccessToken()
    let expiresAt = now.addingTimeInterval(60 * 60 * 24)
    state.emailVerificationTokens.append(
      .init(tokenHash: Self.tokenHash(token), userID: user.id, expiresAt: expiresAt))
    try persist()
    return .init(email: user.email, token: token, expiresAt: expiresAt)
  }

  /// Cancels an undelivered verification token without persisting the raw
  /// value or disclosing whether the account has since been verified.
  public func cancelEmailVerification(token: String) throws {
    let tokenHash = Self.tokenHash(token)
    let count = state.emailVerificationTokens.count
    state.emailVerificationTokens.removeAll { $0.tokenHash == tokenHash }
    if state.emailVerificationTokens.count != count { try persist() }
  }

  public func completeEmailVerification(
    _ request: CompleteEmailVerificationRequest, now: Date = .now
  ) throws {
    let tokenCount = state.emailVerificationTokens.count
    state.emailVerificationTokens.removeAll { $0.expiresAt <= now }
    let tokenHash = Self.tokenHash(request.token)
    guard let verification = state.emailVerificationTokens.first(where: { $0.tokenHash == tokenHash }),
      let userIndex = state.users.firstIndex(where: { $0.id == verification.userID })
    else {
      if state.emailVerificationTokens.count != tokenCount { try persist() }
      throw AuthStoreError.invalidEmailVerificationToken
    }

    let user = state.users[userIndex]
    state.users[userIndex] = StoredUser(
      id: user.id, email: user.email, displayName: user.displayName,
      passwordHash: user.passwordHash, createdAt: user.createdAt, emailVerified: true,
      leaderboardOptedOut: user.leaderboardOptedOut, profileDetails: user.profileDetails,
      selectedBadgeID: user.selectedBadgeID, startedTestCount: user.startedTestCount)
    state.emailVerificationTokens.removeAll { $0.userID == user.id }
    try persist()
  }

  public func authenticatedUser(for accessToken: String, now: Date = .now) throws
    -> AuthUserResponse
  {
    let hash = Self.tokenHash(accessToken)
    guard let session = state.sessions.first(where: { $0.tokenHash == hash && $0.expiresAt > now }),
      let user = state.users.first(where: { $0.id == session.userID })
    else { throw AuthStoreError.invalidAccessToken }
    return userResponse(for: user)
  }

  public func developerAccessKeys(accessToken: String, now: Date = .now) throws
    -> DeveloperAccessKeyListResponse
  {
    let user = try authenticatedUser(for: accessToken, now: now)
    let keys = state.developerAccessKeys
      .filter { $0.userID == user.id }
      .sorted { $0.createdAt > $1.createdAt }
      .map { $0.response() }
    return .init(keys: keys)
  }

  public func createDeveloperAccessKey(
    _ request: CreateDeveloperAccessKeyRequest, accessToken: String, now: Date = .now
  ) throws -> CreateDeveloperAccessKeyResponse {
    let user = try authenticatedUser(for: accessToken, now: now)
    guard state.developerAccessKeys.filter({ $0.userID == user.id }).count < 5 else {
      throw AuthStoreError.developerAccessKeyLimitReached
    }
    let name = try validatedDeveloperAccessKeyName(request.name)
    let accessKey = "tbak_\(Self.makeAccessToken())"
    let stored = StoredDeveloperAccessKey(
      id: UUID(), userID: user.id, tokenHash: Self.tokenHash(accessKey), name: name,
      enabled: true, createdAt: now, modifiedAt: now, lastUsedAt: nil)
    state.developerAccessKeys.append(stored)
    try persist()
    return .init(key: stored.response(), accessKey: accessKey)
  }

  public func updateDeveloperAccessKey(
    id: UUID, request: UpdateDeveloperAccessKeyRequest, accessToken: String, now: Date = .now
  ) throws -> DeveloperAccessKey {
    guard request.name != nil || request.enabled != nil else {
      throw AuthStoreError.invalidDeveloperAccessKeyName
    }
    let user = try authenticatedUser(for: accessToken, now: now)
    guard let index = state.developerAccessKeys.firstIndex(where: {
      $0.id == id && $0.userID == user.id
    }) else { throw AuthStoreError.developerAccessKeyNotFound }
    let existing = state.developerAccessKeys[index]
    let updated = StoredDeveloperAccessKey(
      id: existing.id, userID: existing.userID, tokenHash: existing.tokenHash,
      name: try request.name.map(validatedDeveloperAccessKeyName) ?? existing.name,
      enabled: request.enabled ?? existing.enabled, createdAt: existing.createdAt,
      modifiedAt: now, lastUsedAt: existing.lastUsedAt)
    state.developerAccessKeys[index] = updated
    try persist()
    return updated.response()
  }

  public func deleteDeveloperAccessKey(
    id: UUID, accessToken: String, now: Date = .now
  ) throws {
    let user = try authenticatedUser(for: accessToken, now: now)
    guard let index = state.developerAccessKeys.firstIndex(where: {
      $0.id == id && $0.userID == user.id
    }) else { throw AuthStoreError.developerAccessKeyNotFound }
    state.developerAccessKeys.remove(at: index)
    try persist()
  }

  /// Replaces the password only after checking the existing password, then
  /// invalidates every existing device session and returns one fresh session.
  public func changePassword(
    _ request: ChangePasswordRequest, accessToken: String, now: Date = .now
  ) throws -> AuthSessionResponse {
    let currentUser = try authenticatedUser(for: accessToken, now: now)
    guard let index = state.users.firstIndex(where: { $0.id == currentUser.id }) else {
      throw AuthStoreError.invalidAccessToken
    }
    let user = state.users[index]
    guard let passwordHash = user.passwordHash,
      try Bcrypt.verify(request.currentPassword, created: passwordHash)
    else {
      throw AuthStoreError.invalidCredentials
    }
    try validatedPassword(request.newPassword)

    let updatedUser = StoredUser(
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      passwordHash: try Bcrypt.hash(request.newPassword, cost: bcryptCost),
      createdAt: user.createdAt,
      emailVerified: user.emailVerified,
      leaderboardOptedOut: user.leaderboardOptedOut,
      profileDetails: user.profileDetails,
      selectedBadgeID: user.selectedBadgeID,
      startedTestCount: user.startedTestCount
    )
    state.users[index] = updatedUser
    state.sessions.removeAll { $0.userID == updatedUser.id }
    state.passwordResetTokens.removeAll { $0.userID == updatedUser.id }
    let response = makeSession(for: updatedUser, now: now)
    try persist()
    return response
  }

  /// Changes the account email only after checking the existing password,
  /// then invalidates every previous device session and returns one fresh one.
  public func changeEmail(_ request: ChangeEmailRequest, accessToken: String, now: Date = .now)
    throws -> AuthSessionResponse
  {
    let currentUser = try authenticatedUser(for: accessToken, now: now)
    guard let index = state.users.firstIndex(where: { $0.id == currentUser.id }) else {
      throw AuthStoreError.invalidAccessToken
    }
    let user = state.users[index]
    guard let passwordHash = user.passwordHash,
      try Bcrypt.verify(request.currentPassword, created: passwordHash)
    else {
      throw AuthStoreError.invalidCredentials
    }
    let email = try validatedEmail(request.newEmail)
    guard email != user.email else { throw AuthStoreError.invalidEmail }
    guard !state.users.contains(where: { $0.id != user.id && $0.email == email }) else {
      throw AuthStoreError.emailAlreadyRegistered
    }

    let updatedUser = StoredUser(
      id: user.id, email: email, displayName: user.displayName,
      passwordHash: user.passwordHash, createdAt: user.createdAt,
      emailVerified: false,
      leaderboardOptedOut: user.leaderboardOptedOut,
      profileDetails: user.profileDetails,
      selectedBadgeID: user.selectedBadgeID,
      startedTestCount: user.startedTestCount
    )
    state.users[index] = updatedUser
    state.sessions.removeAll { $0.userID == updatedUser.id }
    state.passwordResetTokens.removeAll { $0.userID == updatedUser.id }
    state.emailVerificationTokens.removeAll { $0.userID == updatedUser.id }
    let response = makeSession(for: updatedUser, now: now)
    try persist()
    return response
  }

  /// Revokes every session for the authenticated account after confirming the
  /// current password or a one-time reauthentication. The caller's session is
  /// intentionally included, so the device must sign in again.
  public func revokeAllSessions(
    _ request: RevokeSessionsRequest, accessToken: String, reauthenticationToken: String? = nil,
    now: Date = .now
  ) throws {
    let currentUser = try authenticatedUser(for: accessToken, now: now)
    guard let user = state.users.first(where: { $0.id == currentUser.id }) else {
      throw AuthStoreError.invalidAccessToken
    }
    if let currentPassword = request.currentPassword {
      guard let passwordHash = user.passwordHash,
        try Bcrypt.verify(currentPassword, created: passwordHash)
      else { throw AuthStoreError.invalidCredentials }
    } else {
      guard let reauthenticationToken else { throw AuthStoreError.invalidReauthenticationToken }
      try consumeReauthenticationToken(reauthenticationToken, for: user.id, now: now)
    }
    state.sessions.removeAll { $0.userID == user.id }
    try persist()
  }

  /// Deletes the authenticated account and every record owned by it. A current
  /// password or one-time reauthentication is required so a leaked access token
  /// cannot erase it.
  public func deleteAccount(
    _ request: DeleteAccountRequest, accessToken: String, reauthenticationToken: String? = nil,
    now: Date = .now
  )
    throws
  {
    let currentUser = try authenticatedUser(for: accessToken, now: now)
    guard let index = state.users.firstIndex(where: { $0.id == currentUser.id }) else {
      throw AuthStoreError.invalidAccessToken
    }
    let user = state.users[index]
    if let currentPassword = request.currentPassword {
      guard let passwordHash = user.passwordHash,
        try Bcrypt.verify(currentPassword, created: passwordHash)
      else { throw AuthStoreError.invalidCredentials }
    } else {
      guard let reauthenticationToken else { throw AuthStoreError.invalidReauthenticationToken }
      try consumeReauthenticationToken(reauthenticationToken, for: user.id, now: now)
    }
    let userID = currentUser.id
    let removedQuoteIDs = Set(state.quoteSubmissions.filter { $0.userID == userID }.map(\.id))

    state.users.remove(at: index)
    state.sessions.removeAll { $0.userID == userID }
    state.developerAccessKeys.removeAll { $0.userID == userID }
    state.passwordResetTokens.removeAll { $0.userID == userID }
    state.emailVerificationTokens.removeAll { $0.userID == userID }
    state.oauthIdentities.removeAll { $0.userID == userID }
    state.oauthTransactions.removeAll { $0.userID == userID }
    state.reauthenticationTokens.removeAll { $0.userID == userID }
    state.syncRecords.removeAll { $0.userID == userID }
    state.results.removeAll { $0.userID == userID }
    state.connections.removeAll { $0.requesterID == userID || $0.recipientID == userID }
    state.quoteSubmissions.removeAll { $0.userID == userID }
    state.quoteRatings.removeAll { $0.userID == userID || removedQuoteIDs.contains($0.quoteID) }
    state.notifications.removeAll { $0.recipientID == userID || $0.actorID == userID }
    state.profileReports.removeAll { $0.reporterID == userID || $0.profileID == userID }
    state.quoteReports.removeAll { $0.reporterID == userID || removedQuoteIDs.contains($0.quoteID) }
    state.directMessages.removeAll { $0.senderID == userID || $0.recipientID == userID }
    state.blockedUserIDs = state.blockedUserIDs.reduce(into: [:]) { filtered, pair in
      guard pair.key != userID else { return }
      filtered[pair.key] = pair.value.filter { $0 != userID }
    }
    try persist()
  }

  public func updateProfile(_ request: UpdateProfileRequest, accessToken: String, now: Date = .now)
    throws -> AuthUserResponse
  {
    let currentUser = try authenticatedUser(for: accessToken, now: now)
    guard let index = state.users.firstIndex(where: { $0.id == currentUser.id }) else {
      throw AuthStoreError.invalidAccessToken
    }
    let user = state.users[index]
    let displayName = try request.displayName.map(validatedDisplayName) ?? user.displayName
    let profileDetails = try request.profileDetails.map(validatedProfileDetails) ?? user.profileDetails
    let selectedBadgeID = try validatedSelectedBadgeID(
      request.selectedBadgeID, existing: user.selectedBadgeID, userID: user.id)
    let updatedUser = StoredUser(
      id: user.id, email: user.email, displayName: displayName, passwordHash: user.passwordHash,
      createdAt: user.createdAt, emailVerified: user.emailVerified,
      leaderboardOptedOut: request.leaderboardOptedOut ?? user.leaderboardOptedOut,
      profileDetails: profileDetails, selectedBadgeID: selectedBadgeID,
      startedTestCount: user.startedTestCount)
    state.users[index] = updatedUser
    try persist()
    return userResponse(for: updatedUser)
  }

  public func publicProfile(id: UUID, now: Date = .now) throws -> PublicProfileResponse {
    guard let user = state.users.first(where: { $0.id == id }) else {
      throw AuthStoreError.profileNotFound
    }
    return detailedPublicProfile(for: user, now: now)
  }

  public func searchPublicProfiles(query: String?, limit: Int?) throws
    -> PublicProfileSearchResponse
  {
    let term = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard term.count >= 2, term.count <= 40 else { throw AuthStoreError.invalidProfileSearch }
    let count = min(max(limit ?? 20, 1), 50)
    let profiles = state.users
      .filter {
        $0.displayName.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
      }
      .sorted {
        $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
      }
      .prefix(count)
      .map(publicProfile(for:))
    return .init(profiles: profiles)
  }

  public func sendConnection(_ request: ConnectionRequest, accessToken: String, now: Date = .now)
    throws -> ConnectionResponse
  {
    let current = try authenticatedUser(for: accessToken, now: now)
    guard current.id != request.recipientID else { throw AuthStoreError.cannotConnectToSelf }
    guard !isBlocked(between: current.id, and: request.recipientID) else {
      throw AuthStoreError.connectionNotFound
    }
    guard let recipient = state.users.first(where: { $0.id == request.recipientID }) else {
      throw AuthStoreError.profileNotFound
    }
    guard
      !state.connections.contains(where: {
        ($0.requesterID == current.id && $0.recipientID == recipient.id)
          || ($0.requesterID == recipient.id && $0.recipientID == current.id)
      })
    else {
      throw AuthStoreError.connectionAlreadyExists
    }
    state.connections.append(
      .init(requesterID: current.id, recipientID: recipient.id, status: "pending", updatedAt: now))
    state.notifications.append(
      .init(
        id: UUID(), recipientID: recipient.id, actorID: current.id, kind: .connectionRequest,
        createdAt: now, readAt: nil))
    try persist()
    return .init(
      id: recipient.id, profile: publicProfile(for: recipient), relation: .outgoingRequest,
      updatedAt: now)
  }

  public func acceptConnection(requesterID: UUID, accessToken: String, now: Date = .now) throws
    -> ConnectionResponse
  {
    let current = try authenticatedUser(for: accessToken, now: now)
    guard
      let index = state.connections.firstIndex(where: {
        $0.requesterID == requesterID && $0.recipientID == current.id
      })
    else { throw AuthStoreError.connectionNotFound }
    guard state.connections[index].status == "pending" else {
      throw AuthStoreError.connectionNotPending
    }
    state.connections[index].status = "accepted"
    state.connections[index].updatedAt = now
    guard let requester = state.users.first(where: { $0.id == requesterID }) else {
      throw AuthStoreError.profileNotFound
    }
    state.notifications.append(
      .init(
        id: UUID(), recipientID: requester.id, actorID: current.id, kind: .connectionAccepted,
        createdAt: now, readAt: nil))
    try persist()
    return .init(
      id: requester.id, profile: publicProfile(for: requester), relation: .friend, updatedAt: now)
  }

  public func removeConnection(otherUserID: UUID, accessToken: String, now: Date = .now) throws {
    let current = try authenticatedUser(for: accessToken, now: now)
    guard
      let index = state.connections.firstIndex(where: {
        ($0.requesterID == current.id && $0.recipientID == otherUserID)
          || ($0.requesterID == otherUserID && $0.recipientID == current.id)
      })
    else {
      throw AuthStoreError.connectionNotFound
    }
    state.connections.remove(at: index)
    try persist()
  }

  public func blockUser(_ otherUserID: UUID, accessToken: String, now: Date = .now) throws {
    let current = try authenticatedUser(for: accessToken, now: now)
    guard current.id != otherUserID, state.users.contains(where: { $0.id == otherUserID }) else {
      throw AuthStoreError.profileNotFound
    }
    var blocked = Set(state.blockedUserIDs[current.id] ?? [])
    blocked.insert(otherUserID)
    state.blockedUserIDs[current.id] = Array(blocked)
    state.connections.removeAll {
      ($0.requesterID == current.id && $0.recipientID == otherUserID)
        || ($0.requesterID == otherUserID && $0.recipientID == current.id)
    }
    state.directMessages.removeAll {
      ($0.senderID == current.id && $0.recipientID == otherUserID)
        || ($0.senderID == otherUserID && $0.recipientID == current.id)
    }
    try persist()
  }

  public func unblockUser(_ otherUserID: UUID, accessToken: String, now: Date = .now) throws {
    let current = try authenticatedUser(for: accessToken, now: now)
    guard var blocked = state.blockedUserIDs[current.id], blocked.contains(otherUserID) else {
      throw AuthStoreError.connectionNotFound
    }
    blocked.removeAll { $0 == otherUserID }
    state.blockedUserIDs[current.id] = blocked
    try persist()
  }

  public func blockedUsers(accessToken: String, now: Date = .now) throws -> BlockedUsersResponse {
    let current = try authenticatedUser(for: accessToken, now: now)
    let profiles = (state.blockedUserIDs[current.id] ?? []).compactMap { id in
      state.users.first(where: { $0.id == id }).map(publicProfile(for:))
    }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    return .init(profiles: profiles)
  }

  public func notifications(accessToken: String, now: Date = .now) throws
    -> TypebarNotificationsResponse
  {
    let current = try authenticatedUser(for: accessToken, now: now)
    let notifications = state.notifications.compactMap {
      notification -> TypebarNotificationResponse? in
      guard notification.recipientID == current.id,
        let actor = state.users.first(where: { $0.id == notification.actorID })
      else { return nil }
      return .init(
        id: notification.id, kind: notification.kind, actor: publicProfile(for: actor),
        createdAt: notification.createdAt, readAt: notification.readAt)
    }
    .sorted { $0.createdAt > $1.createdAt }
    return .init(notifications: notifications)
  }

  public func markNotificationRead(_ id: UUID, accessToken: String, now: Date = .now) throws
    -> TypebarNotificationResponse
  {
    let current = try authenticatedUser(for: accessToken, now: now)
    guard
      let index = state.notifications.firstIndex(where: {
        $0.id == id && $0.recipientID == current.id
      })
    else {
      throw AuthStoreError.notificationNotFound
    }
    if state.notifications[index].readAt == nil {
      state.notifications[index].readAt = now
      try persist()
    }
    let notification = state.notifications[index]
    guard let actor = state.users.first(where: { $0.id == notification.actorID }) else {
      throw AuthStoreError.notificationNotFound
    }
    return .init(
      id: notification.id, kind: notification.kind, actor: publicProfile(for: actor),
      createdAt: notification.createdAt, readAt: notification.readAt)
  }

  /// Stores an account-scoped report for a private moderation workflow. The
  /// reported profile is neither notified nor changed by this operation.
  public func submitProfileReport(
    _ request: ProfileReportRequest, accessToken: String, now: Date = .now
  ) throws -> ProfileReportResponse {
    let reporter = try authenticatedUser(for: accessToken, now: now)
    guard reporter.id != request.profileID else { throw AuthStoreError.cannotReportSelf }
    guard state.users.contains(where: { $0.id == request.profileID }) else {
      throw AuthStoreError.profileNotFound
    }
    let note = request.note?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard note?.count ?? 0 <= 400 else { throw AuthStoreError.invalidProfileReport }
    guard
      !state.profileReports.contains(where: {
        $0.reporterID == reporter.id && $0.profileID == request.profileID
          && $0.reason == request.reason
      })
    else { throw AuthStoreError.reportAlreadySubmitted }

    let report = StoredProfileReport(
      id: UUID(), reporterID: reporter.id, profileID: request.profileID,
      reason: request.reason, note: note?.isEmpty == true ? nil : note, submittedAt: now
    )
    state.profileReports.append(report)
    try persist()
    return .init(id: report.id, submittedAt: report.submittedAt)
  }

  /// Reads the currently published deployment announcements without requiring
  /// an account. The server owns the set, so returning it whole avoids making
  /// a locally dismissed item reappear merely because it fell off a page.
  public func publicAnnouncements() -> PublicAnnouncementsResponse {
    .init(
      announcements: state.announcements
        .sorted { $0.publishedAt > $1.publishedAt }
        .map { $0.response() })
  }

  /// The route layer authorizes the deployment key; this store method only
  /// validates and persists an original Typebar announcement.
  public func publishAnnouncement(
    _ request: AnnouncementPublicationRequest, now: Date = .now
  ) throws -> PublicAnnouncementResponse {
    let message = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty, message.count <= 500 else { throw AuthStoreError.invalidAnnouncement }
    guard (request.scheduledAt?.timeIntervalSince1970 ?? 0) >= 0 else {
      throw AuthStoreError.invalidAnnouncement
    }
    let announcement = StoredAnnouncement(
      id: UUID(), message: message, level: request.level, sticky: request.sticky,
      scheduledAt: request.scheduledAt, publishedAt: now)
    state.announcements.append(announcement)
    try persist()
    return announcement.response()
  }

  /// Deleting an announcement only removes that public message. It never
  /// changes accounts, notifications, results, or local acknowledgement data.
  public func removeAnnouncement(_ id: UUID) throws -> Bool {
    let oldCount = state.announcements.count
    state.announcements.removeAll { $0.id == id }
    guard state.announcements.count != oldCount else { throw AuthStoreError.profileNotFound }
    try persist()
    return true
  }

  /// Lists only the minimum private-review context for reports whose target
  /// still exists. The deployment route authenticates the reviewer; this
  /// store API intentionally never accepts or returns reporter identities.
  public func moderationProfileReports(status: ProfileReportModerationStatus?, limit: Int?)
    -> ModerationProfileReportListResponse
  {
    let resolvedLimit = min(max(limit ?? 50, 1), 100)
    let reports = state.profileReports
      .filter { status == nil || $0.status == status }
      .sorted { $0.submittedAt > $1.submittedAt }
      .prefix(resolvedLimit)
      .compactMap { report -> ModerationProfileReportResponse? in
        guard let profile = state.users.first(where: { $0.id == report.profileID }) else {
          return nil
        }
        return .init(
          id: report.id,
          profile: publicProfile(for: profile),
          reason: report.reason,
          note: report.note,
          status: report.status,
          submittedAt: report.submittedAt
        )
      }
    return .init(reports: Array(reports))
  }

  /// Changes review metadata only. No account visibility, results, profile
  /// data, relationship or notification is modified as a side effect.
  public func moderateProfileReport(_ id: UUID, status: ProfileReportModerationStatus) throws
    -> ModerationProfileReportResponse
  {
    guard let index = state.profileReports.firstIndex(where: { $0.id == id }) else {
      throw AuthStoreError.profileNotFound
    }
    guard let profile = state.users.first(where: { $0.id == state.profileReports[index].profileID })
    else { throw AuthStoreError.profileNotFound }
    state.profileReports[index].status = status
    try persist()
    let report = state.profileReports[index]
    return .init(
      id: report.id, profile: publicProfile(for: profile), reason: report.reason, note: report.note,
      status: report.status, submittedAt: report.submittedAt)
  }

  public func submitQuoteReport(
    _ request: QuoteReportRequest, accessToken: String, now: Date = .now
  ) throws -> QuoteReportResponse {
    let reporter = try authenticatedUser(for: accessToken, now: now)
    guard
      let quote = state.quoteSubmissions.first(where: {
        $0.id == request.quoteID && $0.status == "approved"
      }), quote.userID != reporter.id
    else { throw AuthStoreError.profileNotFound }
    let note = request.note?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard note?.count ?? 0 <= 400 else { throw AuthStoreError.invalidQuoteSubmission }
    guard
      !state.quoteReports.contains(where: {
        $0.reporterID == reporter.id && $0.quoteID == request.quoteID && $0.reason == request.reason
      })
    else { throw AuthStoreError.reportAlreadySubmitted }
    let report = StoredQuoteReport(
      id: UUID(), reporterID: reporter.id, quoteID: quote.id, reason: request.reason,
      note: note?.isEmpty == true ? nil : note, submittedAt: now)
    state.quoteReports.append(report)
    try persist()
    return .init(id: report.id, submittedAt: report.submittedAt)
  }

  public func directConversation(with otherUserID: UUID, accessToken: String, now: Date = .now)
    throws -> DirectConversationResponse
  {
    let current = try authenticatedUser(for: accessToken, now: now)
    guard canExchangeMessages(between: current.id, and: otherUserID) else {
      throw AuthStoreError.directMessageNotAllowed
    }
    let messages = state.directMessages
      .filter {
        ($0.senderID == current.id && $0.recipientID == otherUserID)
          || ($0.senderID == otherUserID && $0.recipientID == current.id)
      }
      .sorted { $0.createdAt < $1.createdAt }
      .map(directMessageResponse(for:))
    return .init(messages: messages)
  }

  public func sendDirectMessage(
    _ request: DirectMessageRequest, accessToken: String, now: Date = .now
  ) throws -> DirectMessageResponse {
    let current = try authenticatedUser(for: accessToken, now: now)
    guard canExchangeMessages(between: current.id, and: request.recipientID) else {
      throw AuthStoreError.directMessageNotAllowed
    }
    let body = request.body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...1_000).contains(body.count) else { throw AuthStoreError.invalidDirectMessage }
    let message = StoredDirectMessage(
      id: UUID(), senderID: current.id, recipientID: request.recipientID, body: body,
      createdAt: now, readAt: nil)
    state.directMessages.append(message)
    state.notifications.append(
      .init(
        id: UUID(), recipientID: request.recipientID, actorID: current.id, kind: .directMessage,
        createdAt: now, readAt: nil))
    try persist()
    return directMessageResponse(for: message)
  }

  public func markDirectConversationRead(
    with otherUserID: UUID, accessToken: String, now: Date = .now
  ) throws {
    let current = try authenticatedUser(for: accessToken, now: now)
    guard canExchangeMessages(between: current.id, and: otherUserID) else {
      throw AuthStoreError.directMessageNotAllowed
    }
    var changed = false
    for index in state.directMessages.indices
    where state.directMessages[index].senderID == otherUserID
      && state.directMessages[index].recipientID == current.id
      && state.directMessages[index].readAt == nil
    {
      state.directMessages[index].readAt = now
      changed = true
    }
    if changed { try persist() }
  }

  public func submitQuote(_ request: QuoteSubmissionRequest, accessToken: String, now: Date = .now)
    throws -> QuoteSubmissionResponse
  {
    let user = try authenticatedUser(for: accessToken, now: now)
    let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let attribution = request.attribution?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      Set([
        "english", "spanish", "german", "afrikaans", "greek", "greeklish", "dutch", "danish", "norwegianBokmal", "norwegianNynorsk", "swedish", "hungarian", "czech", "slovak", "slovenian", "croatian", "serbian", "serbianLatin", "bulgarian", "romanian", "finnish", "estonian", "icelandic", "french", "italian", "portuguese",
        "simplifiedChinese",
        "traditionalChinese", "russian", "ukrainian", "ukrainianLatin", "japaneseHiragana", "japaneseKatakana", "japaneseRomaji",
        "korean", "turkish", "polish",
      ])
        .contains(request.language), (10...500).contains(text.count), attribution?.count ?? 0 <= 80
    else { throw AuthStoreError.invalidQuoteSubmission }
    let submission = StoredQuoteSubmission(
      id: UUID(), userID: user.id, language: request.language, text: text,
      attribution: attribution?.isEmpty == true ? nil : attribution, status: "pending",
      submittedAt: now)
    state.quoteSubmissions.append(submission)
    try persist()
    return .init(id: submission.id, status: submission.status, submittedAt: submission.submittedAt)
  }

  public func quoteSubmissions(accessToken: String, now: Date = .now) throws
    -> QuoteSubmissionListResponse
  {
    let user = try authenticatedUser(for: accessToken, now: now)
    let submissions: [QuoteSubmissionResponse] = state.quoteSubmissions.filter {
      $0.userID == user.id
    }.sorted { $0.submittedAt > $1.submittedAt }.map {
      QuoteSubmissionResponse(id: $0.id, status: $0.status, submittedAt: $0.submittedAt)
    }
    return .init(submissions: submissions)
  }

  /// Returns review material only for the deployment-owned moderation route.
  /// Reporter identity stays in private storage and is never part of this
  /// response, while report notes remain available for meaningful review.
  public func moderationQuotes(status: String?, limit: Int?) throws -> ModerationQuoteListResponse {
    if let status, !Set(["pending", "approved", "rejected"]).contains(status) {
      throw AuthStoreError.invalidQuoteSubmission
    }
    let resolvedLimit = min(max(limit ?? 50, 1), 100)
    let quotes = state.quoteSubmissions
      .filter { status == nil || $0.status == status }
      .sorted { $0.submittedAt > $1.submittedAt }
      .prefix(resolvedLimit)
      .map { submission in
        ModerationQuoteResponse(
          id: submission.id,
          language: submission.language,
          text: submission.text,
          attribution: submission.attribution,
          status: submission.status,
          submittedAt: submission.submittedAt,
          reports: state.quoteReports
            .filter { $0.quoteID == submission.id }
            .sorted { $0.submittedAt > $1.submittedAt }
            .map { .init(reason: $0.reason, note: $0.note, submittedAt: $0.submittedAt) }
        )
      }
    return .init(quotes: Array(quotes))
  }

  public func withdrawQuoteSubmission(_ id: UUID, accessToken: String, now: Date = .now) throws {
    let user = try authenticatedUser(for: accessToken, now: now)
    guard
      let index = state.quoteSubmissions.firstIndex(where: {
        $0.id == id && $0.userID == user.id && $0.status == "pending"
      })
    else { throw AuthStoreError.profileNotFound }
    state.quoteSubmissions.remove(at: index)
    state.quoteRatings.removeAll { $0.quoteID == id }
    state.quoteReports.removeAll { $0.quoteID == id }
    try persist()
  }

  /// The caller is authenticated by the deployment-level moderation key in
  /// the route layer. Keeping that key outside the persisted user store
  /// prevents ordinary accounts from granting themselves review access.
  public func moderateQuote(_ id: UUID, status: String) throws -> QuoteSubmissionResponse {
    guard Set(["approved", "rejected"]).contains(status),
      let index = state.quoteSubmissions.firstIndex(where: { $0.id == id })
    else { throw AuthStoreError.invalidQuoteSubmission }
    state.quoteSubmissions[index].status = status
    try persist()
    let quote = state.quoteSubmissions[index]
    return .init(id: quote.id, status: quote.status, submittedAt: quote.submittedAt)
  }

  public func rateQuote(
    _ id: UUID, request: QuoteRatingRequest, accessToken: String, now: Date = .now
  ) throws -> QuoteRatingResponse {
    let user = try authenticatedUser(for: accessToken, now: now)
    guard
      let quote = state.quoteSubmissions.first(where: { $0.id == id && $0.status == "approved" }),
      quote.userID != user.id,
      [-1, 0, 1].contains(request.value)
    else { throw AuthStoreError.invalidQuoteSubmission }
    if let index = state.quoteRatings.firstIndex(where: { $0.userID == user.id && $0.quoteID == id }
    ) {
      if request.value == 0 {
        state.quoteRatings.remove(at: index)
      } else {
        state.quoteRatings[index].value = request.value
      }
    } else if request.value != 0 {
      state.quoteRatings.append(.init(userID: user.id, quoteID: id, value: request.value))
    }
    try persist()
    let response = publicQuoteResponse(for: quote, viewerID: user.id)
    return .init(
      quoteID: id, upvotes: response.upvotes, downvotes: response.downvotes,
      viewerRating: response.viewerRating)
  }

  public func publicQuotes(
    language: String?, limit: Int?, accessToken: String? = nil, now: Date = .now
  ) throws -> PublicQuoteListResponse {
    guard
      language == nil
        || Set([
          "english", "spanish", "german", "afrikaans", "greek", "greeklish", "dutch", "danish", "norwegianBokmal", "norwegianNynorsk", "swedish", "hungarian", "czech", "slovak", "slovenian", "croatian", "serbian", "serbianLatin", "bulgarian", "romanian", "finnish", "estonian", "icelandic", "french", "italian", "portuguese",
          "simplifiedChinese",
          "traditionalChinese", "russian", "ukrainian", "ukrainianLatin", "japaneseHiragana", "japaneseKatakana", "japaneseRomaji",
          "korean", "turkish", "polish",
        ]).contains(language!)
    else { throw AuthStoreError.invalidQuoteSubmission }
    let viewerID = try accessToken.map { try authenticatedUser(for: $0, now: now).id }
    let resolvedLimit = min(max(limit ?? 50, 1), 100)
    let quotes: [PublicQuoteResponse] = state.quoteSubmissions
      .filter { $0.status == "approved" && (language == nil || $0.language == language) }
      .sorted { $0.submittedAt > $1.submittedAt }
      .prefix(resolvedLimit)
      .map { publicQuoteResponse(for: $0, viewerID: viewerID) }
    return .init(quotes: quotes)
  }

  private func publicQuoteResponse(for quote: StoredQuoteSubmission, viewerID: UUID?)
    -> PublicQuoteResponse
  {
    let ratings = state.quoteRatings.filter { $0.quoteID == quote.id }
    return .init(
      id: quote.id, language: quote.language, text: quote.text, attribution: quote.attribution,
      submittedAt: quote.submittedAt,
      upvotes: ratings.filter { $0.value == 1 }.count,
      downvotes: ratings.filter { $0.value == -1 }.count,
      viewerRating: viewerID.flatMap { viewer in
        ratings.first(where: { $0.userID == viewer })?.value
      }
    )
  }

  public func connections(accessToken: String, now: Date = .now) throws -> ConnectionsResponse {
    let current = try authenticatedUser(for: accessToken, now: now)
    let values = state.connections.compactMap { connection -> ConnectionResponse? in
      let otherID: UUID
      let relation: ConnectionRelation
      if connection.requesterID == current.id {
        otherID = connection.recipientID
        relation = connection.status == "accepted" ? .friend : .outgoingRequest
      } else if connection.recipientID == current.id {
        otherID = connection.requesterID
        relation = connection.status == "accepted" ? .friend : .incomingRequest
      } else {
        return nil
      }
      guard let other = state.users.first(where: { $0.id == otherID }) else { return nil }
      return .init(
        id: other.id, profile: publicProfile(for: other), relation: relation,
        updatedAt: connection.updatedAt)
    }
    return .init(connections: values.sorted { $0.updatedAt > $1.updatedAt })
  }

  private func publicProfile(for user: StoredUser) -> PublicProfileResponse {
    let results = state.results.filter { $0.userID == user.id }
    return publicProfile(for: user, results: results, activity: nil, streak: nil)
  }

  private func detailedPublicProfile(for user: StoredUser, now: Date) -> PublicProfileResponse {
    let results = state.results.filter { $0.userID == user.id }
    let shouldShowActivity = user.profileDetails.showActivity
    return publicProfile(
      for: user, results: results,
      activity: shouldShowActivity ? publicActivity(from: results, endingAt: now) : nil,
      streak: shouldShowActivity ? publicStreak(from: results, endingAt: now) : nil)
  }

  private func publicProfile(
    for user: StoredUser, results: [StoredResult], activity: PublicProfileActivityResponse?,
    streak: PublicProfileStreakResponse?
  ) -> PublicProfileResponse {
    return .init(
      id: user.id,
      displayName: user.displayName,
      joinedAt: user.createdAt,
      completedResultCount: results.count,
      startedTestCount: user.startedTestCount,
      totalTypingSeconds: totalTypingSeconds(from: results),
      bestWPM: results.map(\.wpm).max() ?? 0,
      highestConsistency: results.map(\.consistency).max() ?? 0,
      personalBests: publicPersonalBests(from: results),
      activity: activity,
      streak: streak,
      totalExperience: experience(for: user.id),
      profileDetails: user.profileDetails,
      discordAvatar: publicDiscordAvatar(for: user),
      selectedBadge: selectedPublicBadge(for: user)
    )
  }

  private func availablePublicBadges(for userID: UUID) -> [PublicProfileBadge] {
    let results = state.results.filter { $0.userID == userID }
    let accurateRunExists = results.contains {
      $0.accuracy >= 98 && $0.finishedAt.timeIntervalSince($0.startedAt) >= 15
    }
    let bestWPM = results.map(\.wpm).max() ?? 0
    let totalTypingSeconds = results.reduce(0.0) { partial, result in
      partial + max(0, result.finishedAt.timeIntervalSince(result.startedAt))
    }
    var badges: [PublicProfileBadge] = []
    if !results.isEmpty {
      badges.append(.init(id: "first-finish", title: "起步", systemImage: "flag.checkered"))
    }
    if accurateRunExists {
      badges.append(.init(id: "clear-key", title: "清晰按键", systemImage: "checkmark.seal"))
    }
    if bestWPM >= 80 {
      badges.append(.init(id: "swift-line", title: "迅捷一行", systemImage: "bolt"))
    }
    if totalTypingSeconds >= 15 * 60 {
      badges.append(.init(id: "steady-room", title: "稳定练习", systemImage: "timer"))
    }
    return badges
  }

  private func selectedPublicBadge(for user: StoredUser) -> PublicProfileBadge? {
    guard let selectedBadgeID = user.selectedBadgeID else { return nil }
    return availablePublicBadges(for: user.id).first { $0.id == selectedBadgeID }
  }

  private func publicDiscordAvatar(for user: StoredUser) -> PublicDiscordAvatarResponse? {
    guard user.profileDetails.showDiscordAvatar,
      let identity = state.oauthIdentities.first(where: {
        $0.userID == user.id && $0.provider == .discord
      }), let avatarHash = identity.avatarHash
    else { return nil }
    return .init(subject: identity.subject, avatarHash: avatarHash)
  }

  private func publicActivity(from results: [StoredResult], endingAt now: Date)
    -> PublicProfileActivityResponse?
  {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let lastDay = calendar.startOfDay(for: now)
    guard let firstDay = calendar.date(byAdding: .day, value: -364, to: lastDay) else { return nil }
    var testsByDays = Array(repeating: 0, count: 365)

    for result in results {
      let resultDay = calendar.startOfDay(for: result.finishedAt)
      guard resultDay >= firstDay, resultDay <= lastDay else { continue }
      let offset = calendar.dateComponents([.day], from: firstDay, to: resultDay).day ?? -1
      guard testsByDays.indices.contains(offset) else { continue }
      testsByDays[offset] += 1
    }

    guard testsByDays.contains(where: { $0 > 0 }) else { return nil }
    return .init(lastDay: lastDay, testsByDays: testsByDays)
  }

  private func totalTypingSeconds(from results: [StoredResult]) -> Double {
    results.reduce(0) { total, result in
      total + max(0, result.finishedAt.timeIntervalSince(result.startedAt))
    }
  }

  private func publicStreak(from results: [StoredResult], endingAt now: Date)
    -> PublicProfileStreakResponse?
  {
    guard !results.isEmpty else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let days = Set(results.map { calendar.startOfDay(for: $0.finishedAt) })
    let currentDay = calendar.startOfDay(for: now)
    var currentDays = 0
    var cursor = currentDay
    while days.contains(cursor) {
      currentDays += 1
      guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
      cursor = previousDay
    }

    let sortedDays = days.sorted()
    var longestDays = 0
    var runLength = 0
    var previousDay: Date?
    for day in sortedDays {
      if let previousDay,
        calendar.date(byAdding: .day, value: 1, to: previousDay) == day
      {
        runLength += 1
      } else {
        runLength = 1
      }
      longestDays = max(longestDays, runLength)
      previousDay = day
    }
    return .init(currentDays: currentDays, longestDays: longestDays)
  }

  private func publicPersonalBests(from results: [StoredResult]) -> [PublicProfileBestResponse] {
    let standardModes: [(mode: String, durationSeconds: Int?, wordLimit: Int?)] = [
      ("time", 15, nil), ("time", 30, nil), ("time", 60, nil), ("time", 120, nil),
      ("words", nil, 10), ("words", nil, 25), ("words", nil, 50), ("words", nil, 100),
    ]

    return standardModes.compactMap { standard in
      let candidates = results.filter {
        $0.mode == standard.mode
          && $0.durationSeconds == standard.durationSeconds
          && $0.wordLimit == standard.wordLimit
      }
      guard let best = candidates.max(by: { candidate, currentBest in
        candidate.wpm == currentBest.wpm
          ? candidate.finishedAt < currentBest.finishedAt
          : candidate.wpm < currentBest.wpm
      }) else { return nil }
      return .init(
        id: best.id, mode: best.mode, durationSeconds: best.durationSeconds,
        wordLimit: best.wordLimit, language: best.language, wpm: best.wpm,
        accuracy: best.accuracy, consistency: best.consistency, finishedAt: best.finishedAt)
    }
  }

  private func experience(for userID: UUID, since: Date? = nil, before: Date? = nil) -> Int {
    state.results
      .filter {
        $0.userID == userID
          && (since == nil || $0.finishedAt >= since!)
          && (before == nil || $0.finishedAt < before!)
      }
      .reduce(0) { total, record in
        total + TypebarExperiencePolicy.points(for: resultRequest(from: record))
      }
  }

  private func resultRequest(from record: StoredResult) -> ResultSubmissionRequest {
    .init(
      id: record.id, mode: record.mode, language: record.language,
      durationSeconds: record.durationSeconds, wordLimit: record.wordLimit, wpm: record.wpm,
      rawWpm: record.rawWpm, accuracy: record.accuracy, consistency: record.consistency,
      errorCount: record.errorCount,
      eventCount: record.eventCount, tags: record.tags, startedAt: record.startedAt,
      finishedAt: record.finishedAt)
  }

  private func resultSubmissionResponse(
    for request: ResultSubmissionRequest, userID: UUID, now: Date
  ) -> ResultSubmissionResponse {
    let isLeaderboardEligible = !state.users.first(where: { $0.id == userID })!.leaderboardOptedOut
    let weeklyEntries = experienceLeaderboardEntries(now: now)
    return .init(
      id: request.id,
      accepted: true,
      leaderboardEligible: isLeaderboardEligible,
      experienceGained: TypebarExperiencePolicy.points(for: request),
      totalExperience: experience(for: userID),
      weeklyExperienceRank: isLeaderboardEligible
        ? weeklyEntries.first(where: { $0.userID == userID })?.rank
        : nil
    )
  }

  private func isBlocked(between first: UUID, and second: UUID) -> Bool {
    (state.blockedUserIDs[first] ?? []).contains(second)
      || (state.blockedUserIDs[second] ?? []).contains(first)
  }

  private func canExchangeMessages(between first: UUID, and second: UUID) -> Bool {
    first != second && !isBlocked(between: first, and: second)
      && state.connections.contains {
        (($0.requesterID == first && $0.recipientID == second)
          || ($0.requesterID == second && $0.recipientID == first)) && $0.status == "accepted"
      }
  }

  private func directMessageResponse(for message: StoredDirectMessage) -> DirectMessageResponse {
    .init(
      id: message.id, senderID: message.senderID, recipientID: message.recipientID,
      body: message.body, createdAt: message.createdAt, readAt: message.readAt)
  }

  public func pushSync(_ request: SyncPushRequest, accessToken: String, now: Date = .now) throws
    -> SyncPushResponse
  {
    let user = try authenticatedUser(for: accessToken, now: now)
    var results: [SyncPushResult] = []

    for change in request.changes {
      guard !change.type.isEmpty, change.type.count <= 64, change.version >= 0 else {
        results.append(.init(id: change.id, status: .conflict, serverVersion: -1))
        continue
      }

      if let index = state.syncRecords.firstIndex(where: {
        $0.userID == user.id && $0.id == change.id
      }) {
        let existing = state.syncRecords[index]
        guard change.version > existing.version else {
          results.append(.init(id: change.id, status: .conflict, serverVersion: existing.version))
          continue
        }
        let record = makeSyncRecord(userID: user.id, change: change, now: now)
        state.syncRecords[index] = record
        results.append(.init(id: change.id, status: .accepted, serverVersion: record.version))
      } else {
        let record = makeSyncRecord(userID: user.id, change: change, now: now)
        state.syncRecords.append(record)
        results.append(.init(id: change.id, status: .accepted, serverVersion: record.version))
      }
    }
    try persist()
    return .init(results: results, nextCursor: state.nextSyncCursor)
  }

  public func pullSync(
    after cursor: Int, accessToken: String, limit: Int? = nil, now: Date = .now
  ) throws
    -> SyncPullResponse
  {
    let user = try authenticatedUser(for: accessToken, now: now)
    let records = state.syncRecords
      .filter { $0.userID == user.id && $0.cursor > cursor }
      .sorted { $0.cursor < $1.cursor }
    guard let limit else {
      return .init(
        changes: records.map { $0.response() }, nextCursor: state.nextSyncCursor, hasMore: false)
    }

    let pageSize = min(max(limit, 1), 250)
    let page = Array(records.prefix(pageSize))
    let hasMore = records.count > page.count
    // An unfinished page must resume at the last record actually delivered. Once the
    // user-scoped stream is exhausted, advancing to the current global cursor is safe:
    // any future record for this user receives a strictly higher cursor.
    let nextCursor: Int
    if hasMore, let last = page.last {
      nextCursor = last.cursor
    } else {
      nextCursor = state.nextSyncCursor
    }
    return .init(
      changes: page.map { $0.response() }, nextCursor: nextCursor, hasMore: hasMore)
  }

  public func submitResult(
    _ request: ResultSubmissionRequest, credential: ResultServiceCredential, now: Date = .now
  ) throws -> ResultSubmissionResponse {
    let user = try authenticatedUser(for: credential, now: now)
    try validate(result: request, now: now)
    let tags = try validatedResultTags(request.tags)
    if state.results.contains(where: { $0.userID == user.id && $0.id == request.id }) {
      return resultSubmissionResponse(for: request, userID: user.id, now: now)
    }
    state.results.append(
      .init(
        id: request.id, userID: user.id, mode: request.mode, language: request.language,
        durationSeconds: request.durationSeconds, wordLimit: request.wordLimit,
        wpm: request.wpm, rawWpm: request.rawWpm, accuracy: request.accuracy,
        consistency: request.consistency, errorCount: request.errorCount, eventCount: request.eventCount,
        tags: tags,
        startedAt: request.startedAt, finishedAt: request.finishedAt
      ))
    guard let userIndex = state.users.firstIndex(where: { $0.id == user.id }) else {
      throw AuthStoreError.invalidAccessToken
    }
    state.users[userIndex].startedTestCount += request.restartCount + 1
    try persist()
    return resultSubmissionResponse(for: request, userID: user.id, now: now)
  }

  public func submitResult(
    _ request: ResultSubmissionRequest, accessToken: String, now: Date = .now
  ) throws -> ResultSubmissionResponse {
    try submitResult(request, credential: .accessToken(accessToken), now: now)
  }

  /// Removes only the authenticated account's submitted results after a fresh
  /// password check or one-time reauthentication. Local app history and every
  /// other account's records remain outside this operation's scope.
  public func deleteResults(
    _ request: DeleteResultsRequest, accessToken: String, reauthenticationToken: String? = nil,
    now: Date = .now
  ) throws -> ResultDeletionResponse {
    let currentUser = try authenticatedUser(for: accessToken, now: now)
    guard let userIndex = state.users.firstIndex(where: { $0.id == currentUser.id }) else {
      throw AuthStoreError.invalidAccessToken
    }
    let user = state.users[userIndex]
    if let currentPassword = request.currentPassword {
      guard let passwordHash = user.passwordHash,
        try Bcrypt.verify(currentPassword, created: passwordHash)
      else { throw AuthStoreError.invalidCredentials }
    } else {
      guard let reauthenticationToken else { throw AuthStoreError.invalidReauthenticationToken }
      try consumeReauthenticationToken(reauthenticationToken, for: user.id, now: now)
    }
    let countBeforeDeletion = state.results.count
    state.results.removeAll { $0.userID == user.id }
    state.users[userIndex].startedTestCount = 0
    let removedCount = countBeforeDeletion - state.results.count
    try persist()
    return .init(deleted: true, removedCount: removedCount)
  }

  public func updateResultTags(
    id: UUID, request: UpdateResultTagsRequest, accessToken: String, now: Date = .now
  ) throws -> AccountResultResponse {
    let user = try authenticatedUser(for: accessToken, now: now)
    let tags = try validatedResultTags(request.tags)
    guard let index = state.results.firstIndex(where: { $0.id == id && $0.userID == user.id }) else {
      throw AuthStoreError.resultNotFound
    }
    state.results[index].tags = tags
    try persist()
    return state.results[index].response()
  }

  public func results(
    _ query: ResultListQuery, credential: ResultServiceCredential, now: Date = .now
  ) throws -> ResultListResponse {
    let user = try authenticatedUser(for: credential, now: now)
    let offset = query.offset ?? 0
    let limit = query.limit ?? 50
    guard offset >= 0, (0...1_000).contains(limit),
      query.finishedOnOrAfter.map(\.isFinite) ?? true
    else { throw AuthStoreError.invalidResultQuery }
    let cutoff = query.finishedOnOrAfter.map(Date.init(timeIntervalSince1970:))
    let records = state.results
      .filter { record in
        record.userID == user.id && cutoff.map { record.finishedAt >= $0 } != false
      }
      .sorted {
        $0.finishedAt == $1.finishedAt
          ? $0.id.uuidString > $1.id.uuidString
          : $0.finishedAt > $1.finishedAt
      }
    return .init(
      results: Array(records.dropFirst(offset).prefix(limit)).map { $0.response() },
      total: records.count)
  }

  public func result(
    id: UUID, credential: ResultServiceCredential, now: Date = .now
  ) throws -> AccountResultResponse {
    let user = try authenticatedUser(for: credential, now: now)
    guard let record = state.results.first(where: { $0.id == id && $0.userID == user.id }) else {
      throw AuthStoreError.resultNotFound
    }
    return record.response()
  }

  public func leaderboard(_ query: LeaderboardQuery, now: Date = .now) throws -> LeaderboardResponse
  {
    let entries = try leaderboardEntries(query, eligibleUserIDs: nil, now: now)
    return .init(entries: Array(entries.prefix(leaderboardLimit(query))))
  }

  public func leaderboardRank(
    _ query: LeaderboardQuery, accessToken: String, now: Date = .now
  ) throws -> LeaderboardRankResponse {
    let user = try authenticatedUser(for: accessToken, now: now)
    return .init(
      entry: try leaderboardEntries(query, eligibleUserIDs: nil, now: now)
        .first(where: { $0.userID == user.id }))
  }

  public func friendLeaderboard(_ query: LeaderboardQuery, accessToken: String, now: Date = .now)
    throws -> LeaderboardResponse
  {
    let current = try authenticatedUser(for: accessToken, now: now)
    let entries = try leaderboardEntries(
      query, eligibleUserIDs: acceptedFriendIDs(for: current.id), now: now
    )
    return .init(entries: Array(entries.prefix(leaderboardLimit(query))))
  }

  public func friendLeaderboardRank(
    _ query: LeaderboardQuery, accessToken: String, now: Date = .now
  ) throws -> LeaderboardRankResponse {
    let current = try authenticatedUser(for: accessToken, now: now)
    return .init(
      entry: try leaderboardEntries(
        query, eligibleUserIDs: acceptedFriendIDs(for: current.id), now: now
      ).first(where: { $0.userID == current.id }))
  }

  public func experienceLeaderboard(
    period: String? = nil, eligibleUserIDs: Set<UUID>? = nil, now: Date = .now
  ) throws -> ExperienceLeaderboardResponse
  {
    let resolvedPeriod = try experienceLeaderboardPeriod(period)
    let entries = experienceLeaderboardEntries(
      eligibleUserIDs: eligibleUserIDs, period: resolvedPeriod, now: now)
    return .init(entries: Array(entries.prefix(100)), period: resolvedPeriod.rawValue)
  }

  public func experienceLeaderboardRank(
    period: String? = nil, accessToken: String, now: Date = .now
  ) throws -> ExperienceLeaderboardRankResponse {
    let user = try authenticatedUser(for: accessToken, now: now)
    let resolvedPeriod = try experienceLeaderboardPeriod(period)
    return .init(
      entry: experienceLeaderboardEntries(period: resolvedPeriod, now: now)
        .first(where: { $0.userID == user.id }),
      period: resolvedPeriod.rawValue)
  }

  public func friendExperienceLeaderboard(
    period: String? = nil, accessToken: String, now: Date = .now
  ) throws
    -> ExperienceLeaderboardResponse
  {
    let current = try authenticatedUser(for: accessToken, now: now)
    return try experienceLeaderboard(
      period: period, eligibleUserIDs: acceptedFriendIDs(for: current.id), now: now)
  }

  public func friendExperienceLeaderboardRank(
    period: String? = nil, accessToken: String, now: Date = .now
  ) throws -> ExperienceLeaderboardRankResponse {
    let current = try authenticatedUser(for: accessToken, now: now)
    let resolvedPeriod = try experienceLeaderboardPeriod(period)
    return .init(
      entry: experienceLeaderboardEntries(
        eligibleUserIDs: acceptedFriendIDs(for: current.id), period: resolvedPeriod, now: now
      ).first(where: { $0.userID == current.id }),
      period: resolvedPeriod.rawValue)
  }

  private func acceptedFriendIDs(for userID: UUID) -> Set<UUID> {
    state.connections.reduce(into: Set([userID])) { ids, connection in
      guard connection.status == "accepted" else { return }
      if connection.requesterID == userID { ids.insert(connection.recipientID) }
      if connection.recipientID == userID { ids.insert(connection.requesterID) }
    }
  }

  private enum ExperienceLeaderboardPeriod: String {
    case week
    case lastWeek
  }

  private func experienceLeaderboardPeriod(_ rawValue: String?) throws -> ExperienceLeaderboardPeriod {
    guard let period = ExperienceLeaderboardPeriod(rawValue: rawValue ?? ExperienceLeaderboardPeriod.week.rawValue)
    else { throw ResultStoreError.invalidResult }
    return period
  }

  private func experienceLeaderboardEntries(
    eligibleUserIDs: Set<UUID>? = nil, period: ExperienceLeaderboardPeriod = .week, now: Date
  ) -> [ExperienceLeaderboardEntry] {
    let calendar = Calendar(identifier: .iso8601)
    let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
    let lowerBound: Date
    let upperBound: Date?
    switch period {
    case .week:
      lowerBound = currentWeekStart
      upperBound = nil
    case .lastWeek:
      lowerBound = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart)
        ?? currentWeekStart
      upperBound = currentWeekStart
    }
    return state.users.compactMap { user -> (StoredUser, Int)? in
      guard !user.leaderboardOptedOut,
        eligibleUserIDs == nil || eligibleUserIDs!.contains(user.id)
      else { return nil }
      let weeklyPoints = experience(for: user.id, since: lowerBound, before: upperBound)
      return weeklyPoints > 0 ? (user, weeklyPoints) : nil
    }
    .sorted {
      if $0.1 != $1.1 { return $0.1 > $1.1 }
      return $0.0.displayName.localizedCaseInsensitiveCompare($1.0.displayName) == .orderedAscending
    }
    .enumerated()
    .map { offset, value in
      ExperienceLeaderboardEntry(
        id: value.0.id, rank: offset + 1, userID: value.0.id, displayName: value.0.displayName,
        totalExperience: value.1, selectedBadge: selectedPublicBadge(for: value.0),
        discordAvatar: publicDiscordAvatar(for: value.0))
    }
  }

  private func leaderboardLimit(_ query: LeaderboardQuery) -> Int {
    min(max(query.limit ?? 25, 1), 100)
  }

  private func leaderboardEntries(
    _ query: LeaderboardQuery, eligibleUserIDs: Set<UUID>?, now: Date
  ) throws -> [LeaderboardEntry] {
    let modes = Set(["time", "words", "quote", "zen", "custom"])
    let languages = Set([
      "english", "spanish", "german", "afrikaans", "greek", "greeklish", "dutch", "danish", "norwegianBokmal", "norwegianNynorsk", "swedish", "hungarian", "czech", "slovak", "slovenian", "croatian", "serbian", "serbianLatin", "bulgarian", "romanian", "finnish", "estonian", "icelandic", "french", "italian", "portuguese",
      "simplifiedChinese",
      "traditionalChinese", "russian", "ukrainian", "ukrainianLatin", "japaneseHiragana", "japaneseKatakana", "japaneseRomaji",
      "korean", "turkish", "polish",
      "mixedEnglishChinese", "mixedLanguages",
    ])
    let periods = Set(["all", "day", "yesterday", "week"])
    if let mode = query.mode, !modes.contains(mode) { throw ResultStoreError.invalidResult }
    if let language = query.language, !languages.contains(language) {
      throw ResultStoreError.invalidResult
    }
    let period = query.period ?? "all"
    guard periods.contains(period) else { throw ResultStoreError.invalidResult }
    let calendar = Calendar.current
    let todayStart = calendar.startOfDay(for: now)
    let lowerBound: Date?
    let upperBound: Date?
    switch period {
    case "day":
      lowerBound = todayStart
      upperBound = nil
    case "yesterday":
      lowerBound = calendar.date(byAdding: .day, value: -1, to: todayStart)
      upperBound = todayStart
    case "week":
      lowerBound = Calendar(identifier: .iso8601).dateInterval(of: .weekOfYear, for: now)?.start
      upperBound = nil
    default:
      lowerBound = nil
      upperBound = nil
    }
    let users = Dictionary(uniqueKeysWithValues: state.users.map { ($0.id, $0) })
    let records = state.results.filter { result in
      (eligibleUserIDs == nil || eligibleUserIDs!.contains(result.userID))
        && users[result.userID]?.leaderboardOptedOut == false
        && (query.mode == nil || result.mode == query.mode)
        && (query.language == nil || result.language == query.language)
        && (lowerBound == nil || result.finishedAt >= lowerBound!)
        && (upperBound == nil || result.finishedAt < upperBound!)
    }.sorted {
      if $0.wpm != $1.wpm { return $0.wpm > $1.wpm }
      if $0.accuracy != $1.accuracy { return $0.accuracy > $1.accuracy }
      return $0.finishedAt > $1.finishedAt
    }
    var representedUsers = Set<UUID>()
    let bestRecordPerUser = records.filter { representedUsers.insert($0.userID).inserted }
    return bestRecordPerUser.enumerated().compactMap {
      offset, result -> LeaderboardEntry? in
      guard let user = users[result.userID] else { return nil }
      return .init(
        id: result.id, rank: offset + 1, userID: user.id, displayName: user.displayName,
        mode: result.mode, language: result.language, wpm: result.wpm,
        accuracy: result.accuracy, consistency: result.consistency, finishedAt: result.finishedAt,
        selectedBadge: selectedPublicBadge(for: user), discordAvatar: publicDiscordAvatar(for: user))
    }
  }

  private func makeSession(for user: StoredUser, now: Date) -> AuthSessionResponse {
    let token = Self.makeAccessToken()
    let expiry = now.addingTimeInterval(60 * 60 * 24 * 30)
    state.sessions.append(
      .init(tokenHash: Self.tokenHash(token), userID: user.id, expiresAt: expiry))
    return .init(
      user: userResponse(for: user),
      accessToken: token,
      expiresAt: expiry
    )
  }

  private func makeReauthenticationToken(
    for userID: UUID, now: Date
  ) throws -> ReauthenticationResponse {
    state.reauthenticationTokens.removeAll { $0.expiresAt <= now }
    let token = Self.makeAccessToken()
    state.reauthenticationTokens.append(
      .init(
        tokenHash: Self.tokenHash(token), userID: userID,
        expiresAt: now.addingTimeInterval(5 * 60)))
    try persist()
    return .init(reauthenticationToken: token)
  }

  private func consumeReauthenticationToken(
    _ token: String, for userID: UUID, now: Date
  ) throws {
    let originalCount = state.reauthenticationTokens.count
    state.reauthenticationTokens.removeAll { $0.expiresAt <= now }
    if state.reauthenticationTokens.count != originalCount { try persist() }
    let tokenHash = Self.tokenHash(token)
    guard let index = state.reauthenticationTokens.firstIndex(where: {
      $0.userID == userID && $0.tokenHash == tokenHash
    }) else { throw AuthStoreError.invalidReauthenticationToken }
    state.reauthenticationTokens.remove(at: index)
    try persist()
  }

  private func userResponse(for userID: UUID) throws -> AuthUserResponse {
    guard let user = state.users.first(where: { $0.id == userID }) else {
      throw AuthStoreError.invalidAccessToken
    }
    return userResponse(for: user)
  }

  private func userResponse(for user: StoredUser) -> AuthUserResponse {
    let availableBadges = availablePublicBadges(for: user.id)
    let selectedBadgeID = selectedPublicBadge(for: user)?.id
    return .init(
      id: user.id, email: user.email, emailVerified: user.emailVerified, displayName: user.displayName,
      totalExperience: experience(for: user.id), leaderboardOptedOut: user.leaderboardOptedOut,
      profileDetails: user.profileDetails,
      authenticationMethods: authenticationMethods(for: user.id), availableBadges: availableBadges,
      selectedBadgeID: selectedBadgeID)
  }

  private func authenticationMethods(for userID: UUID) -> [AuthenticationMethod] {
    guard let user = state.users.first(where: { $0.id == userID }) else { return [] }
    var available = Set<AuthenticationMethod>()
    if user.passwordHash != nil { available.insert(.password) }
    for identity in state.oauthIdentities where identity.userID == userID {
      switch identity.provider {
      case .github: available.insert(.github)
      case .google: available.insert(.google)
      case .discord: available.insert(.discord)
      }
    }
    return AuthenticationMethod.allCases.filter { available.contains($0) }
  }

  private func makeSyncRecord(userID: UUID, change: SyncChangeRequest, now: Date)
    -> StoredSyncRecord
  {
    state.nextSyncCursor += 1
    return .init(
      userID: userID,
      id: change.id,
      type: change.type,
      version: change.version,
      payload: change.payload,
      isDeleted: change.isDeleted,
      cursor: state.nextSyncCursor,
      updatedAt: now
    )
  }

  private func authenticatedUser(forDeveloperAccessKey accessKey: String, now: Date) throws
    -> AuthUserResponse
  {
    guard accessKey.hasPrefix("tbak_") else { throw AuthStoreError.invalidDeveloperAccessKey }
    let hash = Self.tokenHash(accessKey)
    guard let index = state.developerAccessKeys.firstIndex(where: { $0.tokenHash == hash }) else {
      throw AuthStoreError.invalidDeveloperAccessKey
    }
    let key = state.developerAccessKeys[index]
    guard key.enabled else { throw AuthStoreError.inactiveDeveloperAccessKey }
    guard let user = state.users.first(where: { $0.id == key.userID }) else {
      throw AuthStoreError.invalidDeveloperAccessKey
    }
    state.developerAccessKeys[index] = StoredDeveloperAccessKey(
      id: key.id, userID: key.userID, tokenHash: key.tokenHash, name: key.name,
      enabled: key.enabled, createdAt: key.createdAt, modifiedAt: key.modifiedAt, lastUsedAt: now)
    try persist()
    return userResponse(for: user)
  }

  private func authenticatedUser(for credential: ResultServiceCredential, now: Date) throws
    -> AuthUserResponse
  {
    switch credential {
    case .accessToken(let accessToken):
      try authenticatedUser(for: accessToken, now: now)
    case .developerAccessKey(let accessKey):
      try authenticatedUser(forDeveloperAccessKey: accessKey, now: now)
    }
  }

  private func persist() throws {
    guard let fileURL else { return }
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder.server.encode(state).write(to: fileURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
  }

  private func validatedEmail(_ value: String) throws -> String {
    guard let email = normalizedEmail(value) else { throw AuthStoreError.invalidEmail }
    return email
  }

  private func validatedOAuthIdentity(_ identity: OAuthProviderIdentity) throws -> (String, String) {
    let subject = identity.subject.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !subject.isEmpty, subject.count <= 255 else { throw AuthStoreError.invalidOAuthIdentity }
    return (subject, try validatedEmail(identity.email))
  }

  private func normalizedEmail(_ value: String) -> String? {
    let email = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let parts = email.split(separator: "@", omittingEmptySubsequences: false)
    guard email.count <= 254, parts.count == 2, !parts[0].isEmpty, parts[1].contains(".") else {
      return nil
    }
    return email
  }

  private func validatedDisplayName(_ value: String) throws -> String {
    let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (2...32).contains(name.count) else { throw AuthStoreError.invalidDisplayName }
    return name
  }

  private func validatedDeveloperAccessKeyName(_ value: String) throws -> String {
    let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...20).contains(name.count), let first = name.first,
      first.isASCII && (first.isLetter || first.isNumber),
      name.allSatisfy({ character in
        character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
      })
    else { throw AuthStoreError.invalidDeveloperAccessKeyName }
    return name
  }

  private func validatedResultTags(_ values: [String]) throws -> [String] {
    guard values.count <= 5 else { throw AuthStoreError.invalidResultTags }
    var seen = Set<String>()
    var tags: [String] = []
    for value in values {
      let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !tag.isEmpty, tag.count <= 24 else { throw AuthStoreError.invalidResultTags }
      let key = tag.folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX"))
      guard seen.insert(key).inserted else { throw AuthStoreError.invalidResultTags }
      tags.append(tag)
    }
    return tags
  }

  private func validatedProfileDetails(_ value: ProfileDetails) throws -> ProfileDetails {
    let bio = value.bio.trimmingCharacters(in: .whitespacesAndNewlines)
    let keyboard = value.keyboard.trimmingCharacters(in: .whitespacesAndNewlines)
    guard bio.count <= 250, keyboard.count <= 75 else { throw AuthStoreError.invalidProfileDetails }
    let github = try validatedProfileHandle(value.github, maximumLength: 39)
    let socialHandle = try validatedProfileHandle(value.socialHandle, maximumLength: 15)
    let websiteURL = try validatedProfileWebsite(value.websiteURL)
    return .init(
      bio: bio, keyboard: keyboard, github: github, socialHandle: socialHandle,
      websiteURL: websiteURL, showActivity: value.showActivity,
      showDiscordAvatar: value.showDiscordAvatar)
  }

  private func validatedSelectedBadgeID(_ requested: String?, existing: String?, userID: UUID) throws
    -> String?
  {
    guard let requested else { return existing }
    let selectedBadgeID = requested.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !selectedBadgeID.isEmpty else { return nil }
    guard availablePublicBadges(for: userID).contains(where: { $0.id == selectedBadgeID }) else {
      throw AuthStoreError.invalidProfileDetails
    }
    return selectedBadgeID
  }

  private static func discordAvatarHash(from identity: OAuthProviderIdentity) -> String? {
    guard identity.provider == .discord,
      let rawHash = identity.avatarHash?.trimmingCharacters(in: .whitespacesAndNewlines)
    else { return nil }
    let normalized = rawHash.lowercased()
    let hex = normalized.hasPrefix("a_") ? String(normalized.dropFirst(2)) : normalized
    guard hex.count == 32, hex.allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
    return normalized
  }

  private func validatedProfileHandle(_ value: String, maximumLength: Int) throws -> String {
    let handle = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard handle.count <= maximumLength else { throw AuthStoreError.invalidProfileDetails }
    guard handle.allSatisfy({ character in
      character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
    }) else { throw AuthStoreError.invalidProfileDetails }
    return handle
  }

  private func validatedProfileWebsite(_ value: String) throws -> String {
    let website = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard website.count <= 200 else { throw AuthStoreError.invalidProfileDetails }
    guard !website.isEmpty else { return "" }
    guard let components = URLComponents(string: website), components.scheme == "https",
      let host = components.host, !host.isEmpty
    else { throw AuthStoreError.invalidProfileDetails }
    return website
  }

  private func validatedPassword(_ value: String) throws {
    guard (12...72).contains(value.utf8.count) else { throw AuthStoreError.weakPassword }
  }

  private func validate(result: ResultSubmissionRequest, now: Date) throws {
    guard Set(["time", "words", "quote", "zen", "custom"]).contains(result.mode),
      Set([
        "english", "spanish", "german", "afrikaans", "greek", "greeklish", "dutch", "danish", "norwegianBokmal", "norwegianNynorsk", "swedish", "hungarian", "czech", "slovak", "slovenian", "croatian", "serbian", "serbianLatin", "bulgarian", "romanian", "finnish", "estonian", "icelandic", "french", "italian", "portuguese",
        "simplifiedChinese",
        "traditionalChinese", "russian", "ukrainian", "ukrainianLatin", "japaneseHiragana", "japaneseKatakana", "japaneseRomaji",
        "korean", "turkish", "polish",
        "mixedEnglishChinese", "mixedLanguages",
      ]).contains(result.language),
      (0...400).contains(result.wpm), (0...500).contains(result.rawWpm),
      (0...100).contains(result.accuracy), (0...100).contains(result.consistency),
      result.errorCount >= 0, result.eventCount >= 0,
      (0...1_000).contains(result.restartCount),
      result.rawWpm >= result.wpm, result.errorCount <= result.eventCount,
      result.startedAt <= result.finishedAt,
      result.finishedAt <= now.addingTimeInterval(60 * 5),
      result.finishedAt >= now.addingTimeInterval(-60 * 60 * 24 * 365 * 2)
    else { throw ResultStoreError.invalidResult }
    let timeIsValid = result.durationSeconds.map { (5...3600).contains($0) } ?? false
    let wordsAreValid = result.wordLimit.map { (1...1000).contains($0) } ?? false
    guard timeIsValid || wordsAreValid || ["quote", "zen", "custom"].contains(result.mode) else {
      throw ResultStoreError.invalidResult
    }

    let elapsed = result.finishedAt.timeIntervalSince(result.startedAt)
    guard (1...3600).contains(elapsed) else { throw ResultStoreError.invalidResult }
    if result.mode == "time", let configuredDuration = result.durationSeconds {
      guard abs(elapsed - Double(configuredDuration)) <= 1 else {
        throw ResultStoreError.invalidResult
      }
    }

    let correctCharacters = result.eventCount - result.errorCount
    let expectedAccuracy =
      result.eventCount == 0
      ? 100
      : Int((Double(correctCharacters) / Double(result.eventCount) * 100).rounded())
    let expectedWPM = Int((Double(correctCharacters) / 5 / elapsed * 60).rounded())
    let expectedRawWPM = Int((Double(result.eventCount) / 5 / elapsed * 60).rounded())
    guard result.accuracy == expectedAccuracy,
      abs(result.wpm - expectedWPM) <= 1,
      abs(result.rawWpm - expectedRawWPM) <= 1
    else { throw ResultStoreError.invalidResult }
  }

  private static func makeAccessToken() -> String {
    var generator = SystemRandomNumberGenerator()
    let bytes = (0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) }
    return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }

  private static func tokenHash(_ token: String) -> String {
    SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private static func codeChallenge(for verifier: String) -> String {
    Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }
}

public enum ResultStoreError: Error, Equatable {
  case invalidResult
}

extension JSONEncoder {
  fileprivate static var server: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }
}

extension JSONDecoder {
  fileprivate static var server: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
