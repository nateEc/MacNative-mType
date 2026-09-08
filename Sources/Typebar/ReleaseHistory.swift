import SwiftUI

struct TypebarRelease: Equatable, Identifiable, Sendable {
  let title: String
  let tag: String
  let notes: String
  let publishedAt: Date?
  let pageURL: URL

  var id: String { tag }
}

struct ReleaseHistoryPage: Equatable, Sendable {
  let releases: [TypebarRelease]
  let hasMore: Bool
}

enum ReleaseHistoryError: LocalizedError {
  case invalidEndpoint
  case unexpectedResponse
  case requestFailed(Int)

  var errorDescription: String? {
    switch self {
    case .invalidEndpoint: "无法创建版本历史请求。"
    case .unexpectedResponse: "GitHub 返回了无法识别的响应。"
    case .requestFailed(let statusCode): "GitHub 请求失败（HTTP \(statusCode)）。"
    }
  }
}

enum ReleaseHistoryCatalog {
  private struct Payload: Decodable {
    let name: String?
    let tag: String
    let body: String?
    let pageURL: URL
    let isDraft: Bool
    let isPrerelease: Bool
    let publishedAt: String?

    enum CodingKeys: String, CodingKey {
      case name, body, draft, prerelease
      case tag = "tag_name"
      case pageURL = "html_url"
      case publishedAt = "published_at"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      name = try container.decodeIfPresent(String.self, forKey: .name)
      tag = try container.decode(String.self, forKey: .tag)
      body = try container.decodeIfPresent(String.self, forKey: .body)
      pageURL = try container.decode(URL.self, forKey: .pageURL)
      isDraft = try container.decode(Bool.self, forKey: .draft)
      isPrerelease = try container.decode(Bool.self, forKey: .prerelease)
      publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt)
    }
  }

  static func endpoint(page: Int, pageSize: Int) -> URL? {
    guard page > 0, (1...100).contains(pageSize) else { return nil }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.github.com"
    components.path = "/repos/nateEc/MacNative-mType/releases"
    components.queryItems = [
      URLQueryItem(name: "page", value: String(page)),
      URLQueryItem(name: "per_page", value: String(pageSize)),
    ]
    return components.url
  }

  static func decode(_ data: Data, pageSize: Int) throws -> ReleaseHistoryPage {
    let payloads = try JSONDecoder().decode([Payload].self, from: data)
    let releases = payloads.compactMap { payload -> TypebarRelease? in
      guard !payload.isDraft, !payload.isPrerelease else { return nil }
      let tag = payload.tag.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !tag.isEmpty, isTypebarReleaseURL(payload.pageURL) else { return nil }
      let name = payload.name?.trimmingCharacters(in: .whitespacesAndNewlines)
      let body = payload.body?.trimmingCharacters(in: .whitespacesAndNewlines)
      return TypebarRelease(
        title: name.flatMap { $0.isEmpty ? nil : $0 } ?? tag,
        tag: tag,
        notes: body.flatMap { $0.isEmpty ? nil : $0 } ?? "没有提供发布说明。",
        publishedAt: payload.publishedAt.flatMap(parseDate),
        pageURL: payload.pageURL)
    }
    return ReleaseHistoryPage(releases: releases, hasMore: payloads.count == pageSize)
  }

  static func load(page: Int, pageSize: Int) async throws -> ReleaseHistoryPage {
    guard let url = endpoint(page: page, pageSize: pageSize) else {
      throw ReleaseHistoryError.invalidEndpoint
    }
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("Typebar-macOS", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw ReleaseHistoryError.unexpectedResponse
    }
    guard response.statusCode == 200 else {
      throw ReleaseHistoryError.requestFailed(response.statusCode)
    }
    return try decode(data, pageSize: pageSize)
  }

  private static func parseDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }

  private static func isTypebarReleaseURL(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "https"
      && url.host?.lowercased() == "github.com"
      && url.path.lowercased().hasPrefix("/nateec/macnative-mtype/releases/")
  }
}

enum ReleaseHistoryCommand {
  static let identifier = "release-history"
  static let item = CommandPaletteItem(
    id: identifier,
    title: "版本历史",
    subtitle: "查看 Typebar 的正式发布与更新说明",
    systemImage: "clock.arrow.circlepath",
    keywords: ["release", "changelog", "version history", "版本历史", "更新日志", "发布"],
    group: .settings)
}

