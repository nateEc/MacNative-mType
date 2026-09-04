import Observation
import SwiftUI

/// Public, deployment-owned information displayed as plain native text. It
/// intentionally has no account, prompt, or device fields.
enum RemoteAnnouncementLevel: String, CaseIterable, Codable, Identifiable, Sendable {
  case notice
  case success
  case warning

  var id: Self { self }

  var displayName: String {
    switch self {
    case .notice: "提示"
    case .success: "已更新"
    case .warning: "注意"
    }
  }

  var systemImage: String {
    switch self {
    case .notice: "megaphone"
    case .success: "checkmark.seal"
    case .warning: "exclamationmark.triangle"
    }
  }

  var tint: Color {
    switch self {
    case .notice: .secondary
    case .success: .green
    case .warning: .orange
    }
  }
}

struct RemoteAnnouncement: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let message: String
  let level: RemoteAnnouncementLevel
  let sticky: Bool
  let scheduledAt: Date?
  let publishedAt: Date

  init(
    id: UUID, message: String, level: RemoteAnnouncementLevel, sticky: Bool,
    scheduledAt: Date? = nil, publishedAt: Date
  ) {
    self.id = id
    self.message = message
    self.level = level
    self.sticky = sticky
    self.scheduledAt = scheduledAt
    self.publishedAt = publishedAt
  }

  func renderedMessage(
    at date: Date = .now, locale: Locale = .current, timeZone: TimeZone = .current
  ) -> String {
    guard let scheduledAt else { return message }
    let dateTime = dateText(for: scheduledAt, dateStyle: .medium, timeStyle: .short, locale: locale, timeZone: timeZone)
    let dateOnly = dateText(for: scheduledAt, dateStyle: .medium, timeStyle: .none, locale: locale, timeZone: timeZone)
    let relativeFormatter = RelativeDateTimeFormatter()
    relativeFormatter.locale = locale
    let relative = relativeFormatter.localizedString(for: scheduledAt, relativeTo: date)
    return message
      .replacingOccurrences(of: "{dateDifference}", with: relative)
      .replacingOccurrences(of: "{dateNoTime}", with: dateOnly)
      .replacingOccurrences(of: "{date}", with: dateTime)
  }

  private func dateText(
    for date: Date, dateStyle: DateFormatter.Style, timeStyle: DateFormatter.Style,
    locale: Locale, timeZone: TimeZone
  ) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.dateStyle = dateStyle
    formatter.timeStyle = timeStyle
    return formatter.string(from: date)
  }
}

struct RemoteAnnouncementPublicationRequest: Codable, Sendable {
  let message: String
  let level: RemoteAnnouncementLevel
  let sticky: Bool
  let scheduledAt: Date?

  init(
    message: String, level: RemoteAnnouncementLevel, sticky: Bool, scheduledAt: Date? = nil
  ) {
    self.message = message
    self.level = level
    self.sticky = sticky
    self.scheduledAt = scheduledAt
  }
}

struct RemoteAnnouncementsResponse: Codable, Sendable {
  let announcements: [RemoteAnnouncement]
}

/// Local acknowledgement behavior mirrors the user-visible announcement
/// contract: ordinary messages can be closed on this Mac, while sticky
/// messages remain until the deployment removes them. No acknowledgement is
/// sent to the server.
@MainActor
@Observable
final class RemoteAnnouncementCenter {
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let acknowledgementKey = "remoteAnnouncements.dismissed.v1"
  private var dismissedIDs: Set<UUID>

  private(set) var announcements: [RemoteAnnouncement] = []
  private(set) var isRefreshing = false

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    dismissedIDs = Set(
      (defaults.stringArray(forKey: acknowledgementKey) ?? []).compactMap(UUID.init(uuidString:)))
  }

  var visibleAnnouncements: [RemoteAnnouncement] {
    announcements.filter { $0.sticky || !dismissedIDs.contains($0.id) }
  }

  func refresh(using account: AccountSession) async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    do {
      replace(with: try await account.publicAnnouncements())
    } catch {
      // Announcements are supplementary. A network failure must never block
      // offline typing or discard a previously displayed message.
    }
  }

  func replace(with latest: [RemoteAnnouncement]) {
    announcements = latest.sorted {
      $0.publishedAt == $1.publishedAt ? $0.id.uuidString > $1.id.uuidString : $0.publishedAt > $1.publishedAt
    }
    let liveIDs = Set(announcements.map(\.id))
    if announcements.isEmpty {
      dismissedIDs = []
    } else {
      dismissedIDs.formIntersection(liveIDs)
    }
    persistAcknowledgements()
  }

  func dismiss(_ announcement: RemoteAnnouncement) {
    guard !announcement.sticky else { return }
    dismissedIDs.insert(announcement.id)
    persistAcknowledgements()
  }

  private func persistAcknowledgements() {
    defaults.set(dismissedIDs.map(\.uuidString).sorted(), forKey: acknowledgementKey)
  }
}

struct RemoteAnnouncementBannerStack: View {
  let center: RemoteAnnouncementCenter

  var body: some View {
    ForEach(center.visibleAnnouncements) { announcement in
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Image(systemName: announcement.level.systemImage)
          .foregroundStyle(announcement.level.tint)
          .accessibilityHidden(true)
        Text(announcement.renderedMessage())
          .font(.callout)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        if !announcement.sticky {
          Button("关闭", systemImage: "xmark") { center.dismiss(announcement) }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .accessibilityLabel("关闭公告")
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(announcement.level.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
      .accessibilityElement(children: .combine)
    }
  }
}
