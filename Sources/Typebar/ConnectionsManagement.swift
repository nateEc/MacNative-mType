import Foundation
import Observation

struct ConnectionsOwnerIdentity: Hashable {
  let endpoint: String
  let owner: AccountProfileEditIdentity
  @MainActor init(account: AccountSession) {
    endpoint = account.endpoint; owner = .init(account: account)
  }
  @MainActor func isCurrent(_ account: AccountSession) -> Bool {
    endpoint == account.endpoint && owner.isCurrent(account)
  }
}

struct ConnectionsReadIdentity: Equatable {
  let owner: ConnectionsOwnerIdentity
  let relationshipRevision: UInt64
  let refresh: UUID
  @MainActor init(owner: ConnectionsOwnerIdentity, account: AccountSession, refresh: UUID) {
    self.owner = owner; relationshipRevision = account.profileRelationshipRevision; self.refresh = refresh
  }
  @MainActor func isCurrent(_ account: AccountSession) -> Bool {
    owner.isCurrent(account) && relationshipRevision == account.profileRelationshipRevision
  }
}

enum ConnectionsMutation: Equatable {
  case send(UUID), accept(UUID), remove(UUID), block(UUID), unblock(UUID)
  var targetID: UUID {
    switch self {
    case .send(let id), .accept(let id), .remove(let id), .block(let id), .unblock(let id): id
    }
  }
}

struct ConnectionsSnapshot {
  let connections: [RemoteConnection]
  let blockedProfiles: [RemotePublicProfile]
  var blockedIDs: Set<UUID> { Set(blockedProfiles.map(\.id)) }
  var visibleConnections: [RemoteConnection] {
    let blocked = blockedIDs
    return connections.filter { !blocked.contains($0.profile.id) }.sorted {
      $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
    }
  }
  func validate(ownerID: UUID) throws {
    guard blockedIDs.count == blockedProfiles.count, !blockedIDs.contains(ownerID) else {
      throw RemoteAccountError.unexpectedResponse
    }
    _ = try ProfileRelationshipSnapshot(connections: connections, blockedIDs: blockedIDs)
      .status(for: ownerID, ownerID: ownerID)
  }
  func status(for id: UUID) -> ProfileRelationshipStatus {
    if blockedIDs.contains(id) { return .blocked }
    switch connections.first(where: { $0.profile.id == id })?.relation {
    case .friend: return .friend
    case .incomingRequest: return .incomingRequest
    case .outgoingRequest: return .outgoingRequest
    case nil: return .notConnected
    }
  }
  func allows(_ action: ConnectionsMutation, ownerID: UUID) -> Bool {
    guard action.targetID != ownerID else { return false }
    let relation = status(for: action.targetID)
    switch action {
    case .send: return relation == .notConnected
    case .accept: return relation == .incomingRequest
    case .remove: return [.incomingRequest, .outgoingRequest, .friend].contains(relation)
    case .block: return relation != .blocked
    case .unblock: return relation == .blocked
    }
  }
}

/// A single authenticated page's private data. No persistent/global friend cache.
@MainActor @Observable final class ConnectionsManagementState {
  private(set) var request: ConnectionsReadIdentity?
  private(set) var snapshot: ConnectionsSnapshot?
  private(set) var isLoading = false
  private(set) var message: String?
  private(set) var searchResults: [RemotePublicProfile] = []
  private(set) var searchMessage: String?
  private(set) var isSearching = false
  private var searchOwner: ConnectionsOwnerIdentity?
  private var loadGeneration = UUID()
  private var searchGeneration = UUID()
  private var operation: UUID?
  var isMutating: Bool { operation != nil }

