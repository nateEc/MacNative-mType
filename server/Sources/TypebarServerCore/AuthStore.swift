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

public struct ChangeEmailRequest: Content, Equatable {
  public let currentPassword: String
  public let newEmail: String
}

public struct DeleteAccountRequest: Content, Equatable {
  public let currentPassword: String
}

public struct AccountDeletionResponse: Content, Equatable {
  public let deleted: Bool
}

public struct UpdateProfileRequest: Content, Equatable {
  public let displayName: String
  /// Omitted by older clients, which preserves the existing account choice.
  public let leaderboardOptedOut: Bool?

  public init(displayName: String, leaderboardOptedOut: Bool? = nil) {
    self.displayName = displayName
    self.leaderboardOptedOut = leaderboardOptedOut
  }
}

public struct AuthSessionResponse: Content, Equatable {
  public let user: AuthUserResponse
  public let accessToken: String
  public let expiresAt: Date
}

public struct AuthUserResponse: Content, Equatable {
  public let id: UUID
  public let email: String
  public let displayName: String
  public let totalExperience: Int
  public let leaderboardOptedOut: Bool
}

public struct PublicProfileResponse: Content, Equatable {
  public let id: UUID
  public let displayName: String
  public let joinedAt: Date
  public let completedResultCount: Int
  public let bestWPM: Int
  public let highestConsistency: Double
  public let personalBests: [PublicProfileBestResponse]
  public let activity: PublicProfileActivityResponse?
  public let totalExperience: Int
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
}

