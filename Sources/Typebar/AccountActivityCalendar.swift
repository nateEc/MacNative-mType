import SwiftUI

struct RemoteAccountActivityYears: Codable, Sendable {
  let id: UUID
  let activityByYear: [String: [Int?]]
  let practiceHistoryComplete: Bool

  private enum CodingKeys: String, CodingKey { case id, activityByYear, practiceHistoryComplete }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    activityByYear = try values.decode([String: [Int?]].self, forKey: .activityByYear)
    practiceHistoryComplete = try values.decode(Bool.self, forKey: .practiceHistoryComplete)
    for (key, counts) in activityByYear {
      guard let year = Int(key), String(year) == key, (1970...9999).contains(year),
        let first = AccountActivityYearPolicy.utc.date(from: DateComponents(year: year, month: 1, day: 1)),
        let days = AccountActivityYearPolicy.utc.range(of: .day, in: .year, for: first), counts.count <= days.count,
        counts.compactMap({ $0 }).allSatisfy({ $0 >= 0 && Double($0) <= 9_007_199_254_740_991 })
      else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid annual activity")) }
    }
  }
}

enum AccountActivityYearPolicy {
  static var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }
  static func years(joinedAt: Date, now: Date = .now, calendar: Calendar = AccountActivityYearPolicy.utc) -> [Int] {
    guard joinedAt.timeIntervalSinceReferenceDate.isFinite, now.timeIntervalSinceReferenceDate.isFinite else { return [] }
    let start = max(1970, calendar.component(.year, from: joinedAt))
    let end = min(9999, calendar.component(.year, from: now))
    guard start <= end else { return [] }
    return Array((start...end).reversed())
  }
  static func activity(year: Int, from response: RemoteAccountActivityYears) -> RemotePublicProfileActivity? {
    guard let counts = response.activityByYear[String(year)], !counts.isEmpty,
      let first = utc.date(from: DateComponents(year: year, month: 1, day: 1)),
      let range = utc.range(of: .day, in: .year, for: first),
      let last = utc.date(byAdding: .day, value: range.count - 1, to: first) else { return nil }
    return .init(lastDay: last, testsByDays: counts + Array(repeating: nil, count: range.count - counts.count))
  }
  static func currentYearActivity(_ activity: RemotePublicProfileActivity?, year: Int) -> RemotePublicProfileActivity? {
    guard let activity, (1970...9999).contains(year),
      let first = utc.date(from: DateComponents(year: year, month: 1, day: 1)),
      let range = utc.range(of: .day, in: .year, for: first),
      let last = utc.date(byAdding: .day, value: range.count - 1, to: first) else { return nil }
    var counts = Array<Int?>(repeating: nil, count: range.count)
    if utc.component(.year, from: activity.lastDay) == year,
      let ordinal = utc.ordinality(of: .day, in: .year, for: activity.lastDay) {
      for (index, count) in activity.testsByDays.enumerated() {
        let dayIndex = ordinal - activity.testsByDays.count + index
        if counts.indices.contains(dayIndex) { counts[dayIndex] = count }
      }
    }
    return .init(lastDay: last, testsByDays: counts)
  }
}

enum ProfileActivityCalendarPresentation {
  static func levels(_ counts: [Int?]) -> [Int] {
    let sorted = counts.compactMap { $0 }.sorted()
    guard !sorted.isEmpty else { return counts.map { _ in 0 } }
    let trim = Int((Double(sorted.count) * 0.1).rounded())
    let values = sorted[trim..<(sorted.count - trim)]
    let mean = values.reduce(0.0) { $0 + Double($1) } / Double(values.count)
    let thresholds = [(mean / 2).rounded(.down), mean.rounded(), (mean * 1.5).rounded()]
    return counts.map { count in
      guard let count, count > 0 else { return 0 }
      return thresholds.firstIndex(where: { Double(count) <= $0 }).map { $0 + 1 } ?? 4
    }
  }
}

