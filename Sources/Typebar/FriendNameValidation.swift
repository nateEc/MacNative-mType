import Foundation
import Observation

struct FriendNameCheckID: Equatable {
  let read: ConnectionsReadIdentity
  let rawName: String
  let ownerName: String
  let snapshotReady: Bool
  var retry: UUID = UUID()
  @MainActor func isCurrent(_ account: AccountSession) -> Bool {
    read.isCurrent(account) && account.currentUser?.displayName == ownerName
  }
}

enum FriendNameStatus {
  case idle, invalid, selfName, unavailable, checking, unknown, existing(ProfileRelationshipStatus)
  case ready(RemotePublicProfile), failed(String)
  var message: String {
    switch self {
    case .idle: "输入完整展示名，停止输入 1 秒后校验。"
    case .invalid: "请输入 1–32 个字符的完整展示名，不包含控制字符。"
    case .selfName: "不能向本人发送好友请求。"
    case .unavailable: "当前关系未知或正在变更；请关闭后刷新好友列表。"
    case .checking: "正在校验完整展示名…"
    case .unknown: "没有找到这个完整展示名。"
    case .existing(.blocked): "你已屏蔽这个用户；请先在已屏蔽列表解除。"
    case .existing(.friend): "你们已经是好友。"
    case .existing(.incomingRequest): "已收到这个用户的请求；请在收到的请求中处理。"
    case .existing(.outgoingRequest): "已发送请求，等待对方接受。"
    case .existing: "当前关系未知，请刷新。"
    case .ready(let profile): "将向 \(profile.displayName) 发送好友请求。"
    case .failed(let error): "精确名称校验不可用。可重试，或返回好友页使用搜索：" + error
    }
  }
}

enum FriendNamePolicy {
  static func normalized(_ value: String) -> String? {
    let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...32).contains(name.count), name.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil else { return nil }
    return name
  }
  static func key(_ name: String) -> String {
    name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
  }
  static func local(_ name: String, ownerName: String, snapshot: ConnectionsSnapshot) -> FriendNameStatus? {
    if key(name) == key(ownerName) { return .selfName }
    if snapshot.blockedProfiles.contains(where: { key($0.displayName) == key(name) }) { return .existing(.blocked) }
    if let row = snapshot.connections.first(where: { key($0.profile.displayName) == key(name) }) {
      return .existing(snapshot.status(for: row.profile.id))
    }
    return nil
  }
}

@MainActor @Observable final class FriendNameValidationState {
  private(set) var request: FriendNameCheckID?
  private(set) var status: FriendNameStatus = .idle
  private var generation = UUID()
  func clear() { generation = UUID(); request = nil; status = .idle }
  func displayedStatus(_ id: FriendNameCheckID, account: AccountSession) -> FriendNameStatus {
    request == id && id.isCurrent(account) ? status : .idle
  }
  func readyProfile(_ id: FriendNameCheckID, account: AccountSession,
    management: ConnectionsManagementState) -> RemotePublicProfile? {
    guard request == id, id.isCurrent(account), id.snapshotReady, case .ready(let profile) = status,
      management.canPerform(.send(profile.id), request: id.read, account: account) else { return nil }
    return profile
  }
  func check(_ id: FriendNameCheckID, account: AccountSession, management: ConnectionsManagementState,
    debounce: () async throws -> Void, resolve: (String) async throws -> RemotePublicProfile?) async {
    let nonce = UUID(); generation = nonce; request = id; status = .idle
    guard !Task.isCancelled, id.isCurrent(account) else { return }
    guard id.snapshotReady, !management.isLoading, !management.isMutating,
      let snapshot = management.displayedSnapshot(request: id.read, account: account) else { status = .unavailable; return }
    guard let name = FriendNamePolicy.normalized(id.rawName) else {
      status = id.rawName.isEmpty ? .idle : .invalid; return
    }
    if let local = FriendNamePolicy.local(name, ownerName: id.ownerName, snapshot: snapshot) { status = local; return }
    status = .checking
    func current() -> Bool {
      !Task.isCancelled && generation == nonce && request == id && id.isCurrent(account)
        && !management.isLoading && !management.isMutating
        && management.displayedSnapshot(request: id.read, account: account) != nil
    }
    do {
      try await debounce()
      guard current() else { return }
      let value = try await resolve(name)
      guard current() else { return }
      guard let value else { status = .unknown; return }
      guard FriendNamePolicy.key(value.displayName) == FriendNamePolicy.key(name), value.activity == nil,
        value.accountStreakClaim == nil else { throw RemoteAccountError.unexpectedResponse }
      if value.id == id.read.owner.owner.scope?.userID { status = .selfName; return }
      // Resolve renames against current UUID relationships, not only old names.
      guard let latest = management.displayedSnapshot(request: id.read, account: account) else { return }
      let relation = latest.status(for: value.id)
      status = relation == .notConnected ? .ready(value) : .existing(relation)
    } catch {
      guard current() else { return }
      status = .failed(error.localizedDescription)
    }
  }
}

struct RemoteProfileNameLookupResponse: Decodable, Sendable {
  let version: Int
  let profile: RemotePublicProfile?
}
