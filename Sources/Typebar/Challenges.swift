import SwiftUI

struct TypebarChallenge: Identifiable, Equatable {
  let id: String
  let title: String
  let description: String
  let preset: SavedTestPreset
  let requirements: ChallengeRequirements
}

enum ChallengeMetricRequirement: Equatable {
  case minimum(Int)
  case exact(Int)

  func summary(label: String, suffix: String = "") -> String {
    switch self {
    case .minimum(let value): "\(label)至少 \(value)\(suffix)"
    case .exact(let value): "\(label)恰为 \(value)\(suffix)"
    }
  }

  func failure(label: String, actual: Int, suffix: String = "") -> String? {
    switch self {
    case .minimum(let expected) where actual < expected:
      "\(label)需要至少 \(expected)\(suffix)（本次 \(actual)\(suffix)）"
    case .exact(let expected) where actual != expected:
      "\(label)需要恰为 \(expected)\(suffix)（本次 \(actual)\(suffix)）"
    default:
      nil
    }
  }
}

struct ChallengeConfigurationRequirements: Equatable {
  var mode: TestMode?
  var language: TypingLanguage?
  var difficulty: Difficulty?
  var punctuation: Bool?
  var numbers: Bool?
}

struct ChallengeRequirements: Equatable {
  var wpm: ChallengeMetricRequirement? = nil
  var rawWPM: ChallengeMetricRequirement? = nil
  var accuracy: ChallengeMetricRequirement? = nil
  var consistency: ChallengeMetricRequirement? = nil
  var minimumDuration: TimeInterval? = nil
  var maximumAFKPercentage: Int? = nil
  var exactFunboxes: [TestModifier]? = nil
  var configuration: ChallengeConfigurationRequirements? = nil
  var maximumErrors: Int? = nil

  var effectiveMaximumAFKPercentage: Int { min(maximumAFKPercentage ?? 10, 10) }

  var summary: String {
    [
      wpm?.summary(label: "速度", suffix: " WPM"),
      rawWPM?.summary(label: "原始速度", suffix: " WPM"),
      accuracy?.summary(label: "准确率", suffix: "%"),
      consistency?.summary(label: "一致性", suffix: "%"),
      minimumDuration.map { "时长至少 \(Int($0.rounded())) 秒" },
      "闲置不超过 \(effectiveMaximumAFKPercentage)%",
      exactFunboxes.map { "趣味模式恰为 \(modifierNames($0))" },
      configuration.map(configurationSummary),
      maximumErrors.map { "错误不超过 \($0)" },
    ]
    .compactMap { $0 }
    .joined(separator: " · ")
  }

  private func modifierNames(_ modifiers: [TestModifier]) -> String {
    modifiers.isEmpty ? "无" : modifiers.map(\.displayName).sorted().joined(separator: "、")
  }

  private func configurationSummary(_ required: ChallengeConfigurationRequirements) -> String {
    var parts: [String] = []
    if let mode = required.mode { parts.append("模式 \(mode.displayName)") }
    if let language = required.language { parts.append("语言 \(language.rawValue)") }
    if let difficulty = required.difficulty { parts.append("难度 \(difficulty.rawValue)") }
    if let punctuation = required.punctuation { parts.append(punctuation ? "启用标点" : "关闭标点") }
    if let numbers = required.numbers { parts.append(numbers ? "启用数字" : "关闭数字") }
    return parts.joined(separator: "、")
  }
}

struct ChallengeEvaluation: Equatable {
  let challenge: TypebarChallenge
  let passed: Bool
  let failedRequirements: [String]
}

enum ChallengeEvaluator {
  static func evaluate(_ result: CompletedTestResult, challenge: TypebarChallenge)
    -> ChallengeEvaluation
  {
    var failedRequirements: [String] = []
    let requirements = challenge.requirements

    if let failure = requirements.wpm?.failure(label: "速度", actual: result.wpm, suffix: " WPM") {
      failedRequirements.append(failure)
    }
    if let failure = requirements.rawWPM?.failure(
      label: "原始速度", actual: result.rawWpm, suffix: " WPM"
    ) {
      failedRequirements.append(failure)
    }
    if let failure = requirements.accuracy?.failure(
      label: "准确率", actual: result.accuracy, suffix: "%"
    ) {
      failedRequirements.append(failure)
    }

    if let consistencyRequirement = requirements.consistency {
      let consistency = Int(
        ResultConsistencyPolicy.metrics(
          events: result.replayEvents,
          duration: result.elapsedDuration
        ).typing.rounded())
      if let failure = consistencyRequirement.failure(
        label: "一致性", actual: consistency, suffix: "%"
      ) {
        failedRequirements.append(failure)
      }
    }

    if let minimumDuration = requirements.minimumDuration,
      Int(result.elapsedDuration.rounded()) < Int(minimumDuration.rounded())
    {
      failedRequirements.append(
        "时长需要至少 \(Int(minimumDuration.rounded())) 秒（本次 \(Int(result.elapsedDuration.rounded())) 秒）")
    }

    let roundedAFKPercentage = result.afkPercentage.rounded()
    if !roundedAFKPercentage.isFinite || roundedAFKPercentage > Double(Int.max) {
      failedRequirements.append("闲置比例无效，无法验收")
    } else if Int(max(0, roundedAFKPercentage)) > requirements.effectiveMaximumAFKPercentage {
      let afkPercentage = Int(max(0, roundedAFKPercentage))
      failedRequirements.append(
        "闲置需要不超过 \(requirements.effectiveMaximumAFKPercentage)%（本次 \(afkPercentage)%）")
    }

    if let expectedFunboxes = requirements.exactFunboxes {
      let expected = Set(expectedFunboxes.map(\.rawValue))
      let actualFunboxes = result.configuration.modifiers.filter {
        TestModifier.funboxPreferenceCases.contains($0)
      }
      let actual = Set(actualFunboxes.map(\.rawValue))
      if actual != expected {
        failedRequirements.append(
          "趣味模式需要精确匹配（要求 \(modifierNames(expectedFunboxes))；本次 \(modifierNames(actualFunboxes))）")
      }
    }

    if let required = requirements.configuration {
      evaluateConfiguration(result.configuration, required: required, failures: &failedRequirements)
    }

    if let maximumErrors = requirements.maximumErrors, result.errorCount > maximumErrors {
      failedRequirements.append("错误需要不超过 \(maximumErrors)（本次 \(result.errorCount)）")
    }
    return .init(
      challenge: challenge, passed: failedRequirements.isEmpty,
      failedRequirements: failedRequirements)
  }

