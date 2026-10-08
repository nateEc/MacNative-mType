import Foundation
import Observation

struct ProfileRelationshipIdentity: Equatable {
  let profileID: UUID
  let endpoint: String
  let scope: ResultPublicationScope?
  let sessionRevision: UInt64
  let relationshipRevision: UInt64
  let allowsAccountActions: Bool
  let isAccountOverview: Bool
  let retryRevision: UUID

  @MainActor init(profileID: UUID, account: AccountSession, allowsAccountActions: Bool = true,
    isAccountOverview: Bool = false, retryRevision: UUID) {
    self.profileID = profileID; endpoint = account.endpoint; scope = account.resultPublicationScope
    sessionRevision = account.accountPersonalBestSessionRevision
    relationshipRevision = account.profileRelationshipRevision
    self.allowsAccountActions = allowsAccountActions; self.isAccountOverview = isAccountOverview
    self.retryRevision = retryRevision
  }
  @MainActor func isCurrent(_ account: AccountSession) -> Bool {
    allowsAccountActions && !isAccountOverview && scope != nil && scope?.userID != profileID
      && endpoint == account.endpoint && scope == account.resultPublicationScope
      && sessionRevision == account.accountPersonalBestSessionRevision
  }
  @MainActor func isCurrentRead(_ account: AccountSession) -> Bool {
    isCurrent(account) && relationshipRevision == account.profileRelationshipRevision
  }
}

enum ProfileRelationshipStatus: Equatable {
  case unavailable, loading, notConnected, outgoingRequest, incomingRequest, friend, blocked
  case failed(String)
  var canSend: Bool { self == .notConnected }
}

struct ProfileRelationshipSnapshot {
  let connections: [RemoteConnection]
  let blockedIDs: Set<UUID>

  func status(for profileID: UUID, ownerID: UUID) throws -> ProfileRelationshipStatus {
    guard Set(connections.map(\.profile.id)).count == connections.count,
      connections.allSatisfy({ $0.id == $0.profile.id && $0.profile.id != ownerID }) else {
      throw RemoteAccountError.unexpectedResponse
    }
    // A block may arrive between the two reads; never offer a write in that case.
    if blockedIDs.contains(profileID) { return .blocked }
    guard let relation = connections.first(where: { $0.profile.id == profileID })?.relation else { return .notConnected }
    switch relation {
    case .outgoingRequest: return .outgoingRequest
    case .incomingRequest: return .incomingRequest
    case .friend: return .friend
    }
  }
}

/// View-local private status. No global friend list, credentials or disk cache.
@MainActor @Observable final class ProfileRelationshipState {
  private(set) var request: ProfileRelationshipIdentity?
  private(set) var status: ProfileRelationshipStatus = .unavailable
  private var generation = UUID()
  private var operation: UUID?
  var isSending: Bool { operation != nil }

  func displayedStatus(identity: ProfileRelationshipIdentity, account: AccountSession) -> ProfileRelationshipStatus {
    guard identity.isCurrentRead(account), request == identity else { return .unavailable }
    return status
  }

  func load(identity: ProfileRelationshipIdentity, account: AccountSession,
    fetch: () async throws -> ProfileRelationshipSnapshot) async {
    guard !Task.isCancelled, identity.isCurrentRead(account) else { return }
    let nonce = UUID(); generation = nonce; operation = nil
    request = identity; status = .loading
    do {
      let result = try await account.loadProfileRelationship(identity: identity, fetch: fetch)
      guard !Task.isCancelled, generation == nonce, request == identity, identity.isCurrentRead(account) else { return }
      status = result
    } catch {
      guard !Task.isCancelled, generation == nonce, request == identity, identity.isCurrentRead(account) else { return }
      status = .failed("关系读取失败，请刷新后再发送请求：" + error.localizedDescription)
    }
  }

  func send(identity: ProfileRelationshipIdentity, account: AccountSession,
    submit: () async throws -> RemoteConnection) async {
    guard !Task.isCancelled, identity.isCurrentRead(account), request == identity,
      status.canSend, operation == nil else { return }
    let token = UUID(), nonce = generation; operation = token
    defer { if operation == token { operation = nil } }
    do {
      _ = try await account.loadProfileConnectionSend(identity: identity, submit: submit)
      guard operation == token, generation == nonce, request == identity, identity.isCurrent(account) else { return }
      status = .outgoingRequest
    } catch {
      guard operation == token, generation == nonce, request == identity, identity.isCurrent(account) else { return }
      // A request can commit before cancellation or a lost response. Do not retry
      // blindly or roll back to a misleading "not connected" state.
      status = .failed("发送未确认，服务端可能已收到；请刷新关系后再操作：" + error.localizedDescription)
    }
  }
}
