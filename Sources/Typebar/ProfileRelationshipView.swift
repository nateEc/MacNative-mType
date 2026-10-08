import SwiftUI

struct ProfileRelationshipView: View {
  let profileID: UUID
  let account: AccountSession
  @State private var revision = UUID()
  @State private var state = ProfileRelationshipState()
  @State private var sendTask: Task<Void, Never>?
  @State private var sendTaskID: UUID?
  private var identity: ProfileRelationshipIdentity {
    .init(profileID: profileID, account: account, retryRevision: revision)
  }

  var body: some View {
    let request = identity
    ProfileRelationshipContent(status: state.displayedStatus(identity: request, account: account),
      isSending: state.request == request && state.isSending,
      refresh: { revision = UUID() }, send: { send(request) })
      .task(id: request) {
        await state.load(identity: request, account: account) {
          try await account.fetchProfileRelationship(identity: request)
        }
      }
      .onChange(of: request) { _, _ in cancelSendWait() }
      .onDisappear { cancelSendWait() }
  }
  private func send(_ request: ProfileRelationshipIdentity) {
    guard sendTask == nil else { return }
    let token = UUID(); sendTaskID = token
    sendTask = Task { @MainActor in
      defer { if sendTaskID == token { sendTask = nil; sendTaskID = nil } }
      await state.send(identity: request, account: account) {
        try await account.sendProfileConnection(identity: request)
      }
    }
  }
  private func cancelSendWait() {
    sendTask?.cancel(); sendTask = nil; sendTaskID = nil
  }
}

/// Production rendering without starting a relationship read or a write.
struct ProfileRelationshipContent: View {
  let status: ProfileRelationshipStatus
  let isSending: Bool
  let refresh: () -> Void
  let send: () -> Void

  var body: some View {
    VStack(spacing: 8) {
      switch status {
      case .unavailable:
        Text("登录后可查看与此用户的关系并发送好友请求。")
      case .loading:
        ProgressView("正在读取好友关系…").controlSize(.small)
      case .notConnected:
        Button(isSending ? "正在发送好友请求…" : "发送好友请求", action: send).disabled(isSending)
      case .outgoingRequest:
        Label("好友请求已发送，等待对方接受", systemImage: "clock")
      case .incomingRequest:
        Label("对方已发来好友请求，可到好友页接受或拒绝", systemImage: "person.badge.plus")
      case .friend:
        Label("你们已是好友", systemImage: "person.2.fill")
      case .blocked:
        Label("你已屏蔽此用户，可到好友页管理", systemImage: "person.crop.circle.badge.xmark")
      case .failed(let message):
        Text(message).textSelection(.enabled)
      }
      if status != .unavailable {
        Button("刷新好友关系", action: refresh).disabled(isSending || status == .loading)
      }
      if isSending {
        Text("关闭可取消等待，但服务端可能已收到请求；重新打开后请刷新确认。")
      }
    }
    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
  }
}
