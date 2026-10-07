import Foundation
import SwiftUI

/// A view of accepted PB snapshots, never a recomputation from result history.
enum AccountPersonalBestTablePolicy {
  struct Row: Identifiable {
    let best: RemotePublicProfileBest
    let isGroupStart: Bool
    let sourceIndex: Int
    var id: String { "\(best.groupKey)/\(sourceIndex)" }
  }

  static func rows(_ profile: RemotePublicProfile, mode: TestMode) -> [Row] {
    let input = profile.displayPersonalBests.enumerated().filter { $0.element.mode == mode.rawValue }
    var keys: [String] = []
    var groups: [String: [(offset: Int, element: RemotePublicProfileBest)]] = [:]
    for item in input {
      let best = item.element
      let explicitParameter = best.mode == "time" ? best.durationSeconds : best.mode == "words" ? best.wordLimit : nil
      let key = best.mode2 ?? explicitParameter.map(String.init) ?? best.configurationLabel
      if groups[key] == nil { keys.append(key) }
      groups[key, default: []].append(item)
    }
    // JavaScript object integer keys precede other keys; preserve insertion
    // order for unknown and very large mode parameters rather than guessing.
    let integerKeys = keys.compactMap { key -> (String, UInt32)? in
      guard let value = UInt32(key), value != UInt32.max, String(value) == key else { return nil }
      return (key, value)
    }.sorted { $0.1 < $1.1 }.map(\.0)
    let numeric = Set(integerKeys)
    return (integerKeys + keys.filter { !numeric.contains($0) }).flatMap { key in
      (groups[key] ?? []).sorted {
        $0.element.effectiveWpm == $1.element.effectiveWpm ? $0.offset < $1.offset
          : $0.element.effectiveWpm > $1.element.effectiveWpm
      }.enumerated().map { index, item in
        Row(best: item.element, isGroupStart: index == 0, sourceIndex: item.offset)
      }
    }
  }

  static func coverageNotice(_ profile: RemotePublicProfile) -> String {
    if profile.personalBestLedgerVersion == nil {
      return "旧服务只提供标准档摘要；这不是完整个人最佳账本，缺失选项保持未知。"
    }
    if profile.personalBestHistoryComplete == false {
      return "旧账本仅恢复迁移时可确认的基线；已删除的旧纪录无法补回。"
    }
    return "读取当前账户独立个人最佳账本；删除成绩历史不会删除这些纪录。"
  }
}

/// The actual SwiftUI task identity is testable without opening a window.
struct AccountPersonalBestTableLoadID: Equatable {
  let scope: ResultPublicationScope?
  let revision: UUID
  let sessionRevision: UInt64
  @MainActor init(account: AccountSession, revision: UUID) {
    scope = account.resultPublicationScope; self.revision = revision
    sessionRevision = account.accountPersonalBestSessionRevision
  }
}

struct AccountPersonalBestTableView: View {
  let account: AccountSession
  let settings: AppSettings
  @Environment(\.dismiss) private var dismiss
  @State private var mode = TestMode.time
  @State private var revision = UUID()
  @State private var loaded: (request: AccountPersonalBestTableLoadID, profile: RemotePublicProfile)?
  @State private var message: String?
  @State private var isLoading = false
  private var loadID: AccountPersonalBestTableLoadID { .init(account: account, revision: revision) }
  private var profile: RemotePublicProfile? {
    loaded?.request == loadID ? loaded?.profile : nil
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          Picker("测试类型", selection: $mode) {
            ForEach([TestMode.time, .words, .custom, .zen], id: \.self) { Text($0.displayName).tag($0) }
          }.pickerStyle(.segmented)
          Text("账户纪录与这台 Mac 的个人最佳、已载入成绩和标签 PB 分开；只读，不修改纪录或设置。")
            .font(.caption).foregroundStyle(.secondary)
          if let profile {
            Text(profile.displayName).font(.headline)
            Text(AccountPersonalBestTablePolicy.coverageNotice(profile))
              .font(.caption).foregroundStyle(.secondary)
          }
        }
        if isLoading { ProgressView("正在读取账户个人最佳…") }
        if let message { Text(message).foregroundStyle(.secondary) }
        if let profile {
          let rows = AccountPersonalBestTablePolicy.rows(profile, mode: mode)
          if rows.isEmpty {
            ContentUnavailableView("没有\(mode.displayName)个人最佳", systemImage: "trophy",
              description: Text("此服务响应没有该模式的纪录；不会从本机或成绩历史补造。"))
          } else {
            ForEach(rows) { row in
              VStack(alignment: .leading, spacing: 6) {
                if row.isGroupStart { Text(row.best.configurationLabel).font(.headline) }
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                  VStack(alignment: .leading, spacing: 3) {
                    Text("\(number(row.best.effectiveWpm, speed: true)) \(settings.typingSpeedUnit.displayName)")
                      .font(.title3.monospacedDigit())
                    Text("Raw \(number(row.best.preciseRawWpm ?? row.best.rawWpm.map(Double.init), speed: true)) · 准确率 \(number(row.best.preciseAccuracy ?? Double(row.best.accuracy)))% · 稳定度 \(number(row.best.consistency))%")
                      .font(.caption.monospacedDigit())
                  }
                  Spacer()
                  VStack(alignment: .trailing, spacing: 3) {
                    Text(row.best.languageLabel)
                    Text(row.best.groupingLabel)
                    Text(row.best.recordedAt, format: .dateTime.year().month().day().hour().minute())
                    if row.best.personalBestOrigin == "legacyHistory" { Text("旧历史基线") }
                  }.font(.caption).foregroundStyle(.secondary)
                }
              }.padding(.vertical, 4).textSelection(.enabled)
                .accessibilityElement(children: .combine)
            }
          }
        } else if !isLoading, account.resultPublicationScope == nil {
          ContentUnavailableView("请先登录账户", systemImage: "person.crop.circle")
        }
      }
      .navigationTitle("账户个人最佳表")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
        ToolbarItem { Button("刷新") { revision = UUID() }.disabled(isLoading || account.resultPublicationScope == nil) }
      }
    }
    .frame(minWidth: 760, idealWidth: 850, minHeight: 420, idealHeight: 620)
    .task(id: loadID) { await load() }
  }

  private func number(_ value: Double?, speed: Bool = false) -> String {
    AccountHistoryNumberPresentation.text(value, unit: speed ? settings.typingSpeedUnit : nil,
      decimals: settings.alwaysShowDecimalPlaces)
  }

  @MainActor private func load() async {
    let request = loadID
    loaded = nil; message = nil; isLoading = false
    guard let scope = request.scope else { return }
    isLoading = true
    defer { if loadID == request { isLoading = false } }
    do {
      let profile = try await account.fetchAccountPersonalBestProfile(scope: scope)
      guard !Task.isCancelled, loadID == request else { return }
      loaded = (request, profile)
    } catch {
      guard !Task.isCancelled, loadID == request else { return }
      message = "读取失败，请刷新重试：" + error.localizedDescription
    }
  }
}
