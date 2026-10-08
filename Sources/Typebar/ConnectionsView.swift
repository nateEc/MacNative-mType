import SwiftUI

enum ConnectionActionPolicy {
  static func canReject(_ relation: RemoteConnectionRelation) -> Bool { relation == .incomingRequest }
}

struct ConnectionsView: View {
  let account: AccountSession
  var body: some View {
    let owner = ConnectionsOwnerIdentity(account: account)
    ConnectionsSessionView(account: account, owner: owner).id(owner)
  }
}

private struct ConnectionsSessionView: View {
  @Environment(\.dismiss) private var dismiss
  let account: AccountSession
  let owner: ConnectionsOwnerIdentity
  @State private var state = ConnectionsManagementState()
  @State private var refresh = UUID()
  @State private var searchQuery = ""
  @State private var searchTask: Task<Void, Never>?
  @State private var searchTaskID: UUID?
  @State private var mutationTask: Task<Void, Never>?
  @State private var mutationTaskID: UUID?
  @State private var selectedConversation: RemotePublicProfile?
  private var readIdentity: ConnectionsReadIdentity { .init(owner: owner, account: account, refresh: refresh) }

  var body: some View {
    let request = readIdentity
    NavigationStack {
      Group {
        if owner.isCurrent(account), let ownerID = owner.owner.scope?.userID {
          ConnectionsManagementContent(ownerID: ownerID,
            snapshot: state.displayedSnapshot(request: request, account: account),
            searchResults: state.displayedSearch(owner: owner, account: account),
            isLoading: state.request != request || state.isLoading,
            isSearching: state.isSearching, isMutating: state.isMutating,
            message: state.request == request ? state.message : nil,
            searchMessage: state.displayedSearchMessage(owner: owner, account: account), query: $searchQuery,
            search: { search() }, action: { mutate($0, request: request) },
            conversation: { profile in
              guard state.canPerform(.remove(profile.id), request: request, account: account),
                state.displayedSnapshot(request: request, account: account)?.status(for: profile.id) == .friend else { return }
              selectedConversation = profile
            })
        } else {
          Text("请先在“设置 → 自建账户”中登录，才能管理好友关系。")
            .foregroundStyle(.secondary).padding()
        }
      }
      .navigationTitle("好友")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("刷新") { refresh = UUID() }
            .disabled(!owner.isCurrent(account) || state.isLoading || state.isMutating)
        }
        ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
      }
    }
    .frame(minWidth: 440, minHeight: 360)
    .sheet(item: $selectedConversation) { profile in
      if owner.isCurrent(account) { DirectConversationView(profile: profile, account: account) }
    }
    .task(id: request) {
      await state.load(request: request, account: account) { try await account.fetchConnectionsSnapshot(identity: request) }
    }
    .onChange(of: searchQuery) { _, _ in
      searchTask?.cancel(); searchTask = nil; searchTaskID = nil; state.clearSearch()
    }
    .onDisappear { cancelTasks() }
  }

  private func search() {
    guard searchTask == nil, owner.isCurrent(account) else { return }
    let token = UUID(), query = searchQuery; searchTaskID = token
    searchTask = Task { @MainActor in
      defer { if searchTaskID == token { searchTask = nil; searchTaskID = nil } }
      await state.search(query: query, owner: owner, account: account) {
        try await account.searchConnectionsProfiles(query: $0, identity: owner)
      }
    }
  }
  private func mutate(_ action: ConnectionsMutation, request: ConnectionsReadIdentity) {
    guard mutationTask == nil else { return }
    let token = UUID(); mutationTaskID = token
    mutationTask = Task { @MainActor in
      defer { if mutationTaskID == token { mutationTask = nil; mutationTaskID = nil } }
      let confirmed = await state.perform(action, request: request, account: account) {
        try await account.performConnectionsMutation(action, identity: request)
      }
      if confirmed, owner.isCurrent(account) { refresh = UUID() }
    }
  }
  private func cancelTasks() {
    searchTask?.cancel(); searchTask = nil; searchTaskID = nil
    mutationTask?.cancel(); mutationTask = nil; mutationTaskID = nil
  }
}

/// Production form without account/network ownership, for isolated layout QA.
struct ConnectionsManagementContent: View {
  let ownerID: UUID
  let snapshot: ConnectionsSnapshot?
  let searchResults: [RemotePublicProfile]
  let isLoading: Bool
  let isSearching: Bool
  let isMutating: Bool
  let message: String?
  var searchMessage: String? = nil
  @Binding var query: String
  let search: () -> Void
  let action: (ConnectionsMutation) -> Void
  let conversation: (RemotePublicProfile) -> Void
  @State private var pendingRemoval: UUID?

