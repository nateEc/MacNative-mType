import SwiftUI

struct DirectConversationView: View {
    @Environment(\.dismiss) private var dismiss
    let profile: RemotePublicProfile
    let account: AccountSession

    @State private var messages: [RemoteDirectMessage] = []
    @State private var draft = ""
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName).font(.headline.monospaced())
                    Text("仅限已接受的好友 · 消息不会公开显示")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("刷新", action: load).disabled(isWorking)
            }
            .padding([.horizontal, .top], 20)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if messages.isEmpty {
                        ContentUnavailableView("还没有消息", systemImage: "bubble.left.and.bubble.right", description: Text("写下一条练习感受，开始这段对话。"))
                            .padding(.top, 48)
                    }
                    ForEach(messages) { item in
                        let isMine = item.senderID == account.currentUser?.id
                        HStack {
                            if isMine { Spacer(minLength: 70) }
                            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                                Text(item.body).textSelection(.enabled)
                                Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(isMine ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                            if !isMine { Spacer(minLength: 70) }
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            VStack(alignment: .trailing, spacing: 7) {
                TextEditor(text: $draft)
                    .frame(height: 68)
                    .overlay(alignment: .topLeading) {
                        if draft.isEmpty { Text("写一条消息").foregroundStyle(.tertiary).padding(8).allowsHitTesting(false) }
                    }
                HStack {
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Text("\(draft.count)/1000").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Button("发送", action: send).buttonStyle(.borderedProminent)
                        .disabled(isWorking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 1000)
                }
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
        .task { await loadAsync() }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
    }

    private func load() { Task { await loadAsync() } }
    private func loadAsync() async {
        isWorking = true
        defer { isWorking = false }
        do {
            messages = try await account.directConversation(with: profile.id)
            try await account.markDirectConversationRead(with: profile.id)
            message = nil
        } catch { message = error.localizedDescription }
    }
    private func send() {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                let sent = try await account.sendDirectMessage(to: profile.id, body: draft)
                messages.append(sent)
                draft = ""
                message = nil
            } catch { message = error.localizedDescription }
        }
    }
}
