import Foundation
import SwiftData
import SwiftUI

/// One numeric best snapshot for a non-quote configuration.
struct LocalPersonalBestRow: Codable, Equatable, Identifiable {
  let id: UUID
  let mode: TestMode
  let parameter: Int
  let wpm: Double
  let rawWpm: Double
  let accuracy: Double
  let consistency: Double
  let difficulty: Difficulty
  let language: TypingLanguage
  let includesPunctuation: Bool
  let includesNumbers: Bool
  let usesLazyLatin: Bool
  let finishedAt: Date

  var parameterLabel: String {
    switch mode {
    case .time: parameter == 0 ? "无限时" : "\(parameter) 秒"
    case .words: parameter == 0 ? "无限词" : "\(parameter) 词"
    case .zen, .custom: mode.displayName
    case .quote: ""
    }
  }

  var optionsLabel: String {
    var options: [String] = []
    if includesPunctuation { options.append("标点") }
    if includesNumbers { options.append("数字") }
    if usesLazyLatin { options.append("简化重音") }
    return options.isEmpty ? "标准输入" : options.joined(separator: " · ")
  }
}

/// Legacy history projection retained for compatibility checks. Production
/// consumers read the independent ledger, not this deletable-history view.
enum LocalPersonalBestTablePolicy {
  static func rows(results: [CompletedTestResult]) -> [LocalPersonalBestRow] {
    var bestByConfiguration: [ConfigurationKey: CompletedTestResult] = [:]
    for result in results {
      guard result.outcome == .completed,
        CurrentPersonalBestPolicy.isResultEligible(
          configuration: result.configuration, accuracy: result.preciseAccuracy),
        let key = ConfigurationKey(result.configuration)
      else { continue }

      guard let current = bestByConfiguration[key] else {
        bestByConfiguration[key] = result
        continue
      }
      if isBetter(result, than: current) {
        bestByConfiguration[key] = result
      }
    }

    return bestByConfiguration.values.map(makeRow).sorted {
      if $0.mode != $1.mode { return $0.mode.rawValue < $1.mode.rawValue }
      if $0.parameter != $1.parameter { return $0.parameter < $1.parameter }
      if $0.wpm != $1.wpm { return $0.wpm > $1.wpm }
      if $0.finishedAt != $1.finishedAt { return $0.finishedAt < $1.finishedAt }
      return $0.id.uuidString < $1.id.uuidString
    }
  }

  private struct ConfigurationKey: Hashable {
    let mode: TestMode
    let parameter: Int
    let language: TypingLanguage
    let difficulty: Difficulty
    let includesPunctuation: Bool
    let includesNumbers: Bool
    let usesLazyLatin: Bool

    init?(_ configuration: TestConfiguration) {
      switch configuration.mode {
      case .time:
        guard let duration = configuration.duration, duration.isFinite, duration >= 0,
          duration < Double(Int.max), duration.rounded(.towardZero) == duration else { return nil }
        mode = .time
        parameter = Int(duration)
      case .words:
        guard let wordLimit = configuration.wordLimit, wordLimit >= 0 else { return nil }
        mode = .words
        parameter = wordLimit
      case .zen, .custom:
        mode = configuration.mode
        parameter = 0
      case .quote: return nil
      }
      language = configuration.language
      difficulty = configuration.difficulty
      includesPunctuation = configuration.contentOptions.includePunctuation
      includesNumbers = configuration.contentOptions.includeNumbers
      usesLazyLatin = configuration.modifiers.contains(.lazyLatin)
    }
  }

  private static func isBetter(_ candidate: CompletedTestResult, than current: CompletedTestResult) -> Bool {
    if candidate.preciseWpm != current.preciseWpm { return candidate.preciseWpm > current.preciseWpm }
    if candidate.finishedAt != current.finishedAt { return candidate.finishedAt < current.finishedAt }
    return candidate.id.uuidString < current.id.uuidString
  }