  func displayedSnapshot(request: ConnectionsReadIdentity, account: AccountSession) -> ConnectionsSnapshot? {
    self.request == request && request.isCurrent(account) ? snapshot : nil
  }
  func displayedSearch(owner: ConnectionsOwnerIdentity, account: AccountSession) -> [RemotePublicProfile] {
    guard owner == searchOwner, owner.isCurrent(account), let ownerID = owner.owner.scope?.userID else { return [] }
    return searchResults.filter { $0.id != ownerID }
  }
  func displayedSearchMessage(owner: ConnectionsOwnerIdentity, account: AccountSession) -> String? {
    owner == searchOwner && owner.isCurrent(account) ? searchMessage : nil
  }
  func canPerform(_ action: ConnectionsMutation, request: ConnectionsReadIdentity, account: AccountSession) -> Bool {
    guard !isMutating, !isLoading, let ownerID = request.owner.owner.scope?.userID,
      let snapshot = displayedSnapshot(request: request, account: account) else { return false }
    return snapshot.allows(action, ownerID: ownerID)
  }

  func load(request: ConnectionsReadIdentity, account: AccountSession,
    fetch: () async throws -> ConnectionsSnapshot) async {
    guard !Task.isCancelled, request.isCurrent(account) else { return }
    let nonce = UUID(); loadGeneration = nonce; self.request = request
    snapshot = nil; message = nil; isLoading = true
    defer { if loadGeneration == nonce { isLoading = false } }
    do {
      let value = try await account.loadConnectionsSnapshot(identity: request, fetch: fetch)
      guard !Task.isCancelled, loadGeneration == nonce, self.request == request, request.isCurrent(account) else { return }
      snapshot = value
      message = "好友关系已刷新。"
    } catch {
      guard !Task.isCancelled, loadGeneration == nonce, self.request == request, request.isCurrent(account) else { return }
      message = "关系读取失败，当前关系未知；请刷新后再操作：" + error.localizedDescription
    }
  }

  func clearSearch() {
    searchGeneration = UUID(); searchResults = []; searchMessage = nil; searchOwner = nil; isSearching = false
  }
  func search(query: String, owner: ConnectionsOwnerIdentity, account: AccountSession,
    fetch: (String) async throws -> [RemotePublicProfile]) async {
    guard !Task.isCancelled, owner.isCurrent(account), !isMutating,
      let query = ProfileSearchCommandPolicy.normalized(query) else { return }
    let nonce = UUID(); searchGeneration = nonce; searchOwner = owner
    searchResults = []; searchMessage = nil; isSearching = true
    defer { if searchGeneration == nonce { isSearching = false } }
    do {
      let values = try await account.loadConnectionsSearch(identity: owner) { try await fetch(query) }
      guard !Task.isCancelled, searchGeneration == nonce, searchOwner == owner, owner.isCurrent(account) else { return }
      guard Set(values.map(\.id)).count == values.count else { throw RemoteAccountError.unexpectedResponse }
      searchResults = values
      searchMessage = values.isEmpty ? "没有匹配的公开展示名。" : "找到 \(values.count) 位用户。"
    } catch {
      guard !Task.isCancelled, searchGeneration == nonce, searchOwner == owner, owner.isCurrent(account) else { return }
      searchMessage = "用户搜索失败，请重试：" + error.localizedDescription
    }
  }

  @discardableResult func perform(_ action: ConnectionsMutation, request: ConnectionsReadIdentity,
    account: AccountSession, submit: () async throws -> Void) async -> Bool {
    guard !Task.isCancelled, canPerform(action, request: request, account: account) else { return false }
    let token = UUID(); operation = token
    defer { if operation == token { operation = nil } }
    do {
      try await account.loadConnectionsMutation(identity: request, submit: submit)
      guard operation == token, request.owner.isCurrent(account) else { return false }
      if self.request == request { snapshot = nil; message = "操作已确认，请刷新好友关系。" }
      return true
    } catch {
      guard operation == token, request.owner.isCurrent(account) else { return false }
      // Even a cancelled/lost response can follow a committed server write.
      // Retire reads begun before this outcome; only a later refresh unlocks writes.
      loadGeneration = UUID(); snapshot = nil; isLoading = false
      message = "操作未确认，服务端可能已收到；请刷新关系后再操作：" + error.localizedDescription
      return false
    }
  }
}