  private func can(_ action: ConnectionsMutation) -> Bool {
    !isLoading && !isMutating && snapshot?.allows(action, ownerID: ownerID) == true
  }
  var body: some View {
    Form {
      Section("寻找用户") {
        TextField("按公开展示名搜索（2–40 个字符）", text: $query)
        Button("搜索用户", action: search)
          .disabled(isSearching || isMutating || ProfileSearchCommandPolicy.normalized(query) == nil)
        if isSearching { ProgressView("正在搜索用户…") }
        if let searchMessage { Text(searchMessage).font(.caption).foregroundStyle(.secondary) }
        ForEach(searchResults.filter { $0.id != ownerID && snapshot?.blockedIDs.contains($0.id) != true }) { profile in
          VStack(alignment: .leading, spacing: 6) {
            profileSummary(profile)
            HStack {
              if let status = snapshot?.status(for: profile.id), status != .notConnected {
                Text(statusText(status)).font(.caption).foregroundStyle(.secondary)
              } else {
                Button("添加好友") { action(.send(profile.id)) }.disabled(!can(.send(profile.id)))
              }
              Spacer()
              Button("屏蔽", role: .destructive) { action(.block(profile.id)) }.disabled(!can(.block(profile.id)))
            }
          }
        }
      }
      if let snapshot {
        Section("收到的请求") { rows(snapshot, relation: .incomingRequest, empty: "没有待处理的好友请求。") }
        Section("已发送") { rows(snapshot, relation: .outgoingRequest, empty: "没有已发送的好友请求。") }
        Section("好友") { rows(snapshot, relation: .friend, empty: "还没有好友。可搜索公开展示名发送请求。") }
        Section("已屏蔽") {
          if snapshot.blockedProfiles.isEmpty { Text("没有已屏蔽用户。").foregroundStyle(.secondary) }
          ForEach(snapshot.blockedProfiles) { profile in
            HStack {
              Text(profile.displayName)
              Spacer()
              Button("解除屏蔽") { action(.unblock(profile.id)) }.disabled(!can(.unblock(profile.id)))
            }
          }
        }
      } else if !isLoading {
        Text("当前好友关系未知。请刷新后再管理请求、好友或屏蔽。").foregroundStyle(.secondary)
      }
      if isLoading { ProgressView("正在读取好友关系…") }
      if isMutating {
        Text("正在提交。关闭只会取消等待，服务端可能已收到操作；重新打开后请刷新确认。")
          .font(.caption).foregroundStyle(.secondary)
      }
      if let message { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
    }
    .formStyle(.grouped)
    .confirmationDialog("解除好友关系？", isPresented: Binding(get: { pendingRemoval != nil },
      set: { if !$0 { pendingRemoval = nil } })) {
      if let id = pendingRemoval {
        Button("解除好友关系", role: .destructive) { if can(.remove(id)) { action(.remove(id)) }; pendingRemoval = nil }
      }
      Button("取消", role: .cancel) { pendingRemoval = nil }
    }
  }
  @ViewBuilder private func rows(_ snapshot: ConnectionsSnapshot, relation: RemoteConnectionRelation, empty: String) -> some View {
    let values = snapshot.visibleConnections.filter { $0.relation == relation }
    if values.isEmpty { Text(empty).foregroundStyle(.secondary) }
    ForEach(values) { row in
      VStack(alignment: .leading, spacing: 6) {
        profileSummary(row.profile)
        HStack {
          if relation == .incomingRequest {
            Button("接受") { action(.accept(row.profile.id)) }.disabled(!can(.accept(row.profile.id)))
            Button("拒绝", role: .destructive) { action(.remove(row.profile.id)) }.disabled(!can(.remove(row.profile.id)))
          } else if relation == .outgoingRequest {
            Button("取消请求") { action(.remove(row.profile.id)) }.disabled(!can(.remove(row.profile.id)))
          } else {
            Button("解除") { pendingRemoval = row.profile.id }.disabled(!can(.remove(row.profile.id)))
            Button("消息") { conversation(row.profile) }.disabled(!can(.remove(row.profile.id)))
          }
          Spacer()
          Button("屏蔽", role: .destructive) { action(.block(row.profile.id)) }.disabled(!can(.block(row.profile.id)))
        }
      }
    }
  }
  private func profileSummary(_ profile: RemotePublicProfile) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(profile.displayName)
      Text("最佳 \(profile.bestSpeedText) WPM · \(profile.highestConsistency.formatted(.number.precision(.fractionLength(0...2))))% 稳定 · \(profile.completedResultCount) 次完成 · \(profile.startedTestCount) 次开始")
        .font(.caption).foregroundStyle(.secondary)
    }
  }
  private func statusText(_ status: ProfileRelationshipStatus) -> String {
    switch status {
    case .outgoingRequest: "已发送请求，等待对方接受"
    case .incomingRequest: "已收到请求，可在下方接受或拒绝"
    case .friend: "你们已是好友"
    case .blocked: "你已屏蔽此用户"
    default: "当前关系未知，请刷新"
    }
  }
}