  private static func makeRow(_ result: CompletedTestResult) -> LocalPersonalBestRow {
    let configuration = result.configuration
    let consistency = ResultConsistencyPolicy.metrics(
      events: result.replayEvents, duration: result.chartDuration,
      configuration: result.configuration, keySpacingSamples: result.keySpacingSamples).typing
    return .init(
      id: result.id, mode: configuration.mode,
      parameter: ConfigurationKey(configuration)?.parameter ?? 0,
      wpm: result.preciseWpm, rawWpm: result.preciseRawWpm, accuracy: result.preciseAccuracy,
      consistency: consistency, difficulty: configuration.difficulty, language: configuration.language,
      includesPunctuation: configuration.contentOptions.includePunctuation,
      includesNumbers: configuration.contentOptions.includeNumbers,
      usesLazyLatin: configuration.modifiers.contains(.lazyLatin), finishedAt: result.finishedAt)
  }
}

struct LocalPersonalBestTableView: View {
  @Environment(\.dismiss) private var dismiss
  @Query private var ledgers: [LocalPersonalBestLedgerRecord]
  @State private var selectedMode: TestMode = .time
  let speedUnit: TypingSpeedUnit
  let alwaysShowDecimalPlaces: Bool

  private var rows: [LocalPersonalBestRow] {
    (ledgers.first?.ledger?.entries.map(\.row) ?? []).sorted {
      if $0.parameter != $1.parameter { return $0.parameter < $1.parameter }
      if $0.wpm != $1.wpm { return $0.wpm > $1.wpm }
      return $0.id.uuidString < $1.id.uuidString
    }
      .filter { $0.mode == selectedMode }
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          Picker("测试类型", selection: $selectedMode) {
            Text(TestMode.time.displayName).tag(TestMode.time)
            Text(TestMode.words.displayName).tag(TestMode.words)
            Text(TestMode.custom.displayName).tag(TestMode.custom)
            Text(TestMode.zen.displayName).tag(TestMode.zen)
          }
          .pickerStyle(.segmented)
          Text("只显示这台 Mac 的个人最佳；删除历史不会删除纪录，不读取账户或网络数据。")
            .font(.caption)
            .foregroundStyle(.secondary)
          if ledgers.first?.ledger?.historyComplete == false {
            Text("旧历史或导入仅恢复可用基线，已删除的旧纪录无法恢复。")
              .font(.caption).foregroundStyle(.secondary)
          }
        }

        if ledgers.first?.ledger == nil {
          ContentUnavailableView("个人最佳账本不可用", systemImage: "exclamationmark.triangle",
            description: Text("请备份数据库后修复；不会用历史覆盖损坏账本。"))
        } else if rows.isEmpty {
          ContentUnavailableView(
            "还没有可用的个人最佳", systemImage: "trophy",
            description: Text("完成符合条件的\(selectedMode.displayName)练习后会显示在这里。"))
        } else {
          Section("\(selectedMode.displayName)个人最佳") {
            ForEach(rows) { row in
              HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(row.parameterLabel)
                  .font(.headline)
                  .frame(width: 56, alignment: .trailing)
                VStack(alignment: .leading, spacing: 3) {
                  Text(
                    "\(speedUnit.formatted(wpm: row.wpm, alwaysShowDecimalPlaces: alwaysShowDecimalPlaces)) \(speedUnit.displayName) · \(ResultMetricPresentation.accuracy(row.accuracy, alwaysShowDecimalPlaces: alwaysShowDecimalPlaces))"
                  )
                  Text(
                    "Raw \(speedUnit.formatted(wpm: row.rawWpm, alwaysShowDecimalPlaces: alwaysShowDecimalPlaces)) · \(row.consistency.formatted(.number.precision(.fractionLength(0))))% 稳定"
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                  Text("\(row.language.displayName) · \(row.difficulty.displayName)")
                  Text(row.optionsLabel)
                  let snapshot = ledgers.first?.ledger?.entries.first { $0.row.id == row.id }
                  Text(snapshot?.recordedAt ?? row.finishedAt, format: .dateTime.year().month().day())
                  if snapshot?.recordedAt == nil { Text("旧历史日期") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
              }
            }
          }
        }
      }
      .navigationTitle("个人最佳表")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("完成") { dismiss() }
        }
      }
    }
    .frame(minWidth: 680, minHeight: 420)
  }
}
