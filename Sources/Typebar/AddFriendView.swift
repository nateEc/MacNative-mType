import SwiftUI

struct AddFriendView: View {
  let account: AccountSession
  let management: ConnectionsManagementState
  let read: ConnectionsReadIdentity
  let sent: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var retry = UUID()
  @State private var validation = FriendNameValidationState()
  @State private var submission: Task<Void, Never>?
  @State private var submissionID: UUID?
  private var checkID: FriendNameCheckID {
    .init(read: read, rawName: name, ownerName: account.currentUser?.displayName ?? "",
      snapshotReady: !management.isLoading && !management.isMutating
        && management.displayedSnapshot(request: read, account: account) != nil, retry: retry)
  }
  var body: some View {
    let id = checkID
    AddFriendForm(name: Binding(get: { name }, set: { validation.clear(); name = $0 }), status: validation.displayedStatus(id, account: account),
      isSubmitting: management.isMutating,
      canSubmit: submission == nil && validation.readyProfile(id, account: account, management: management) != nil,
      message: management.message,
      retry: { retry = UUID() }, submit: { submit(id) }, close: { dismiss() })
      .task(id: id) {
        await validation.check(id, account: account, management: management,
          debounce: { try await Task.sleep(for: .seconds(1)) },
          resolve: { try await account.resolveFriendName($0, identity: read.owner) })
      }
      .onDisappear { submission?.cancel(); submission = nil; submissionID = nil; validation.clear() }
  }
  private func submit(_ id: FriendNameCheckID) {
    guard submission == nil, let profile = validation.readyProfile(id, account: account, management: management) else { return }
    let token = UUID(); submissionID = token
    submission = Task { @MainActor in
      defer { if submissionID == token { submission = nil; submissionID = nil } }
      guard checkID == id, validation.readyProfile(id, account: account, management: management)?.id == profile.id else { return }
      let confirmed = await management.perform(.send(profile.id), request: read, account: account) {
        try await account.performConnectionsMutation(.send(profile.id), identity: read)
      }
      guard confirmed, read.owner.isCurrent(account) else { return }
      sent(); dismiss()
    }
  }
}

/// Account-free production form, mountable without credentials or networking.
struct AddFriendForm: View {
  @Binding var name: String
  let status: FriendNameStatus
  let isSubmitting: Bool
  let canSubmit: Bool
  let message: String?
  let retry: () -> Void
  let submit: () -> Void
  let close: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("添加好友", systemImage: "person.badge.plus").font(.title2)
      Text("按完整展示名查找，确认后发送好友请求。模糊搜索仍在好友页。")
        .font(.callout).foregroundStyle(.secondary)
      TextField("完整展示名", text: $name).textFieldStyle(.roundedBorder)
        .disabled(isSubmitting).onSubmit { if canSubmit { submit() } }
      Text(status.message).font(.callout).fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled).accessibilityLabel("名称校验：" + status.message)
      if case .checking = status { ProgressView().controlSize(.small) }
      if case .failed = status { Button("重新校验", action: retry).disabled(isSubmitting) }
      if isSubmitting {
        Text("正在发送。关闭只取消等待，服务端可能已收到；重新打开后请刷新确认。")
          .font(.caption).foregroundStyle(.secondary)
      } else if let message { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
      HStack {
        Button("关闭", action: close).keyboardShortcut(.cancelAction)
        Spacer()
        Button("发送请求", action: submit).keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent).disabled(!canSubmit || isSubmitting)
      }
    }.padding(24).frame(minWidth: 360, idealWidth: 440, maxWidth: 500, alignment: .leading)
  }
}