  private static func modifierNames(_ modifiers: [TestModifier]) -> String {
    modifiers.isEmpty ? "无" : modifiers.map(\.displayName).sorted().joined(separator: "、")
  }

  private static func evaluateConfiguration(
    _ actual: TestConfiguration,
    required: ChallengeConfigurationRequirements,
    failures: inout [String]
  ) {
    if let expected = required.mode, actual.mode.rawValue != expected.rawValue {
      failures.append("模式需要为 \(expected.displayName)（本次 \(actual.mode.displayName)）")
    }
    if let expected = required.language, actual.language != expected {
      failures.append("语言需要为 \(expected.rawValue)（本次 \(actual.language.rawValue)）")
    }
    if let expected = required.difficulty, actual.difficulty.rawValue != expected.rawValue {
      failures.append("难度需要为 \(expected.rawValue)（本次 \(actual.difficulty.rawValue)）")
    }
    if let expected = required.punctuation,
      actual.contentOptions.includePunctuation != expected
    {
      failures.append("标点需要\(expected ? "启用" : "关闭")")
    }
    if let expected = required.numbers,
      actual.contentOptions.includeNumbers != expected
    {
      failures.append("数字需要\(expected ? "启用" : "关闭")")
    }
  }
}

enum TypebarChallengeLibrary {
  static let all: [TypebarChallenge] = [
    .init(
      id: "calm-thirty",
      title: "沉稳三十",
      description: "在一段短时间练习中保持速度和准确率。",
      preset: .init(configuration: .timed(seconds: 30), quoteID: nil, customText: nil),
      requirements: .init(
        wpm: .minimum(35),
        accuracy: .minimum(94),
        minimumDuration: 30,
        maximumAFKPercentage: 5,
        maximumErrors: 10
      )
    ),
    .init(
      id: "clean-twenty-five",
      title: "净手二十五",
      description: "完成一段无错误的短词练习。",
      preset: .init(configuration: .words(25), quoteID: nil, customText: nil),
      requirements: .init(accuracy: .exact(100), maximumErrors: 0)
    ),
    .init(
      id: "long-breath",
      title: "长呼吸",
      description: "在更长的词流中稳定保持节奏。",
      preset: .init(configuration: .words(100), quoteID: nil, customText: nil),
      requirements: .init(
        wpm: .minimum(45), accuracy: .minimum(96), maximumErrors: 12
      )
    ),
    .init(
      id: "memory-mark",
      title: "记忆刻度",
      description: "只凭短暂预览完成一组高难度词流。",
      preset: .init(
        configuration: TestConfiguration.words(25, difficulty: .master)
          .with(modifiers: [.memory]),
        quoteID: nil,
        customText: nil
      ),
      requirements: .init(
        accuracy: .minimum(95),
        exactFunboxes: [.memory],
        configuration: .init(mode: .words, difficulty: .master)
      )
    ),
  ]

  static func challenge(id: String?) -> TypebarChallenge? {
    guard let id else { return nil }
    return all.first { $0.id == id }
  }

  static func dailyChallenge(on date: Date = .now, calendar: Calendar = .current)
    -> TypebarChallenge
  {
    let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
    return all[day % all.count]
  }
}

struct ChallengeLibraryView: View {
  @Environment(\.dismiss) private var dismiss
  let onSelect: (TypebarChallenge) -> Void

  var body: some View {
    NavigationStack {
      List(TypebarChallengeLibrary.all) { challenge in
        Button {
          onSelect(challenge)
          dismiss()
        } label: {
          VStack(alignment: .leading, spacing: 5) {
            HStack {
              Text(challenge.title).font(.headline)
              Spacer()
              Image(systemName: "flag.checkered")
                .foregroundStyle(.tint)
            }
            Text(challenge.description)
              .foregroundStyle(.secondary)
            Text(challenge.requirements.summary)
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .accessibilityHint("加载此挑战的固定测试配置")
      }
      .safeAreaInset(edge: .top) {
        let daily = TypebarChallengeLibrary.dailyChallenge()
        Button {
          onSelect(daily)
          dismiss()
        } label: {
          HStack {
            Image(systemName: "sun.max.fill").foregroundStyle(.orange)
            VStack(alignment: .leading) {
              Text("今日离线挑战").font(.caption.weight(.medium))
              Text(daily.title).font(.headline)
            }
            Spacer()
            Image(systemName: "arrow.right.circle.fill").foregroundStyle(.tint)
          }
          .padding(.horizontal)
          .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(.bar)
      }
      .navigationTitle("离线挑战")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("完成") { dismiss() }
        }
      }
    }
    .frame(minWidth: 460, minHeight: 330)
  }
}