struct AccountActivityYearContent: View {
  let response: RemoteAccountActivityYears
  let year: Int
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let activity = AccountActivityYearPolicy.activity(year: year, from: response) {
        PublicProfileActivityCalendar(activity: activity, isAccountOverview: true, periodLabel: "\(year) 年")
      } else { Text("\(String(year)) 年没有已保存的活动。") }
      if !response.practiceHistoryComplete {
        Text("旧账户仅保留可确认活动，空白不代表历史完整。")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct AccountActivityYearKey: Equatable {
  let scope: ResultPublicationScope?
  let sessionRevision: UInt64
  let profileID: UUID
  let completedCount: Int
  let revision: UUID
  @MainActor init(account: AccountSession, profileID: UUID, completedCount: Int, revision: UUID) {
    scope = account.resultPublicationScope
    sessionRevision = account.accountPersonalBestSessionRevision
    self.profileID = profileID; self.completedCount = completedCount; self.revision = revision
  }
  @MainActor func isCurrent(_ account: AccountSession) -> Bool {
    scope?.userID == profileID && scope == account.resultPublicationScope
      && sessionRevision == account.accountPersonalBestSessionRevision
  }
}

struct AccountActivityYearRequest: Equatable {
  let key: AccountActivityYearKey
  let year: Int?
  let currentYear: Int
  init(key: AccountActivityYearKey, year: Int?, now: Date = .now) {
    self.key = key; self.year = year
    currentYear = AccountActivityYearPolicy.utc.component(.year, from: now)
  }
  var usesSnapshot: Bool { year == nil || year == currentYear }
}

@MainActor @Observable final class AccountActivityYearLoader {
  private(set) var loaded: (key: AccountActivityYearKey, response: RemoteAccountActivityYears)?
  private(set) var failure: (request: AccountActivityYearRequest, message: String)?
  private var generation = UUID()

  func load(_ request: AccountActivityYearRequest, account: AccountSession,
    fetch: () async throws -> RemoteAccountActivityYears) async {
    let generation = UUID(); self.generation = generation
    failure = nil
    guard request.key.isCurrent(account), let scope = request.key.scope else { loaded = nil; return }
    guard !request.usesSnapshot else { return }
    guard loaded?.key != request.key else { return }
    loaded = nil
    do {
      let response = try await account.loadAccountActivityYears(scope: scope, load: fetch)
      guard !Task.isCancelled, self.generation == generation, request.key.isCurrent(account) else { return }
      loaded = (request.key, response)
    } catch {
      guard !Task.isCancelled, self.generation == generation, request.key.isCurrent(account) else { return }
      failure = (request, "年度活动读取失败，请重试；旧服务可能尚不支持：" + error.localizedDescription)
    }
  }
}

struct AccountActivityCalendarView: View {
  let profile: RemotePublicProfile
  let account: AccountSession
  @State private var selectedYear: Int?
  @State private var revision = UUID()
  @State private var loader = AccountActivityYearLoader()
  private var request: AccountActivityYearRequest {
    .init(key: .init(account: account, profileID: profile.id,
      completedCount: profile.completedResultCount, revision: revision), year: selectedYear)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Picker("活动年份", selection: $selectedYear) {
          Text("近 12 个月").tag(Int?.none)
          ForEach(AccountActivityYearPolicy.years(joinedAt: profile.joinedAt), id: \.self) { year in
            Text(String(year)).tag(Optional(year))
          }
        }
        .frame(maxWidth: 260)
        if !request.usesSnapshot { Button("刷新年度活动") { revision = UUID() } }
      }
      if !request.key.isCurrent(account) {
        Text("请重新登录后读取自己的活动。")
      } else if let year = selectedYear {
        if year == request.currentYear {
          if let activity = AccountActivityYearPolicy.currentYearActivity(profile.activity, year: year) {
            PublicProfileActivityCalendar(activity: activity, isAccountOverview: true, periodLabel: "\(year) 年")
          } else { Text("\(String(year)) 年没有已保存的活动。") }
        } else if let loaded = loader.loaded, loaded.key == request.key {
          AccountActivityYearContent(response: loaded.response, year: year)
        } else if let failure = loader.failure, failure.request == request {
          Text(failure.message).font(.caption).foregroundStyle(.secondary)
          Button("重试年度活动") { revision = UUID() }
        } else { ProgressView("正在读取年度活动…") }
      } else if let activity = profile.activity {
        PublicProfileActivityCalendar(activity: activity, isAccountOverview: true)
      } else { Text("近 12 个月没有已保存的活动。") }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .task(id: request) {
      let request = request
      await loader.load(request, account: account) {
        guard let scope = request.key.scope else { throw RemoteAccountError.accountScopeChanged }
        return try await account.fetchAccountActivityYears(scope: scope)
      }
    }
  }
}
