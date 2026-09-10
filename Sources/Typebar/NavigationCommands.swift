import SwiftUI

enum NavigationCommandTarget: CaseIterable, Equatable {
  case typingPage
  case leaderboards
  case about
  case settings
  case account
  case profileSearch
  case fullscreen

  var identifier: String {
    switch self {
    case .typingPage: "viewTypingPage"
    case .leaderboards: "viewLeaderboards"
    case .about: "viewAbout"
    case .settings: "viewSettings"
    case .account: "viewAccount"
    case .profileSearch: "searchProfile"
    case .fullscreen: "toggleFullscreen"
    }
  }
}

enum NavigationCommandCatalog {
  static let items = NavigationCommandTarget.allCases.map { target in
    item(for: target)
  }

  static func target(for identifier: String) -> NavigationCommandTarget? {
    NavigationCommandTarget.allCases.first { $0.identifier == identifier }
  }

  private static func item(for target: NavigationCommandTarget) -> CommandPaletteItem {
    let presentation: (String, String, String, [String]) = switch target {
    case .typingPage:
      ("回到打字练习", "关闭命令并把输入焦点交还练习区", "keyboard", ["start", "type", "test", "练习", "主页"])
    case .leaderboards:
      ("打开排行榜", "查看自建服务上的速度与经验榜", "crown", ["leaderboard", "rank", "榜单", "排名"])
    case .about:
      ("打开关于 Typebar", "查看版本、隐私边界和项目链接", "info.circle", ["about", "version", "关于", "版本"])
    case .settings:
      ("打开设置", "调整练习、外观与本机行为", "gearshape", ["settings", "preferences", "设置", "偏好"])
    case .account:
      ("打开账户设置", "登录或管理自建 Typebar 服务账户", "person.crop.circle", ["account", "login", "账户", "登录"])
    case .profileSearch:
      ("搜索公开资料", "按展示名查找自建服务上的用户", "person.text.rectangle", ["profile", "user", "search", "资料", "用户", "搜索"])
    case .fullscreen:
      ("切换全屏", "让当前 Typebar 练习窗口进入或退出全屏", "arrow.up.left.and.arrow.down.right", ["fullscreen", "window", "全屏", "窗口"])
    }
    return CommandPaletteItem(
      id: target.identifier, title: presentation.0, subtitle: presentation.1,
      systemImage: presentation.2, keywords: [target.identifier] + presentation.3,
      group: .navigation)
  }
}

enum ProfileSearchCommandPolicy {
  static func normalized(_ rawValue: String) -> String? {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (2...40).contains(value.count),
      value.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil
    else { return nil }
    return value
  }
}

struct ProfileSearchCommandView: View {
  @Environment(\.dismiss) private var dismiss
  let account: AccountSession
  @State private var query = ""
  @State private var results: [RemotePublicProfile] = []
  @State private var isSearching = false
  @State private var message: String?
  @State private var selectedProfile: RemotePublicProfile?
  @FocusState private var inputFocused: Bool

  private var normalizedQuery: String? { ProfileSearchCommandPolicy.normalized(query) }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Form {
          Section("公开展示名") {
            TextField("输入 2–40 个字符", text: $query)
              .focused($inputFocused)
            if !query.isEmpty, normalizedQuery == nil {
              Text("展示名需为 2–40 个字符，且不能包含换行。")
                .foregroundStyle(.red)
            }
          }
          Section {
            Text("搜索会请求你已连接的自建 Typebar 服务；查询内容不会发往其他服务。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .formStyle(.grouped)
        if isSearching {
          ProgressView().padding()
        } else if results.isEmpty {
          ContentUnavailableView(
            message ?? "输入公开展示名开始搜索", systemImage: "person.text.rectangle")
        } else {
          List(results) { profile in
            Button {
              selectedProfile = profile
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 3) {
                  Text(profile.displayName)
                  Text("最佳 \(profile.bestWPM) WPM · \(profile.completedResultCount) 次完成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
              }
            }
            .buttonStyle(.plain)
          }
          .listStyle(.plain)
        }
      }
      .navigationTitle("搜索公开资料")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
            .keyboardShortcut(.cancelAction)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("搜索", action: search)
          .keyboardShortcut(.defaultAction)
          .disabled(normalizedQuery == nil)
        }
      }
    }
    .frame(width: 520, height: 440)
    .onAppear { inputFocused = true }
    .sheet(item: $selectedProfile) { profile in
      PublicProfileView(profile: profile, account: account)
    }
  }

  private func search() {
    guard let normalizedQuery else { return }
    Task {
      isSearching = true
      defer { isSearching = false }
      do {
        results = try await account.searchPublicProfiles(query: normalizedQuery)
        message = results.isEmpty ? "没有匹配的公开资料" : nil
      } catch {
        results = []
        message = error.localizedDescription
      }
    }
  }
}