public actor AuthStore {
  private struct PersistedState: Codable {
    var users: [StoredUser] = []
    var sessions: [StoredSession] = []
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
    var nextSyncCursor = 0

    private enum CodingKeys: String, CodingKey {
      case users, sessions, syncRecords, results, connections, blockedUserIDs, quoteSubmissions,
        quoteRatings, notifications, profileReports, quoteReports, directMessages, nextSyncCursor
    }

    init() {}

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      users = try values.decodeIfPresent([StoredUser].self, forKey: .users) ?? []
      sessions = try values.decodeIfPresent([StoredSession].self, forKey: .sessions) ?? []
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
      nextSyncCursor = try values.decodeIfPresent(Int.self, forKey: .nextSyncCursor) ?? 0
    }
  }

  private struct StoredUser: Codable {
    let id: UUID
    let email: String
    let displayName: String
    let passwordHash: String
    let createdAt: Date
    let leaderboardOptedOut: Bool

    private enum CodingKeys: String, CodingKey {
      case id, email, displayName, passwordHash, createdAt, leaderboardOptedOut
    }

    init(
      id: UUID, email: String, displayName: String, passwordHash: String, createdAt: Date,
      leaderboardOptedOut: Bool = false
    ) {
      self.id = id
      self.email = email
      self.displayName = displayName
      self.passwordHash = passwordHash
      self.createdAt = createdAt
      self.leaderboardOptedOut = leaderboardOptedOut
    }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      id = try values.decode(UUID.self, forKey: .id)
      email = try values.decode(String.self, forKey: .email)
      displayName = try values.decode(String.self, forKey: .displayName)
      passwordHash = try values.decode(String.self, forKey: .passwordHash)
      createdAt = try values.decode(Date.self, forKey: .createdAt)
      leaderboardOptedOut = try values.decodeIfPresent(Bool.self, forKey: .leaderboardOptedOut) ?? false
    }
  }

  private struct StoredSession: Codable {
    let tokenHash: String
    let userID: UUID
    let expiresAt: Date
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
    let startedAt: Date
    let finishedAt: Date

    private enum CodingKeys: String, CodingKey {
      case id, userID, mode, language, durationSeconds, wordLimit, wpm, rawWpm, accuracy, consistency,
        errorCount, eventCount, startedAt, finishedAt
    }

    init(
      id: UUID, userID: UUID, mode: String, language: String, durationSeconds: Int?,
      wordLimit: Int?, wpm: Int, rawWpm: Int, accuracy: Int, consistency: Double,
      errorCount: Int, eventCount: Int,
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
      finishedAt = try values.decode(Date.self, forKey: .finishedAt)
      let legacyDuration =
        durationSeconds.map(TimeInterval.init)
        ?? max(1, Double(eventCount) / Double(max(rawWpm, 1) * 5) * 60)
      startedAt =
        try values.decodeIfPresent(Date.self, forKey: .startedAt)
        ?? finishedAt.addingTimeInterval(-legacyDuration)
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
    guard let user = state.users.first(where: { $0.email == email }) else {
      throw AuthStoreError.invalidCredentials
    }
    guard try Bcrypt.verify(request.password, created: user.passwordHash) else {
      throw AuthStoreError.invalidCredentials
    }

    state.sessions.removeAll { $0.expiresAt <= now }
    let response = makeSession(for: user, now: now)
    try persist()
    return response
  }

  public func authenticatedUser(for accessToken: String, now: Date = .now) throws
    -> AuthUserResponse
  {
    let hash = Self.tokenHash(accessToken)
    guard let session = state.sessions.first(where: { $0.tokenHash == hash && $0.expiresAt > now }),
      let user = state.users.first(where: { $0.id == session.userID })
    else { throw AuthStoreError.invalidAccessToken }
    return .init(
      id: user.id, email: user.email, displayName: user.displayName,
      totalExperience: experience(for: user.id), leaderboardOptedOut: user.leaderboardOptedOut)
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
    guard try Bcrypt.verify(request.currentPassword, created: user.passwordHash) else {
      throw AuthStoreError.invalidCredentials
    }
    try validatedPassword(request.newPassword)

    let updatedUser = StoredUser(
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      passwordHash: try Bcrypt.hash(request.newPassword, cost: bcryptCost),
      createdAt: user.createdAt,
      leaderboardOptedOut: user.leaderboardOptedOut
    )
    state.users[index] = updatedUser
    state.sessions.removeAll { $0.userID == updatedUser.id }
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
    guard try Bcrypt.verify(request.currentPassword, created: user.passwordHash) else {
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
      leaderboardOptedOut: user.leaderboardOptedOut
    )
    state.users[index] = updatedUser
    state.sessions.removeAll { $0.userID == updatedUser.id }
    let response = makeSession(for: updatedUser, now: now)
    try persist()
    return response
  }

  /// Deletes the authenticated account and every record owned by it. A current
  /// password is required so a leaked, still-valid access token cannot erase it.
  public func deleteAccount(_ request: DeleteAccountRequest, accessToken: String, now: Date = .now)
    throws
  {
    let currentUser = try authenticatedUser(for: accessToken, now: now)
    guard let index = state.users.firstIndex(where: { $0.id == currentUser.id }) else {
      throw AuthStoreError.invalidAccessToken
    }
    guard try Bcrypt.verify(request.currentPassword, created: state.users[index].passwordHash)
    else { throw AuthStoreError.invalidCredentials }
    let userID = currentUser.id
    let removedQuoteIDs = Set(state.quoteSubmissions.filter { $0.userID == userID }.map(\.id))

    state.users.remove(at: index)
    state.sessions.removeAll { $0.userID == userID }
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
    let displayName = try validatedDisplayName(request.displayName)
    guard let index = state.users.firstIndex(where: { $0.id == currentUser.id }) else {
      throw AuthStoreError.invalidAccessToken
    }
    let user = state.users[index]
    let updatedUser = StoredUser(
      id: user.id, email: user.email, displayName: displayName, passwordHash: user.passwordHash,
      createdAt: user.createdAt,
      leaderboardOptedOut: request.leaderboardOptedOut ?? user.leaderboardOptedOut)
    state.users[index] = updatedUser
    try persist()
    return .init(
      id: updatedUser.id, email: updatedUser.email, displayName: updatedUser.displayName,
      totalExperience: experience(for: updatedUser.id),
      leaderboardOptedOut: updatedUser.leaderboardOptedOut)
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
      Set(["english", "spanish", "german", "french", "italian", "portuguese", "simplifiedChinese"])
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
          "english", "spanish", "german", "french", "italian", "portuguese", "simplifiedChinese",
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
    return publicProfile(for: user, results: results, activity: nil)
  }

  private func detailedPublicProfile(for user: StoredUser, now: Date) -> PublicProfileResponse {
    let results = state.results.filter { $0.userID == user.id }
    return publicProfile(
      for: user, results: results, activity: publicActivity(from: results, endingAt: now))
  }

  private func publicProfile(
    for user: StoredUser, results: [StoredResult], activity: PublicProfileActivityResponse?
  ) -> PublicProfileResponse {
    return .init(
      id: user.id,
      displayName: user.displayName,
      joinedAt: user.createdAt,
      completedResultCount: results.count,
      bestWPM: results.map(\.wpm).max() ?? 0,
      highestConsistency: results.map(\.consistency).max() ?? 0,
      personalBests: publicPersonalBests(from: results),
      activity: activity,
      totalExperience: experience(for: user.id)
    )
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

  private func experience(for userID: UUID, since: Date? = nil) -> Int {
    state.results
      .filter { $0.userID == userID && (since == nil || $0.finishedAt >= since!) }
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
      eventCount: record.eventCount, startedAt: record.startedAt, finishedAt: record.finishedAt)
  }

  private func resultSubmissionResponse(
    for request: ResultSubmissionRequest, userID: UUID, now: Date
  ) -> ResultSubmissionResponse {
    let isLeaderboardEligible = !state.users.first(where: { $0.id == userID })!.leaderboardOptedOut
    let weeklyEntries = experienceLeaderboard(now: now).entries
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
    _ request: ResultSubmissionRequest, accessToken: String, now: Date = .now
  ) throws -> ResultSubmissionResponse {
    let user = try authenticatedUser(for: accessToken, now: now)
    try validate(result: request, now: now)
    if state.results.contains(where: { $0.userID == user.id && $0.id == request.id }) {
      return resultSubmissionResponse(for: request, userID: user.id, now: now)
    }
    state.results.append(
      .init(
        id: request.id, userID: user.id, mode: request.mode, language: request.language,
        durationSeconds: request.durationSeconds, wordLimit: request.wordLimit,
        wpm: request.wpm, rawWpm: request.rawWpm, accuracy: request.accuracy,
        consistency: request.consistency, errorCount: request.errorCount, eventCount: request.eventCount,
        startedAt: request.startedAt, finishedAt: request.finishedAt
      ))
    try persist()
    return resultSubmissionResponse(for: request, userID: user.id, now: now)
  }

  public func leaderboard(_ query: LeaderboardQuery, now: Date = .now) throws -> LeaderboardResponse
  {
    try leaderboard(query, eligibleUserIDs: nil, now: now)
  }

  public func friendLeaderboard(_ query: LeaderboardQuery, accessToken: String, now: Date = .now)
    throws -> LeaderboardResponse
  {
    let current = try authenticatedUser(for: accessToken, now: now)
    let friendIDs = state.connections.reduce(into: Set([current.id])) { ids, connection in
      guard connection.status == "accepted" else { return }
      if connection.requesterID == current.id { ids.insert(connection.recipientID) }
      if connection.recipientID == current.id { ids.insert(connection.requesterID) }
    }
    return try leaderboard(query, eligibleUserIDs: friendIDs, now: now)
  }

  public func experienceLeaderboard(eligibleUserIDs: Set<UUID>? = nil, now: Date = .now)
    -> ExperienceLeaderboardResponse
  {
    let weekStart =
      Calendar(identifier: .iso8601).dateInterval(of: .weekOfYear, for: now)?.start ?? now
    let entries = state.users.compactMap { user -> (StoredUser, Int)? in
      guard !user.leaderboardOptedOut,
        eligibleUserIDs == nil || eligibleUserIDs!.contains(user.id)
      else { return nil }
      let weeklyPoints = experience(for: user.id, since: weekStart)
      return weeklyPoints > 0 ? (user, weeklyPoints) : nil
    }
    .sorted {
      if $0.1 != $1.1 { return $0.1 > $1.1 }
      return $0.0.displayName.localizedCaseInsensitiveCompare($1.0.displayName) == .orderedAscending
    }
    .prefix(100)
    .enumerated()
    .map { offset, value in
      ExperienceLeaderboardEntry(
        id: value.0.id, rank: offset + 1, userID: value.0.id, displayName: value.0.displayName,
        totalExperience: value.1)
    }
    return .init(entries: entries)
  }

  public func friendExperienceLeaderboard(accessToken: String, now: Date = .now) throws
    -> ExperienceLeaderboardResponse
  {
    let current = try authenticatedUser(for: accessToken, now: now)
    let friendIDs = state.connections.reduce(into: Set([current.id])) { ids, connection in
      guard connection.status == "accepted" else { return }
      if connection.requesterID == current.id { ids.insert(connection.recipientID) }
      if connection.recipientID == current.id { ids.insert(connection.requesterID) }
    }
    return experienceLeaderboard(eligibleUserIDs: friendIDs, now: now)
  }

  private func leaderboard(_ query: LeaderboardQuery, eligibleUserIDs: Set<UUID>?, now: Date) throws
    -> LeaderboardResponse
  {
    let modes = Set(["time", "words", "quote", "zen", "custom"])
    let languages = Set([
      "english", "spanish", "german", "french", "italian", "portuguese", "simplifiedChinese",
      "mixedEnglishChinese", "mixedLanguages",
    ])
    let periods = Set(["all", "day", "week"])
    if let mode = query.mode, !modes.contains(mode) { throw ResultStoreError.invalidResult }
    if let language = query.language, !languages.contains(language) {
      throw ResultStoreError.invalidResult
    }
    let period = query.period ?? "all"
    guard periods.contains(period) else { throw ResultStoreError.invalidResult }
    let limit = min(max(query.limit ?? 25, 1), 100)
    let cutoff: Date? =
      switch period {
      case "day": Calendar.current.startOfDay(for: now)
      case "week": Calendar(identifier: .iso8601).dateInterval(of: .weekOfYear, for: now)?.start
      default: nil
      }
    let users = Dictionary(uniqueKeysWithValues: state.users.map { ($0.id, $0) })
    let records = state.results.filter { result in
      (eligibleUserIDs == nil || eligibleUserIDs!.contains(result.userID))
        && users[result.userID]?.leaderboardOptedOut == false
        && (query.mode == nil || result.mode == query.mode)
        && (query.language == nil || result.language == query.language)
        && (cutoff == nil || result.finishedAt >= cutoff!)
    }.sorted {
      if $0.wpm != $1.wpm { return $0.wpm > $1.wpm }
      if $0.accuracy != $1.accuracy { return $0.accuracy > $1.accuracy }
      return $0.finishedAt > $1.finishedAt
    }
    var representedUsers = Set<UUID>()
    let bestRecordPerUser = records.filter { representedUsers.insert($0.userID).inserted }
    let entries = bestRecordPerUser.prefix(limit).enumerated().compactMap {
      offset, result -> LeaderboardEntry? in
      guard let user = users[result.userID] else { return nil }
      return .init(
        id: result.id, rank: offset + 1, userID: user.id, displayName: user.displayName,
        mode: result.mode, language: result.language, wpm: result.wpm,
        accuracy: result.accuracy, consistency: result.consistency, finishedAt: result.finishedAt)
    }
    return .init(entries: entries)
  }

  private func makeSession(for user: StoredUser, now: Date) -> AuthSessionResponse {
    let token = Self.makeAccessToken()
    let expiry = now.addingTimeInterval(60 * 60 * 24 * 30)
    state.sessions.append(
      .init(tokenHash: Self.tokenHash(token), userID: user.id, expiresAt: expiry))
    return .init(
      user: .init(
        id: user.id, email: user.email, displayName: user.displayName,
        totalExperience: experience(for: user.id), leaderboardOptedOut: user.leaderboardOptedOut),
      accessToken: token,
      expiresAt: expiry
    )
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

  private func persist() throws {
    guard let fileURL else { return }
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder.server.encode(state).write(to: fileURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
  }

  private func validatedEmail(_ value: String) throws -> String {
    let email = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let parts = email.split(separator: "@", omittingEmptySubsequences: false)
    guard email.count <= 254, parts.count == 2, !parts[0].isEmpty, parts[1].contains(".") else {
      throw AuthStoreError.invalidEmail
    }
    return email
  }

  private func validatedDisplayName(_ value: String) throws -> String {
    let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (2...32).contains(name.count) else { throw AuthStoreError.invalidDisplayName }
    return name
  }

  private func validatedPassword(_ value: String) throws {
    guard (12...72).contains(value.utf8.count) else { throw AuthStoreError.weakPassword }
  }

  private func validate(result: ResultSubmissionRequest, now: Date) throws {
    guard Set(["time", "words", "quote", "zen", "custom"]).contains(result.mode),
      Set([
        "english", "spanish", "german", "french", "italian", "portuguese", "simplifiedChinese",
        "mixedEnglishChinese", "mixedLanguages",
      ]).contains(result.language),
      (0...400).contains(result.wpm), (0...500).contains(result.rawWpm),
      (0...100).contains(result.accuracy), (0...100).contains(result.consistency),
      result.errorCount >= 0, result.eventCount >= 0,
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
