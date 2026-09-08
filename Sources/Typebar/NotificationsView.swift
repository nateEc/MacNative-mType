import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    let account: AccountSession
    let onUnreadCountChange: (Int) -> Void
    @State private var notifications: [RemoteNotification] = []
    @State private var maxCount: Int?
    @State private var isLoading = false
    @State private var message: String?
    @State private var confirmingDeleteAll = false

    var body: some View {
        NavigationStack {
            Group {
                if account.currentUser == nil {
                    ContentUnavailableView("请先登录", systemImage: "bell.slash", description: Text("登录自建 Typebar 服务后可查看好友、私信和徽章奖励通知。"))
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Text(inboxCountText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        if notifications.isEmpty, !isLoading {
                            ContentUnavailableView(
                                "还没有通知", systemImage: "bell",
                                description: Text("好友关系、新私信和徽章奖励会显示在这里。"))
                        } else {
                            List(notifications) { notification in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: notification.presentationSystemImage)
                                        .foregroundStyle(notification.readAt == nil ? Color.accentColor : Color.secondary)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(notification.presentationTitle)
                                            .font(notification.readAt == nil ? .body.weight(.semibold) : .body)
                                        Text(notification.createdAt, format: .dateTime.year().month().day().hour().minute())
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if notification.readAt == nil {
                                        Button("标为已读") { markRead(notification) }
                                            .buttonStyle(.borderless)
                                    }
                                    Button("删除", systemImage: "trash", role: .destructive) {
                                        delete(notification)
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                    .help("删除这条通知")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("通知")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("刷新", action: load)
                        .disabled(account.currentUser == nil || isLoading)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("全部删除", systemImage: "trash", role: .destructive) {
                        confirmingDeleteAll = true
                    }
                    .disabled(notifications.isEmpty || isLoading)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if isLoading { ProgressView().padding() }
                else if let message { Text(message).font(.caption).foregroundStyle(.secondary).padding() }
            }
        }
        .frame(minWidth: 430, minHeight: 320)
        .task { if account.currentUser != nil { await loadAsync() } }
        .confirmationDialog(
            "删除全部通知？", isPresented: $confirmingDeleteAll, titleVisibility: .visible
        ) {
            Button("删除全部通知", role: .destructive) { deleteAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会清空当前账户的通知，不会删除好友关系、私信或已解锁徽章。")
        }
    }

    private func load() { Task { await loadAsync() } }

    private func loadAsync() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let inbox = try await account.notificationInbox()
            notifications = inbox.notifications
            maxCount = inbox.maxCount
            onUnreadCountChange(inbox.unreadCount)
            message = notifications.isEmpty ? "没有新通知。" : "已加载 \(notifications.count) 条通知。"
        } catch { message = error.localizedDescription }
    }

    private func markRead(_ notification: RemoteNotification) {
        Task {
            do {
                let updated = try await account.markNotificationRead(notification.id)
                guard let index = notifications.firstIndex(where: { $0.id == updated.id }) else { return }
                notifications[index] = updated
                publishUnreadCount()
            } catch { message = error.localizedDescription }
        }
    }

    private func delete(_ notification: RemoteNotification) {
        Task {
            do {
                try await account.deleteNotification(notification.id)
                notifications.removeAll { $0.id == notification.id }
                publishUnreadCount()
                message = "通知已删除。"
            } catch { message = error.localizedDescription }
        }
    }

    private func deleteAll() {
        Task {
            do {
                let deletedCount = try await account.deleteAllNotifications()
                notifications.removeAll()
                publishUnreadCount()
                message = "已删除 \(deletedCount) 条通知。"
            } catch { message = error.localizedDescription }
        }
    }

    private func publishUnreadCount() {
        onUnreadCountChange(notifications.lazy.filter { $0.readAt == nil }.count)
    }

    private var inboxCountText: String {
        guard let maxCount else { return "共 \(notifications.count) 条" }
        return "收件箱 \(notifications.count) / \(maxCount)"
    }
}
