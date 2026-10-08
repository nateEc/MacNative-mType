import SwiftUI

struct AccountProfileOverviewLoadID: Equatable {
  let scope: ResultPublicationScope?
  let sessionRevision: UInt64
  let revision: UUID
  let user: RemoteAccountUser?
  let lastResultID: UUID?
  @MainActor init(account: AccountSession, revision: UUID) {
    scope = account.resultPublicationScope
    sessionRevision = account.accountPersonalBestSessionRevision
    self.revision = revision
    user = account.currentUser
    lastResultID = account.lastAccountResult?.id
  }
}

enum AccountProfileLifetimePresentation {
  static func completion(_ profile: RemotePublicProfile) -> String {
    guard profile.startedTestCount > 0, profile.completedResultCount >= 0,
      profile.completedResultCount <= profile.startedTestCount else { return "未知" }
    return "\(Int(floor(Double(profile.completedResultCount) / Double(profile.startedTestCount) * 100)))%"
  }
  static func restartRatio(_ profile: RemotePublicProfile) -> String {
    guard profile.completedResultCount > 0, profile.startedTestCount >= profile.completedResultCount else { return "未知" }
    return AccountHistoryNumberPresentation.restartRatio(
      Double(profile.startedTestCount - profile.completedResultCount) / Double(profile.completedResultCount))
  }
  static func duration(_ seconds: Double) -> String {
    guard seconds.isFinite, (0...9_007_199_254_740_991).contains(seconds) else { return "未知" }
    let whole = Int(seconds.rounded())
    func padded(_ value: Int) -> String { value < 10 ? "0\(value)" : String(value) }
    return "\(padded(whole / 3600)):\(padded(whole / 60 % 60)):\(padded(whole % 60))"
  }
}

/// Account-wide snapshot, deliberately independent of loaded/filtered history.
struct AccountProfileOverviewView: View {
  let account: AccountSession
  let settings: AppSettings
  @Binding var revision: UUID
  @State private var loaded: (request: AccountProfileOverviewLoadID, profile: RemotePublicProfile)?
  @State private var failure: (request: AccountProfileOverviewLoadID, message: String)?
  private var loadID: AccountProfileOverviewLoadID { .init(account: account, revision: revision) }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("我的账户概览").font(.headline)
        Spacer()
        Button("刷新概览") { revision = UUID() }.disabled(loadID.scope == nil)
      }
      if loadID.scope == nil {
        Text("请先登录自建 Typebar 服务。")
          .font(.caption).foregroundStyle(.secondary)
      } else if let loaded, loaded.request == loadID {
        PublicProfileView(profile: loaded.profile, account: account, settings: settings, isAccountOverview: true)
      } else if let failure, failure.request == loadID {
        Text(failure.message).font(.caption).foregroundStyle(.secondary)
        Button("重试读取概览") { revision = UUID() }
      } else {
        ProgressView("正在读取账户累计资料…")
      }
      Divider()
    }
    .task(id: loadID) { await load() }
  }

  @MainActor private func load() async {
    let request = loadID
    loaded = nil; failure = nil
    guard let scope = request.scope else { return }
    do {
      let profile = try await account.fetchAccountProfileOverview(scope: scope)
      guard !Task.isCancelled, loadID == request else { return }
      loaded = (request, profile)
    } catch {
      guard !Task.isCancelled, loadID == request else { return }
      failure = (request, "账户概览读取失败，请重试；旧服务可能尚不支持此接口：" + error.localizedDescription)
    }
  }
}
