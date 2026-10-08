import SwiftUI

struct AccountProfileEditIdentity: Hashable {
  let scope: ResultPublicationScope?
  let sessionRevision: UInt64

  @MainActor init(account: AccountSession) {
    scope = account.resultPublicationScope
    sessionRevision = account.accountPersonalBestSessionRevision
  }

  @MainActor func isCurrent(_ account: AccountSession) -> Bool {
    scope != nil && self == Self(account: account)
  }
}

/// A local draft; unrelated account refreshes must not discard unsaved typing.
struct AccountProfileDraft: Equatable {
  var bio: String
  var keyboard: String
  var github: String
  var socialHandle: String
  var websiteURL: String
  var showActivity: Bool
  var showDiscordAvatar: Bool
  var selectedBadgeID: String

  init(user: RemoteAccountUser) {
    let details = user.profileDetails
    bio = details.bio; keyboard = details.keyboard; github = details.github
    socialHandle = details.socialHandle; websiteURL = details.websiteURL
    showActivity = details.showActivity; showDiscordAvatar = details.showDiscordAvatar
    selectedBadgeID = user.selectedBadgeID ?? ""
  }

  var details: RemoteProfileDetails {
    .init(bio: bio, keyboard: keyboard, github: github, socialHandle: socialHandle,
      websiteURL: websiteURL, showActivity: showActivity, showDiscordAvatar: showDiscordAvatar)
  }

  func canSave(for user: RemoteAccountUser) -> Bool {
    !user.accountSuspended && bio.count <= 250 && keyboard.count <= 75
      && github.count <= 39 && socialHandle.count <= 15 && websiteURL.count <= 200
      && (selectedBadgeID.isEmpty || user.availableBadges.contains { $0.id == selectedBadgeID })
  }
}

struct AccountProfileBadgePresentation {
  let selected: RemotePublicProfileBadge?
  let additional: [RemotePublicProfileBadge]
  let isPrivateInventory: Bool

  init(profile: RemotePublicProfile, isAccountOverview: Bool, user: RemoteAccountUser?) {
    if isAccountOverview, let user, user.id == profile.id {
      isPrivateInventory = true
      selected = user.availableBadges.first { $0.id == user.selectedBadgeID }
      additional = PublicBadgeDisclosurePolicy.additionalBadges(
        earnedBadges: user.availableBadges, selectedBadge: selected)
    } else {
      isPrivateInventory = false
      selected = profile.selectedBadge
      additional = PublicBadgeDisclosurePolicy.additionalBadges(
        earnedBadges: profile.earnedBadges, selectedBadge: selected)
    }
  }
}

struct AccountProfileEditor: View {
  let account: AccountSession
  let identity: AccountProfileEditIdentity
  var didSave: () -> Void = {}
  @State private var draft: AccountProfileDraft
  @State private var message: String?
  @State private var saveTask: Task<Void, Never>?
  @State private var badgeTask: Task<Void, Never>?

  init(account: AccountSession, user: RemoteAccountUser, identity: AccountProfileEditIdentity,
    didSave: @escaping () -> Void = {}) {
    self.account = account; self.identity = identity; self.didSave = didSave
    _draft = State(initialValue: .init(user: user))
  }

  var body: some View {
    Group {
      if identity.isCurrent(account), let user = account.currentUser {
        fields(user: user)
      } else {
        Text("账户或服务器已切换，请重新打开编辑器；旧草稿不会提交。")
          .foregroundStyle(.secondary)
      }
    }
    .onDisappear { saveTask?.cancel(); badgeTask?.cancel() }
  }

