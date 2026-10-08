import AppKit
import SwiftUI

/// One horizontal comparison surface; no separate account store or requests.
struct FriendComparisonView: View {
  let snapshot: ConnectionsSnapshot
  let unit: TypingSpeedUnit
  let openProfile: (RemotePublicProfile) -> Void
  let actions: (RemotePublicProfile) -> AnyView
  @AppStorage("friends.comparison.sort.v1") private var storedSort = "[]"
  @State private var expandedBest: UUID?

  var body: some View {
    let sorting = FriendComparisonSort.decode(storedSort)
    let rows = FriendComparisonPolicy.rows(snapshot, sort: sorting)
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("速度单位：\(unit.displayName) · 点列名排序，Shift 点选添加次级排序")
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("恢复默认顺序") { storedSort = "[]" }.disabled(sorting.isEmpty)
      }
      if snapshot.ownerProfile == nil {
        Text("此服务未提供本人对照数据；好友管理仍可使用。").font(.caption).foregroundStyle(.secondary)
      }
      ScrollView(.horizontal) {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .top, spacing: 12) {
            ForEach(FriendComparisonColumn.allCases, id: \.self) { column in
              Button {
                storedSort = FriendComparisonSort.encode(FriendComparisonSort.toggled(sorting, column: column,
                  adding: NSEvent.modifierFlags.contains(.shift)))
              } label: {
                Text(column.title + sortLabel(column, sorting: sorting)).font(.caption.weight(.semibold))
                  .frame(width: column.width, alignment: .leading)
              }.buttonStyle(.plain).help("排序：\(column.title)。Shift 点选保留其他排序列。")
            }
            Text("操作").font(.caption).frame(width: 160, alignment: .leading)
          }
          Divider()
          ForEach(rows) { row in
            comparison(row)
            Divider()
          }
        }.fixedSize(horizontal: true, vertical: false).padding(.bottom, 8)
      }
      if rows.contains(where: { !$0.hasStatistics || $0.profile.practiceHistoryComplete == false || $0.profile.personalBestHistoryComplete != true }) {
        Text("部分统计或 PB 只有旧历史基线；“—”表示未提供，不能据此断言全生命周期纪录完整。")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func sortLabel(_ column: FriendComparisonColumn, sorting: [FriendComparisonSort]) -> String {
    guard let index = sorting.firstIndex(where: { $0.column == column }) else { return "" }
    return " \(sorting[index].descending ? "↓" : "↑")\(sorting.count > 1 ? String(index + 1) : "")"
  }

  private func comparison(_ row: FriendComparisonRow) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Button { openProfile(row.profile) } label: {
        HStack(alignment: .top, spacing: 6) {
          if let url = row.profile.discordAvatar?.cdnURL {
            SharedProfileAvatarImage(url: url).frame(width: 24, height: 24).clipShape(Circle())
          }
          VStack(alignment: .leading, spacing: 4) {
            Text(row.profile.displayName + (row.isOwner ? "（我）" : "")).lineLimit(2)
            if let badge = row.profile.selectedBadge { Label(badge.title, systemImage: badge.systemImage).font(.caption2) }
            if row.profile.accountSuspended { Text("账户已暂停").font(.caption2) }
            if row.profile.leaderboardOptedOut == true { Text("未参加排行榜").font(.caption2) }
          }
        }.frame(width: FriendComparisonColumn.name.width, alignment: .leading)
      }.buttonStyle(.link).help("打开 \(row.profile.displayName) 的完整公开资料")
      Group {
        if let date = row.connectedAt { Text(date, style: .relative).help(date.formatted(date: .complete, time: .shortened)) }
        else { Text("—") }
      }.frame(width: 100, alignment: .leading)
      Text(row.level.map(String.init) ?? "—").frame(width: 100, alignment: .leading)
        .help(row.hasStatistics ? "累计 \(row.profile.totalExperience) XP" : "服务未提供等级数据")
      Text(row.hasStatistics ? "\(row.profile.completedResultCount)／\(row.profile.startedTestCount)" : "—")
        .frame(width: 100, alignment: .leading)
        .help(row.hasStatistics ? FriendComparisonPolicy.ratio(completed: row.profile.completedResultCount, started: row.profile.startedTestCount) : "服务未提供累计统计")
      Text(row.hasStatistics ? AccountProfileLifetimePresentation.duration(row.profile.totalTypingSeconds) : "—")
        .frame(width: 100, alignment: .leading)
      Text(FriendComparisonPolicy.streak(row.profile.streak?.currentDays)).frame(width: 100, alignment: .leading)
        .help("最长连续：" + FriendComparisonPolicy.streak(row.profile.streak?.longestDays))
      best(row.best(seconds: 15))
      best(row.best(seconds: 60))
      Group {
        if row.isOwner { Text("本人对照").foregroundStyle(.secondary) }
        else { actions(row.profile) }
      }.frame(width: 160, alignment: .leading)
    }.font(.callout.monospacedDigit())
  }
  private func best(_ best: RemotePublicProfileBest?) -> some View {
    Group {
      if let best {
        Button { expandedBest = best.id } label: {
          VStack(alignment: .leading, spacing: 3) {
            Text(PublicProfilePersonalBestPresentation.speed(best.effectiveWpm, unit: unit, decimals: true))
            Text(PublicProfilePersonalBestPresentation.percentage(best.preciseAccuracy ?? Double(best.accuracy), decimals: true))
              .font(.caption).foregroundStyle(.secondary)
          }
        }.buttonStyle(.plain).help("查看语言、Raw、准确率、稳定度和日期")
        .popover(isPresented: Binding(get: { expandedBest == best.id }, set: { if !$0 { expandedBest = nil } })) {
          VStack(alignment: .leading, spacing: 8) {
            Text(best.languageLabel).font(.headline)
            Text("速度 \(PublicProfilePersonalBestPresentation.speed(best.effectiveWpm, unit: unit, decimals: true)) \(unit.displayName)")
            Text("Raw \(PublicProfilePersonalBestPresentation.speed(best.preciseRawWpm ?? best.rawWpm.map(Double.init), unit: unit, decimals: true))")
            Text("准确率 \(PublicProfilePersonalBestPresentation.percentage(best.preciseAccuracy ?? Double(best.accuracy), decimals: true))")
            Text("稳定度 \(PublicProfilePersonalBestPresentation.percentage(best.consistency, decimals: true))")
            Text(best.recordedAt, format: .dateTime.year().month().day())
            Text(best.groupingLabel).font(.caption).foregroundStyle(.secondary)
          }.padding(16).textSelection(.enabled)
        }
      } else { Text("—").foregroundStyle(.secondary) }
    }.frame(width: 135, alignment: .leading)
  }
}
