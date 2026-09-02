import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    let account: AccountSession
    @State private var notifications: [RemoteNotification] = []
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Group {
                if account.currentUser == nil {
                    ContentUnavailableView("请先登录", systemImage: "bell.slash", description: Text("登录自建 Typebar 服务后可查看好友和私信通知。"))
                } else if notifications.isEmpty, !isLoading {
                    ContentUnavailableView("还没有通知", systemImage: "bell", description: Text("好友关系和新私信会显示在这里。"))
                } else {
                    List(notifications) { notification in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: icon(for: notification.kind))
                                .foregroundStyle(notification.readAt == nil ? Color.accentColor : Color.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title(for: notification))
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
    }

    private func title(for notification: RemoteNotification) -> String {
        switch notification.kind {
        case .connectionRequest: "\(notification.actor.displayName) 想与你成为好友"
        case .connectionAccepted: "\(notification.actor.displayName) 接受了你的好友请求"
        case .directMessage: "\(notification.actor.displayName) 发来了一条新消息"
        }
    }

    private func icon(for kind: RemoteNotificationKind) -> String {
        switch kind {
        case .connectionRequest: "person.badge.plus"
        case .connectionAccepted: "person.2.fill"
        case .directMessage: "bubble.left.fill"
        }
    }

    private func load() { Task { await loadAsync() } }

    private func loadAsync() async {
        isLoading = true
        defer { isLoading = false }
        do {
            notifications = try await account.notifications()
            message = notifications.isEmpty ? "没有新通知。" : "已加载 \(notifications.count) 条通知。"
        } catch { message = error.localizedDescription }
    }

    private func markRead(_ notification: RemoteNotification) {
        Task {
            do {
                let updated = try await account.markNotificationRead(notification.id)
                guard let index = notifications.firstIndex(where: { $0.id == updated.id }) else { return }
                notifications[index] = updated
            } catch { message = error.localizedDescription }
        }
    }
}
