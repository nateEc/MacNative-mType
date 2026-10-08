import SwiftUI

/// Reward delivery is separate from the social notification feed.
struct RewardInboxView: View {
  @Environment(\.dismiss) private var dismiss
  let account: AccountSession
  @State private var mails: [RemoteRewardMail] = []
  @State private var maxMail: Int?
  @State private var isLoading = false
  @State private var message: String?
  @State private var confirmingDeleteAll = false
  @State private var operationID = UUID()

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 12) {
        if account.currentUser == nil {
          ContentUnavailableView("请先登录", systemImage: "tray", description: Text("登录自建 Typebar 服务后可领取练习奖励。"))
        } else {
          HStack {
            Text(maxMail.map { "\(mails.count) / \($0) 封" } ?? "奖励邮件")
            Spacer()
            Text("\(RewardInboxPresentation.claimable(mails).count) 封待领取")
          }
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .padding(.horizontal)
          if mails.isEmpty {
            ContentUnavailableView("没有奖励邮件", systemImage: "tray",
              description: Text("奖励送达后不会自动入账，请在这里领取。"))
          } else {
            List(RewardInboxPresentation.ordered(mails)) { mail in
              VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                  Text(mail.subject).font(.headline)
                  Spacer()
                  Text(mail.statusLabel).font(.caption)
                    .foregroundStyle(mail.unclaimed ? Color.accentColor : Color.secondary)
                }
                Text(mail.body).font(.body).textSelection(.enabled)
                if !mail.rewards.isEmpty {
                  Text(mail.rewards.map(\.label).joined(separator:" · "))
                    .font(.system(.callout,design:.monospaced).weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                }
                HStack {
                  Text(mail.date,format:.dateTime.year().month().day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
                  Spacer()
                  if mail.unclaimed {
                    Button("领取奖励") { update(.init(mailIdsToMarkRead:[mail.id])) }
                      .accessibilityLabel("领取 \(mail.subject) 的奖励")
                  } else {
                    Button("删除邮件",role:.destructive) { update(.init(mailIdsToDelete:[mail.id])) }
                      .accessibilityLabel("删除 \(mail.subject)")
                  }
                }
                .buttonStyle(.borderless)
              }
              .padding(.vertical,8)
            }
            .disabled(isLoading)
          }
          if maxMail == 0 {
            Text("此服务的收件箱容量为零，新奖励邮件不会保留。")
              .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
          } else if let maxMail, mails.count >= maxMail {
            Text("收件箱已满。新邮件会挤掉最旧邮件，未领取奖励不会自动入账。")
              .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
          }
        }
        HStack {
          if isLoading { ProgressView().controlSize(.small); Text("正在更新…") }
          else if let message { Text(message).textSelection(.enabled) }
          Spacer()
        }
        .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
      }
      .padding(.vertical,12)
      .navigationTitle("奖励收件箱")
      .toolbar {
        ToolbarItem(placement:.primaryAction) {
          Button("刷新") { Task { await load() } }.disabled(isLoading || account.currentUser == nil)
        }
        ToolbarItem(placement:.primaryAction) {
          if !RewardInboxPresentation.claimable(mails).isEmpty {
            Button("全部领取") { update(.init(mailIdsToMarkRead:RewardInboxPresentation.claimable(mails))) }
              .disabled(isLoading)
          } else {
            Button("全部删除",role:.destructive) { confirmingDeleteAll = true }
              .disabled(isLoading || mails.isEmpty)
          }
        }
        ToolbarItem(placement:.cancellationAction) { Button("完成") { dismiss() } }
      }
    }
    .frame(minWidth:480,minHeight:380)
    .task(id:account.resultPublicationScope) {
      operationID = UUID(); mails = []; maxMail = nil; message = nil; isLoading = false
      confirmingDeleteAll = false
      if account.currentUser != nil { await load() }
    }
    .onDisappear { operationID = UUID() }
    .overlay(alignment: .topTrailing) { LocalNoticeStack(center: account.localNotices, focused: false).padding(12) }
    .confirmationDialog("删除全部邮件？",isPresented:$confirmingDeleteAll,titleVisibility:.visible) {
      Button("删除全部邮件",role:.destructive) {
        let ids = RewardInboxPresentation.deletable(mails)
        if !ids.isEmpty { update(.init(mailIdsToDelete:ids)) }
      }
      Button("取消",role:.cancel) {}
    } message: { Text("只清空当前账户的邮件，不会扣除已领取 XP 或移除已领取徽章。") }
  }

  private func load() async {
    guard !isLoading else { return }
    let operation = UUID(), scope = account.resultPublicationScope
    operationID = operation; isLoading = true
    defer { if operationID == operation { isLoading = false } }
    do {
      let response = try await account.rewardInbox()
      guard operationID == operation, RewardInboxScopePolicy.accepts(requested:scope,current:account.resultPublicationScope) else { return }
      mails = response.inbox; maxMail = response.maxMail; message = nil
    } catch {
      if operationID == operation, account.resultPublicationScope == scope {
        message = error.localizedDescription
        account.localNotices.post("无法读取奖励收件箱，请重试。", level: .error)
      }
    }
  }
  private func update(_ request: RemoteRewardInboxUpdate) {
    guard !isLoading else { return }
    let operation = UUID(), scope = account.resultPublicationScope
    let badgeNames = RewardInboxPresentation.badgeNamesToClaim(mails, request: request)
    operationID = operation; isLoading = true
    Task {
      defer { if operationID == operation { isLoading = false } }
      do {
        let response = try await account.updateRewardInbox(request)
        guard operationID == operation, RewardInboxScopePolicy.accepts(requested:scope,current:account.resultPublicationScope) else { return }
        mails = response.inbox; maxMail = response.maxMail; message = "收件箱已更新。"
        if !badgeNames.isEmpty {
          account.localNotices.post("已领取徽章：" + badgeNames.joined(separator: "、"), level: .success,
            options: .init(durationMilliseconds: 5000, title: "奖励", systemImage: "gift"))
        }
      } catch {
        if operationID == operation, account.resultPublicationScope == scope {
          message = error.localizedDescription
          account.localNotices.post("奖励收件箱操作未确认，请刷新后核对。", level: .error)
        }
      }
    }
  }
}
