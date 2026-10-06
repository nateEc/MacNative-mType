import SwiftUI

struct AccountTagManagerView: View {
  let account: AccountSession
  @State private var draft = ""
  @State private var renamed = ""
  @State private var editing: RemoteAccountTag?
  @State private var pending: RemoteAccountTag?
  @State private var clearOnly = false
  @State private var selected = Set<UUID>()
  @State private var busy = false
  @State private var message: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("账户标签").font(.headline)
        Spacer()
        Button("刷新") { run { try await reload() } }
      }
      Text("最多 15 个稳定 ID 标签，与本机文字标签独立。测试完成时保存勾选的标签；之后改选不会改变已完成或待发成绩。显式历史编辑会检查服务端标签 PB，不重新奖励 XP。")
        .font(.caption).foregroundStyle(.secondary)
      if !account.hasAccountTagDirectory {
        Text("账户标签尚未加载；请刷新。").foregroundStyle(.secondary)
      } else if account.accountTags.isEmpty { Text("尚无账户标签；先添加一个标签。").foregroundStyle(.secondary) }
      ForEach(account.accountTags) { tag in
        VStack(alignment: .leading, spacing: 5) {
          HStack {
            Toggle(tag.displayName, isOn: Binding(get: { selected.contains(tag.id) }, set: { enabled in
              do {
                var updated = selected
                if enabled { updated.insert(tag.id) } else { updated.remove(tag.id) }
                try account.setAccountTagPostingSelection(updated.sorted { $0.uuidString < $1.uuidString })
                selected = updated
              } catch { message = error.localizedDescription }
            }))
            .accessibilityLabel("完成时捕获的标签 \(tag.displayName)，ID \(tag.id)")
            Button("重命名") { editing = tag; renamed = tag.displayName }
            Button("清 PB…", role: .destructive) { pending = tag; clearOnly = true }
            Button("删除…", role: .destructive) { pending = tag; clearOnly = false }
          }
          Text(tag.id.uuidString).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
          DisclosureGroup("标签个人最佳（\(tag.personalBests.count) 组）") {
            ForEach(tag.personalBests) { best in
              VStack(alignment: .leading, spacing: 2) {
                Text("\(best.mode) · \(best.configurationLabel) · \(best.language) · \(best.speedText) WPM")
                Text("\(best.groupingLabel) · Raw \(best.rawSpeedText ?? "未知") · 准确率 \(best.preciseAccuracy ?? Double(best.accuracy), format: .number.precision(.fractionLength(2)))% · 稳定度 \(best.consistency, format: .number.precision(.fractionLength(2)))%")
                  .font(.caption).foregroundStyle(.secondary)
                Text("接受 \(best.recordedAt.formatted(date: .abbreviated, time: .standard))")
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
      }
      HStack {
        TextField("新账户标签（1–16 字符）", text: $draft)
        Button("添加") { run { try await account.saveAccountTagName(id: nil, name: draft); draft = ""; selected = Set(try account.accountTagPostingSelection()) } }
          .disabled(account.accountTags.count >= 15 || !RemoteAccountTagPolicy.isValidName(RemoteAccountTagPolicy.normalizedName(draft)))
      }
      Text("英文字母、数字、单个空格／下划线／连字符；允许重名，ID 始终不同。")
        .font(.caption).foregroundStyle(.secondary)
      if let message = message ?? account.accountTagDirectoryMessage { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
    }
    .disabled(busy || account.currentUser == nil)
    .task(id: account.resultPublicationScope) {
      selected = []; message = nil; editing = nil; pending = nil
      do { try await reload() } catch { message = error.localizedDescription }
    }
    .alert("重命名账户标签", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
      TextField("标签名称", text: $renamed)
      Button("保存") { if let id = editing?.id { run { try await account.saveAccountTagName(id: id, name: renamed); selected = Set(try account.accountTagPostingSelection()) } }; editing = nil }
      Button("取消", role: .cancel) { editing = nil }
    } message: { Text("只修改名称，历史关联和标签 PB 的 ID 保持不变。") }
    .confirmationDialog(clearOnly ? "清空此标签的个人最佳？" : "删除此账户标签？",
      isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
        Button(clearOnly ? "清空标签 PB" : "删除标签", role: .destructive) {
          if let id = pending?.id { let clear = clearOnly; run { try await account.deleteAccountTag(id: id, personalBestsOnly: clear); selected = Set(try account.accountTagPostingSelection()) } }
          pending = nil
        }
      } message: {
        Text(clearOnly ? "此标签的 PB 将清空；历史和其他标签保留，旧成绩重试不恢复 PB。" : "此目录标签及其 PB 将移除；服务端成绩保留，不会转换成同名标签。")
      }
  }
  private func reload() async throws {
    guard account.currentUser != nil else { return }
    try await account.reloadAccountTags()
    selected = Set(try account.accountTagPostingSelection())
  }
  private func run(_ action: @escaping @MainActor () async throws -> Void) {
    busy = true; message = nil
    Task { defer { busy = false }; do { try await action() } catch { message = error.localizedDescription } }
  }
}

struct RemoteAccountResultTagPicker: View {
  let result: RemoteAccountResult
  let account: AccountSession
  @State private var message: String?
  @State private var busy = false
  private var knownIDs: Set<UUID> { Set(account.accountTags.map(\.id)) }
  var body: some View {
    DisclosureGroup("账户标签（\(Set(result.accountTagIDs ?? []).intersection(knownIDs).count) 个）") {
      ForEach(account.accountTags) { tag in
        Toggle("\(tag.displayName) · \(tag.id.uuidString.prefix(8))", isOn: Binding(
          get: { result.accountTagIDs?.contains(tag.id) == true },
          set: { enabled in
            guard !busy else { return }
            var ids = Set(result.accountTagIDs ?? []).intersection(knownIDs)
            if enabled { ids.insert(tag.id) } else { ids.remove(tag.id) }
            busy = true; message = nil
            Task { defer { busy = false }
              do { try await account.updateRemoteAccountResultTagIDs(id: result.id, tagIDs: ids.sorted { $0.uuidString < $1.uuidString }) }
              catch { message = error.localizedDescription } }
          }))
          .disabled(busy || account.isEditingAccountTags || !account.isAccountTagHistoryReady)
      }
      if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
      Text("按 ID 编辑并按已载入缓存重建本机标签 PB；服务端另检查是否授予标签 PB，不改变完成快照或 XP 回执。")
        .font(.caption).foregroundStyle(.secondary)
    }
  }
}
