import SwiftUI

struct ConnectionsView: View {
    @Environment(\.dismiss) private var dismiss
    let account: AccountSession
    @State private var connections: [RemoteConnection] = []
    @State private var blockedProfiles: [RemotePublicProfile] = []
    @State private var isLoading = false
    @State private var message: String?
    @State private var searchQuery = ""
    @State private var searchResults: [RemotePublicProfile] = []
    @State private var isSearching = false
    @State private var selectedConversation: RemotePublicProfile?

    private var incoming: [RemoteConnection] { connections.filter { $0.relation == .incomingRequest } }
    private var outgoing: [RemoteConnection] { connections.filter { $0.relation == .outgoingRequest } }
    private var friends: [RemoteConnection] { connections.filter { $0.relation == .friend } }
    private var visibleSearchResults: [RemotePublicProfile] {
        let blockedIDs = Set(blockedProfiles.map(\.id))
        return searchResults.filter { $0.id != account.currentUser?.id && !blockedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if account.currentUser == nil {
                    Text("请先在“设置 → 自建账户”中登录，才能管理好友关系。")
                        .foregroundStyle(.secondary)
                } else {
                    Section("寻找用户") {
                        TextField("按公开展示名搜索（至少 2 个字符）", text: $searchQuery)
                        Button("搜索用户", action: search)
                            .disabled(isSearching || searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                        if isSearching { ProgressView() }
                        ForEach(visibleSearchResults) { profile in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.displayName)
                                    Text(profileSummary(profile))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("添加好友") { sendRequest(to: profile) }
                                Button("屏蔽", role: .destructive) { block(profile) }
                            }
                        }
                    }
                    Section("收到的请求") {
                        rows(incoming, empty: "没有待处理的好友请求。", buttonTitle: "接受", action: accept)
                    }
                    Section("已发送") {
                        rows(outgoing, empty: "没有已发送的好友请求。", buttonTitle: "取消", action: remove)
                    }
                    Section("好友") {
                        rows(friends, empty: "还没有好友。可在排行榜的资料卡中发送请求。", buttonTitle: "解除", action: remove)
                    }
                    Section("已屏蔽") {
                        if blockedProfiles.isEmpty {
                            Text("没有已屏蔽用户。") .foregroundStyle(.secondary)
                        } else {
                            ForEach(blockedProfiles) { profile in
                                HStack {
                                    Text(profile.displayName)
                                    Spacer()
                                    Button("解除屏蔽") { unblock(profile) }
                                }
                            }
                        }
                    }
                    if isLoading { ProgressView() }
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("好友")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("刷新", action: load).disabled(account.currentUser == nil || isLoading)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(minWidth: 440, minHeight: 360)
        .sheet(item: $selectedConversation) { profile in
            DirectConversationView(profile: profile, account: account)
        }
        .task { if account.currentUser != nil { await loadAsync() } }
    }

    @ViewBuilder
    private func rows(_ values: [RemoteConnection], empty: String, buttonTitle: String, action: @escaping (RemoteConnection) -> Void) -> some View {
        if values.isEmpty {
            Text(empty).foregroundStyle(.secondary)
        } else {
            ForEach(values) { connection in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connection.profile.displayName)
                        Text(profileSummary(connection.profile))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(buttonTitle) { action(connection) }
                    if connection.relation == .friend {
                        Button("消息") { selectedConversation = connection.profile }
                    }
                    Button("屏蔽", role: .destructive) { block(connection.profile) }
                }
            }
        }
    }

    private func load() { Task { await loadAsync() } }

    private func profileSummary(_ profile: RemotePublicProfile) -> String {
        let consistency = profile.highestConsistency.formatted(
            .number.precision(.fractionLength(0...2)))
        return "最佳 \(profile.bestWPM) WPM · \(consistency)% 稳定 · \(profile.completedResultCount) 次完成 · \(profile.startedTestCount) 次开始"
    }

    private func loadAsync() async {
        isLoading = true
        defer { isLoading = false }
        do {
            connections = try await account.connections()
            blockedProfiles = try await account.blockedUsers()
            message = connections.isEmpty ? "没有好友关系。" : "已加载 \(connections.count) 条好友关系。"
        } catch {
            message = error.localizedDescription
        }
    }

    private func accept(_ connection: RemoteConnection) {
        Task {
            do {
                _ = try await account.acceptConnection(from: connection.profile.id)
                await loadAsync()
            } catch { message = error.localizedDescription }
        }
    }

    private func remove(_ connection: RemoteConnection) {
        Task {
            do {
                try await account.removeConnection(with: connection.profile.id)
                await loadAsync()
            } catch { message = error.localizedDescription }
        }
    }

    private func search() {
        Task {
            isSearching = true
            defer { isSearching = false }
            do {
                searchResults = try await account.searchPublicProfiles(query: searchQuery)
                message = searchResults.isEmpty ? "没有匹配的公开展示名。" : "找到 \(searchResults.count) 位用户。"
            } catch { message = error.localizedDescription }
        }
    }

    private func sendRequest(to profile: RemotePublicProfile) {
        Task {
            do {
                _ = try await account.sendConnection(to: profile.id)
                message = "已向 \(profile.displayName) 发送好友请求。"
                await loadAsync()
            } catch { message = error.localizedDescription }
        }
    }

    private func block(_ profile: RemotePublicProfile) {
        Task {
            do {
                try await account.blockUser(profile.id)
                searchResults.removeAll { $0.id == profile.id }
                message = "已屏蔽 \(profile.displayName)，并移除了已有好友关系或请求。"
                await loadAsync()
            } catch { message = error.localizedDescription }
        }
    }

    private func unblock(_ profile: RemotePublicProfile) {
        Task {
            do {
                try await account.unblockUser(profile.id)
                await loadAsync()
                message = "已解除对 \(profile.displayName) 的屏蔽。"
            } catch { message = error.localizedDescription }
        }
    }
}
