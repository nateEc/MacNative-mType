import SwiftUI

struct ProfileLevelProgressView: View {
  let totalXP: Int
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let progress = ProfileLevelProgress(totalXP: totalXP) {
        HStack {
          Text("等级 \(progress.level)").font(.headline)
          Spacer()
          Text(progress.percentText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        ProgressView(value: progress.fraction)
          .accessibilityLabel("当前等级进度").accessibilityValue(progress.percentText)
        Text("\(ExperiencePresentation.compact(progress.earnedXP)) / \(ExperiencePresentation.compact(progress.requiredXP)) XP · 距下一等级 \(ExperiencePresentation.compact(progress.remainingXP)) XP")
          .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        DisclosureGroup("等级详情") {
          VStack(alignment: .leading, spacing: 4) {
            Text("总经验：\(String(progress.totalXP)) XP")
            Text("当前等级已获得：\(String(progress.earnedXP)) XP")
            Text("完成当前等级需要：\(String(progress.requiredXP)) XP")
            Text("距离下一等级：\(String(progress.remainingXP)) XP")
          }.font(.caption.monospacedDigit()).frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        Label("等级暂不可用", systemImage: "questionmark.circle")
        Text("服务返回的总 XP 超出可验证范围；不会补造等级。").font(.caption).foregroundStyle(.secondary)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct AccountStreakClaimView: View {
  let claim: RemoteAccountStreakClaim?
  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      AccountStreakClaimContent(claim: claim, now: context.date)
    }
  }
}

/// The actual production content is mountable with an isolated, fixed clock.
struct AccountStreakClaimContent: View {
  let claim: RemoteAccountStreakClaim?
  let now: Date
  private var presentation: AccountStreakClaimPresentation { .init(claim: claim, now: now) }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(presentation.heading, systemImage: presentation.status == .expired ? "flame" : "calendar")
        .font(.subheadline.weight(.medium))
      if let saved = presentation.hasSavedToday {
        Text("本连续日已保存成绩：\(saved ? "是" : "否")").font(.caption)
      }
      switch presentation.status {
      case .unavailable:
        Text("服务未提供可验证的本人连续状态；可刷新概览或检查服务版本。")
      case .clockMismatch:
        Text("记录时间晚于设备时间，请校准时钟并刷新概览；暂不推断是否领取。")
      case .noSavedResult:
        Text("保存一局成绩后开始记录连续天数；未发布的本机练习不会记入服务账户。")
      case .claimed:
        if let boundary = presentation.nextBoundaryMilliseconds {
          Text("下个连续日开始于 \(remaining(until: boundary)) 后。")
        }
      case .available:
        if let boundary = presentation.nextBoundaryMilliseconds {
          Text("请在 \(remaining(until: boundary)) 内保存成绩，以延续连续记录。")
        }
      case .expired:
        if let lostAt = presentation.lostAtMilliseconds {
          Text("已过期 \(AccountStreakClaimPresentation.duration(milliseconds: now.timeIntervalSince1970 * 1000 - lostAt))；现有连续天数会在下次保存成绩时更新。")
        }
      }
      if presentation.referenceDiffersFromLastSave {
        Text("连续参考时间与最后保存时刻不同；设置日界线也会更新时间，但不代表保存了成绩。")
      }
      if presentation.status != .unavailable && presentation.status != .clockMismatch {
        Text("连续日界线：UTC 00:00 \(offsetText) 小时；活动日历仍按 UTC。")
        if presentation.offsetHours == nil {
          Text("尚未设置个人日界线；可在账户设置中选择，只有一次设置机会。")
        }
      }
    }
    .font(.caption).foregroundStyle(.secondary)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
  private var offsetText: String {
    let offset = presentation.offsetHours ?? 0
    return (offset >= 0 ? "+" : "") + offset.formatted(.number.precision(.fractionLength(0...1)))
  }
  private func remaining(until milliseconds: Double) -> String {
    AccountStreakClaimPresentation.duration(milliseconds: milliseconds - now.timeIntervalSince1970 * 1000)
  }
}
