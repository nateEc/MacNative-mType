import Foundation
import SwiftData
import SwiftUI

/// One locally stored best result for a time or word-count configuration.
struct LocalPersonalBestRow: Equatable, Identifiable {
  let id: UUID
  let mode: TestMode
  let parameter: Int
  let wpm: Int
  let rawWpm: Int
  let accuracy: Int
  let consistency: Double
  let difficulty: Difficulty
  let language: TypingLanguage
  let includesPunctuation: Bool
  let includesNumbers: Bool
  let usesLazyLatin: Bool
  let finishedAt: Date

  var parameterLabel: String {
    switch mode {
    case .time: "\(parameter) 秒"
    case .words: "\(parameter) 词"
    case .quote, .zen, .custom: ""
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

/// Builds a local equivalent of the personal-best table from completed results.
/// It uses the same comparison fields as the practice-screen PB indicator.
enum LocalPersonalBestTablePolicy {
  static func rows(results: [CompletedTestResult]) -> [LocalPersonalBestRow] {
    var bestByConfiguration: [ConfigurationKey: CompletedTestResult] = [:]
    for result in results {
      guard result.outcome == .completed,
        CurrentPersonalBestPolicy.isResultEligible(
          configuration: result.configuration, accuracy: result.accuracy),
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
        guard let duration = configuration.duration, duration > 0 else { return nil }
        mode = .time
        parameter = Int(duration)
      case .words:
        guard let wordLimit = configuration.wordLimit, wordLimit > 0 else { return nil }
        mode = .words
        parameter = wordLimit
      case .quote, .zen, .custom:
        return nil
      }
      language = configuration.language
      difficulty = configuration.difficulty
      includesPunctuation = configuration.contentOptions.includePunctuation
      includesNumbers = configuration.contentOptions.includeNumbers
      usesLazyLatin = configuration.modifiers.contains(.lazyLatin)
    }
  }

  private static func isBetter(_ candidate: CompletedTestResult, than current: CompletedTestResult) -> Bool {
    if candidate.wpm != current.wpm { return candidate.wpm > current.wpm }
    if candidate.finishedAt != current.finishedAt { return candidate.finishedAt < current.finishedAt }
    return candidate.id.uuidString < current.id.uuidString
  }

  private static func makeRow(_ result: CompletedTestResult) -> LocalPersonalBestRow {
    let configuration = result.configuration
    let consistency = ResultConsistencyPolicy.metrics(
      events: result.replayEvents, duration: result.elapsedDuration).typing
    return .init(
      id: result.id, mode: configuration.mode,
      parameter: configuration.mode == .time ? Int(configuration.duration ?? 0) : configuration.wordLimit ?? 0,
      wpm: result.wpm, rawWpm: result.rawWpm, accuracy: result.accuracy,
      consistency: consistency, difficulty: configuration.difficulty, language: configuration.language,
      includesPunctuation: configuration.contentOptions.includePunctuation,
      includesNumbers: configuration.contentOptions.includeNumbers,
      usesLazyLatin: configuration.modifiers.contains(.lazyLatin), finishedAt: result.finishedAt)
  }
}

struct LocalPersonalBestTableView: View {
  @Environment(\.dismiss) private var dismiss
  @Query(sort: \TestResultRecord.finishedAt, order: .reverse) private var results: [TestResultRecord]
  @State private var selectedMode: TestMode = .time
  let speedUnit: TypingSpeedUnit

  private var rows: [LocalPersonalBestRow] {
    LocalPersonalBestTablePolicy.rows(results: results.compactMap(\.portableResult))
      .filter { $0.mode == selectedMode }
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          Picker("测试类型", selection: $selectedMode) {
            Text(TestMode.time.displayName).tag(TestMode.time)
            Text(TestMode.words.displayName).tag(TestMode.words)
          }
          .pickerStyle(.segmented)
          Text("只显示这台 Mac 上同类设置的已完成最佳成绩；不读取账户或网络数据。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if rows.isEmpty {
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
                    "\(speedUnit.converted(wpm: Double(row.wpm)).formatted(.number.precision(.fractionLength(0)))) \(speedUnit.displayName) · \(row.accuracy)%"
                  )
                  Text(
                    "Raw \(speedUnit.converted(wpm: Double(row.rawWpm)).formatted(.number.precision(.fractionLength(0)))) · \(row.consistency.formatted(.number.precision(.fractionLength(0))))% 稳定"
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                  Text("\(row.language.displayName) · \(row.difficulty.displayName)")
                  Text(row.optionsLabel)
                  Text(row.finishedAt, format: .dateTime.year().month().day())
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
