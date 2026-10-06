import SwiftUI

struct AccountTagHistoryFilterControls: View {
  let account: AccountSession
  @Binding var filter: ResultHistoryAccountTagFilter?
  var usesCompletionSnapshots = true

  private var canSelect: Bool {
    account.hasAccountTagDirectory && (filter == nil || filter?.scope == account.resultPublicationScope)
  }

  var body: some View {
    DisclosureGroup("账户标签：\(filter?.selectionSummary ?? "不限")") {
      HStack {
        Button("不限账户标签") { filter = nil }
        Button("全选") { selectAll() }.disabled(!canSelect)
        Button("全不选") { selectAll(); filter?.selectedIDs = []; filter?.includesNoTags = false }
          .disabled(!canSelect)
      }
      if let filter, filter.scope != account.resultPublicationScope {
        Text("此预设属于另一账户或服务器。切回原账户，或取消账户标签筛选。")
          .font(.caption).foregroundStyle(.secondary)
      } else if !account.hasAccountTagDirectory {
        Text("登录并在账户设置刷新标签后可筛选；未知关联不会归入无账户标签。")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Toggle("无账户标签", isOn: choice(nil)).toggleStyle(.checkbox)
        ForEach(account.accountTags) { tag in
          Toggle("\(tag.displayName) · \(tag.id.uuidString.prefix(8))", isOn: choice(tag.id))
            .toggleStyle(.checkbox)
            .help("账户标签 ID：\(tag.id.uuidString)")
            .accessibilityLabel("账户标签 \(tag.displayName)，ID \(tag.id.uuidString)")
        }
      }
      if filter != nil {
        Text(usesCompletionSnapshots
          ? "按当前账户的已确认关联筛选；尚未载入的记录使用同账户完成快照。本机文字标签独立筛选。"
          : "只筛选当前账户已载入的服务端关联，不读取本机完成快照。文字标签独立筛选。")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func selectAll() {
    guard canSelect, let scope = account.resultPublicationScope else { return }
    let known = Set(account.accountTags.map(\.id))
    filter = .init(scope: scope, knownIDs: known, selectedIDs: known, includesNoTags: true)
  }

  private func choice(_ id: UUID?) -> Binding<Bool> {
    Binding(get: {
      guard let filter else { return true }
      return id.map(filter.selectedIDs.contains) ?? filter.includesNoTags
    }, set: { selected in
      guard canSelect else { return }
      if filter == nil { selectAll() }
      if let id {
        if selected { filter?.selectedIDs.insert(id) } else { filter?.selectedIDs.remove(id) }
      } else { filter?.includesNoTags = selected }
    })
  }
}
