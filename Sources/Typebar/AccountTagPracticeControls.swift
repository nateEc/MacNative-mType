import SwiftUI

/// One compact native row: IDs distinguish duplicate names; no copied theme,
/// glyph asset or local-text identity fallback.
struct AccountTagPracticeControls: View {
  let account: AccountSession
  let settings: AppSettings
  let configuration: TestConfiguration
  let hasStarted: Bool
  @State private var busy = false
  @State private var message: String?
  private var selected: [UUID] { (try? account.accountTagPostingSelection()) ?? [] }
  private var selectionError: String? {
    do { _ = try account.accountTagPostingSelection(); return nil }
    catch { return "标签选择无法读取：\(error.localizedDescription)；请重新选择，不会猜测旧 ID。" }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        Label("账户标签", systemImage: "tag").font(.headline)
        Spacer()
        Button("刷新账户标签") {
          busy = true
          Task { defer { busy = false }; await account.refreshAccountTagsForPractice() }
        }.disabled(busy)
      }
      Text("测试完成时捕获勾选的 ID；本机文字标签独立，改名或重名不改变身份。")
        .font(.caption).foregroundStyle(.secondary)
      if !account.hasAccountTagDirectory {
        Text("账户标签尚未加载，账户标签节奏暂不可用。请刷新；不会改用本机文字标签。")
          .font(.caption).foregroundStyle(.secondary)
      } else if account.accountTags.isEmpty {
        Text("此账户尚无标签，可在账户设置添加。").font(.caption).foregroundStyle(.secondary)
      } else {
        ScrollView(.horizontal) {
          HStack(spacing: 10) {
            ForEach(account.accountTags) { tag in
              Toggle("\(tag.displayName) · \(tag.id.uuidString.prefix(8))", isOn: Binding(
                get: { selected.contains(tag.id) }, set: { enabled in
                  var ids = Set(selected)
                  if enabled { ids.insert(tag.id) } else { ids.remove(tag.id) }
                  do {
                    try account.setAccountTagPostingSelection(ids.sorted { $0.uuidString < $1.uuidString })
                    message = nil
                  } catch { message = error.localizedDescription }
                }))
                .toggleStyle(.checkbox)
                .help("账户标签 ID：\(tag.id.uuidString)")
                .accessibilityLabel("账户标签 \(tag.displayName)，ID \(tag.id.uuidString)")
            }
          }
        }
      }
      Button("使用账户标签个人最佳节奏") { settings.paceGuideMode = .accountTagPersonalBest }
        .controlSize(.small)
      if settings.paceGuideMode == .accountTagPersonalBest {
        let target = account.hasAccountTagDirectory
          ? AccountTagPacePolicy.targetWpm(configuration: configuration, tags: account.accountTags, selectedIDs: selected) : nil
        Text(target.map { "当前勾选同类最高 PB：\($0.formatted(.number.precision(.fractionLength(0...2)))) WPM" }
          ?? "当前勾选暂无匹配的账户标签 PB；不会猜测未知分组选项。")
          .font(.caption).foregroundStyle(.secondary)
        if hasStarted {
          Text("切换节奏来源时初始化速度；之后改选影响完成标签及下一轮节奏，不改变已完成成绩。")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      if let error = selectionError ?? message ?? account.accountTagDirectoryMessage {
        Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      }
    }
    .padding(10)
    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
  }
}