struct ReleaseHistoryView: View {
  private static let pageSize = 20

  @State private var releases: [TypebarRelease] = []
  @State private var nextPage = 1
  @State private var canLoadMore = true
  @State private var isLoading = false
  @State private var errorMessage: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        header
        if releases.isEmpty, !isLoading, errorMessage == nil {
          emptyState
        } else {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(releases) { release in
              releaseRow(release)
            }
          }
        }
        footer
      }
      .padding(.horizontal, 38)
      .padding(.vertical, 34)
    }
    .frame(width: 680, height: 700)
    .background(ReleaseHistoryPalette.paper)
    .foregroundStyle(ReleaseHistoryPalette.ink)
    .task {
      if releases.isEmpty { await loadNextPage() }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("TYPEBAR / RELEASE TAPE")
        .font(.caption.monospaced().weight(.semibold))
        .tracking(1.8)
        .foregroundStyle(ReleaseHistoryPalette.amber)
      Text("版本历史")
        .font(.system(size: 38, weight: .bold, design: .rounded))
      Text("这里仅列出 Typebar 自己的正式 GitHub 发布。打开此窗口时才会联网读取；练习功能不依赖它。")
        .font(.callout)
        .foregroundStyle(ReleaseHistoryPalette.fog)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.bottom, 28)
  }

  private func releaseRow(_ release: TypebarRelease) -> some View {
    HStack(alignment: .top, spacing: 18) {
      VStack(spacing: 0) {
        Rectangle()
          .fill(ReleaseHistoryPalette.amber)
          .frame(width: 10, height: 10)
        Rectangle()
          .fill(ReleaseHistoryPalette.rule)
          .frame(width: 2)
      }
      .frame(width: 12)

      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text(release.title)
            .font(.title3.weight(.semibold))
          Spacer(minLength: 16)
          Text(release.tag)
            .font(.caption.monospaced().weight(.medium))
            .foregroundStyle(ReleaseHistoryPalette.amber)
        }
        if let publishedAt = release.publishedAt {
          Text(publishedAt, format: .dateTime.year().month(.abbreviated).day())
            .font(.caption.monospaced())
            .foregroundStyle(ReleaseHistoryPalette.fog)
        }
        Text(release.notes)
          .font(.body)
          .lineSpacing(4)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
        Link("在 GitHub 查看此发布", destination: release.pageURL)
          .font(.callout.weight(.medium))
      }
      .padding(.bottom, 30)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var emptyState: some View {
    ContentUnavailableView(
      "还没有正式发布",
      systemImage: "shippingbox",
      description: Text("创建第一个 GitHub Release 后，它会显示在这里。"))
      .frame(maxWidth: .infinity)
      .padding(.vertical, 56)
  }

  @ViewBuilder
  private var footer: some View {
    if isLoading {
      HStack(spacing: 10) {
        ProgressView().controlSize(.small)
        Text("正在读取发布记录…")
      }
      .font(.callout)
      .foregroundStyle(ReleaseHistoryPalette.fog)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 18)
    } else if let errorMessage {
      VStack(spacing: 10) {
        Text(errorMessage)
          .font(.callout)
          .foregroundStyle(ReleaseHistoryPalette.fog)
        Button("重试") { Task { await loadNextPage() } }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 18)
    } else if canLoadMore {
      Button("读取更早的发布") { Task { await loadNextPage() } }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
  }

  @MainActor
  private func loadNextPage() async {
    guard !isLoading, canLoadMore else { return }
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      let page = try await ReleaseHistoryCatalog.load(
        page: nextPage, pageSize: Self.pageSize)
      let existingTags = Set(releases.map(\.tag))
      releases.append(contentsOf: page.releases.filter { !existingTags.contains($0.tag) })
      nextPage += 1
      canLoadMore = page.hasMore
    } catch {
      errorMessage = "无法读取版本历史。请检查网络连接后重试。"
    }
  }
}

private enum ReleaseHistoryPalette {
  static let paper = Color(red: 0.961, green: 0.949, blue: 0.922)
  static let ink = Color(red: 0.125, green: 0.141, blue: 0.165)
  static let amber = Color(red: 0.847, green: 0.537, blue: 0.169)
  static let fog = Color(red: 0.443, green: 0.467, blue: 0.502)
  static let rule = Color(red: 0.851, green: 0.827, blue: 0.780)
}