  private func fields(user: RemoteAccountUser) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      Text("公开资料").font(.headline)
      Text("名称与 Discord 头像关联可在设置 → 自建账户中更改。")
        .font(.caption).foregroundStyle(.secondary)
      Text("简介").font(.caption).foregroundStyle(.secondary)
      TextEditor(text: $draft.bio)
        .font(.body)
        .frame(height: 80)
        .accessibilityLabel("简介，最多 250 个字符")
        .overlay(alignment: .topLeading) {
          if draft.bio.isEmpty {
            Text("简介（可选，最多 250 个字符）")
              .foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.vertical, 8)
              .allowsHitTesting(false)
          }
        }
      HStack {
        Spacer()
        Text("\(draft.bio.count)/250").font(.caption.monospacedDigit())
          .foregroundStyle(draft.bio.count > 250 ? Color.red : Color.secondary)
      }
      profileField("键盘", prompt: "使用的键盘或布局（可选，最多 75 个字符）", text: $draft.keyboard)
      profileField("GitHub", prompt: "GitHub 用户名（可选）", text: $draft.github)
      profileField("X / Twitter", prompt: "X / Twitter 用户名（可选）", text: $draft.socialHandle)
      VStack(alignment: .leading, spacing: 4) {
        Text("个人网站").font(.caption).foregroundStyle(.secondary)
        TextField("https://（可选）", text: $draft.websiteURL)
          .textContentType(.URL).accessibilityLabel("个人网站")
      }
      Toggle("在公开资料显示活动日历", isOn: $draft.showActivity)
      Text("此选项只隐藏访客看到的日历；本人的活动、累计统计与连续天数不受影响。")
        .font(.caption).foregroundStyle(.secondary)
      if user.authenticationMethods.contains(.discord) {
        Toggle("在公开资料显示 Discord 头像", isOn: $draft.showDiscordAvatar)
      } else {
        Text("关联 Discord 后，可选择在公开资料显示该账户的头像。")
          .font(.caption).foregroundStyle(.secondary)
      }
      Picker("公开资料徽章", selection: $draft.selectedBadgeID) {
        Text("不显示").tag("")
        ForEach(user.availableBadges) { badge in
          Label(badge.title, systemImage: badge.systemImage).tag(badge.id)
        }
      }
      Toggle("公开显示全部已获得徽章", isOn: Binding(
        get: { user.showAllBadges }, set: { value in updateBadgeDisclosure(value) }))
        .disabled(user.availableBadges.isEmpty)
      Text(user.availableBadges.isEmpty
        ? "完成并同步服务端接受的练习后，可在这里选择公开展示的原创徽章。"
        : "此开关立即保存，其他字段需点击更新。关闭时访客只看到选定的一枚；本人仍可查看全部徽章，排行榜只显示选定的一枚。")
        .font(.caption).foregroundStyle(.secondary)
      Button("更新公开资料") { save() }
        .disabled(!draft.canSave(for: user))
      if saveTask != nil || badgeTask != nil { ProgressView("正在更新资料…").controlSize(.small) }
      if let message {
        Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      }
      if user.accountSuspended {
        Label("此账户已被封禁，不能更改公开资料。", systemImage: "lock.shield")
          .font(.caption).foregroundStyle(.secondary)
      }
      Text("简介、键盘说明与链接会公开；邮箱、令牌和本机练习内容不公开。")
        .font(.caption).foregroundStyle(.secondary)
    }
    .disabled(account.isWorking || user.accountSuspended)
  }

  private func profileField(_ label: String, prompt: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      TextField(prompt, text: text).accessibilityLabel(label)
    }
  }

  @MainActor private func save() {
    guard saveTask == nil, identity.isCurrent(account), let user = account.currentUser,
      draft.canSave(for: user), !account.isWorking else { return }
    let submitted = draft
    saveTask = Task { @MainActor in
      defer { saveTask = nil }
      let saved = await account.updateProfileDetails(submitted.details,
        selectedBadgeID: submitted.selectedBadgeID, identity: identity)
      guard !Task.isCancelled, identity.isCurrent(account) else { return }
      message = account.statusMessage
      if saved, let user = account.currentUser {
        draft = .init(user: user)
        didSave()
      }
    }
  }

  @MainActor private func updateBadgeDisclosure(_ value: Bool) {
    guard badgeTask == nil, identity.isCurrent(account), !account.isWorking else { return }
    badgeTask = Task { @MainActor in
      defer { badgeTask = nil }
      _ = await account.setShowAllBadges(value, identity: identity)
      guard !Task.isCancelled, identity.isCurrent(account) else { return }
      message = account.statusMessage // Do not reload or erase the other unsaved fields.
    }
  }
}

struct AccountProfileEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  let account: AccountSession
  let identity: AccountProfileEditIdentity

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("编辑资料").font(.title2.weight(.semibold))
        Spacer()
        Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      ScrollView {
        if identity.isCurrent(account), let user = account.currentUser {
          AccountProfileEditor(account: account, user: user, identity: identity) { dismiss() }
        } else {
          Text("账户或服务器已切换，请重新打开编辑器。")
        }
      }
    }
    .padding(24).frame(width: 480, height: 650)
    .onChange(of: AccountProfileEditIdentity(account: account)) { _, value in
      if value != identity { dismiss() }
    }
  }
}
