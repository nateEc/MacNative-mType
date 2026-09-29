import SwiftUI

struct TypebarChallenge: Identifiable, Equatable {
  let id: String
  let title: String
  let description: String
  /// Public identifiers accepted from legacy web challenge URLs. They are
  /// identities only; the local title, description and requirements stay
  /// independently authored by Typebar.
  let legacyURLNames: [String]
  let preset: SavedTestPreset
  let requirements: ChallengeRequirements
  let dailyEligible: Bool

  init(
    id: String,
    title: String,
    description: String,
    legacyURLNames: [String] = [],
    preset: SavedTestPreset,
    requirements: ChallengeRequirements,
    dailyEligible: Bool = true
  ) {
    self.id = id
    self.title = title
    self.description = description
    self.legacyURLNames = legacyURLNames
    self.preset = preset
    self.requirements = requirements
    self.dailyEligible = dailyEligible
  }
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
  var liveSpeedStyle: LiveMetricStyle?
  var paceCaretStyle: TypingCaretStyle?
  var tapeMode: PracticeTapeMode?
  var wordLimit: Int?
  var fontFamily: String?
  var keyboardGuideMode: KeyboardGuideMode?
}

struct ChallengeRequirements: Equatable {
  var wpm: ChallengeMetricRequirement? = nil
  var rawWPM: ChallengeMetricRequirement? = nil
  var accuracy: ChallengeMetricRequirement? = nil
  var consistency: ChallengeMetricRequirement? = nil
  var minimumDuration: TimeInterval? = nil
  var maximumAFKPercentage: Int? = nil
  var exactFunboxes: [TestModifier]? = nil
  var layoutFluidMinimumWPM: Int? = nil
  var configuration: ChallengeConfigurationRequirements? = nil
  var maximumErrors: Int? = nil
  var requiresVirtualKeyboardOnly = false
  var requiredCustomWordLimit: Int? = nil
  var exactPrompt: String? = nil
  var requiresOneHandedSource = false

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
      layoutFluidMinimumWPM.map { "三种不同布局各至少 \($0) WPM" },
      configuration.map(configurationSummary),
      maximumErrors.map { "错误不超过 \($0)" },
      requiresVirtualKeyboardOnly ? "仅使用屏幕键盘输入" : nil,
      requiredCustomWordLimit.map { "指定脚本的 \($0) 词完整练习" },
      exactPrompt.map { _ in "使用本挑战的原生脚本" },
      requiresOneHandedSource ? "所选布局单手词表，最多一小时或一万词" : nil,
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
    if let liveSpeedStyle = required.liveSpeedStyle {
      parts.append("实时速度 \(liveSpeedStyle.displayName)")
    }
    if let paceCaretStyle = required.paceCaretStyle {
      parts.append("节奏光标 \(paceCaretStyle.displayName)")
    }
    if let tapeMode = required.tapeMode { parts.append("卷带 \(tapeMode.displayName)") }
    if let wordLimit = required.wordLimit { parts.append("词数 \(wordLimit)") }
    if let fontFamily = required.fontFamily { parts.append("字体 \(fontFamily)") }
    if let keyboardGuideMode = required.keyboardGuideMode {
      parts.append("键盘图 \(keyboardGuideMode.displayName)")
    }
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
    if let accuracy = requirements.accuracy {
      let actual = result.preciseAccuracy
      let displayed = String(format: "%.2f", actual)
      switch accuracy {
      case .minimum(let expected) where actual < Double(expected):
        failedRequirements.append("准确率需要至少 \(expected)%（本次 \(displayed)%）")
      case .exact(let expected) where actual != Double(expected):
        failedRequirements.append("准确率需要恰为 \(expected)%（本次 \(displayed)%）")
      default:
        break
      }
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

    if let minimumWPM = requirements.layoutFluidMinimumWPM {
      if result.configuration.mode != .time || result.configuration.duration != 60 {
        failedRequirements.append("布局挑战需要六十秒计时配置")
      } else if let layouts = result.challengePresentation?.layoutFluidLayouts,
        layouts.count == 3, Set(layouts).count == 3,
        let speeds = LayoutFluidChallengePolicy.segmentSpeeds(result, layouts: layouts)
      {
        for (layout, wpm) in speeds where wpm < minimumWPM {
          failedRequirements.append(
            "布局 \(layout.displayName) 需要至少 \(minimumWPM) WPM（本段 \(wpm) WPM）")
        }
      } else {
        failedRequirements.append("需要三种不同布局的本次练习记录，旧结果无法验收")
      }
    }

    if let required = requirements.configuration {
      evaluateConfiguration(
        result.configuration,
        presentation: result.challengePresentation,
        required: required,
        failures: &failedRequirements)
    }

    if let maximumErrors = requirements.maximumErrors, result.errorCount > maximumErrors {
      failedRequirements.append("错误需要不超过 \(maximumErrors)（本次 \(result.errorCount)）")
    }
    if requirements.requiresVirtualKeyboardOnly {
      if result.configuration.mode != .time || result.configuration.duration != 3_600 {
        failedRequirements.append("需要一小时计时配置")
      }
      if result.challengePresentation?.virtualKeyboardOnly != true {
        failedRequirements.append("需要本次仅使用屏幕键盘输入的记录，旧结果无法验收")
      }
    }
    if let count = requirements.requiredCustomWordLimit,
      result.configuration.mode != .custom
        || result.configuration.customTextCompletion != .words
        || result.configuration.wordLimit != count
    {
      failedRequirements.append("需要指定脚本的 \(count) 词自定义练习")
    }
    if let prompt = requirements.exactPrompt, result.prompt != prompt {
      failedRequirements.append("需要完成本挑战的原生脚本")
    }
    if requirements.requiresOneHandedSource {
      let presentation = result.challengePresentation
      if result.outcome != .completed
        || result.configuration.mode != .custom
        || result.configuration.customTextCompletion != .words
        || result.configuration.wordLimit != 10_000
        || result.configuration.duration != 3_600
      {
        failedRequirements.append("需要一小时或一万词的单手自定义练习")
      }
      if result.elapsedDuration < 3_600 && (presentation?.completedWords ?? 0) < 10_000 {
        failedRequirements.append("需要完成一小时或一万词；旧结果缺少词数证据无法验收")
      }
      if let selection = presentation?.oneHandedSelection,
        let source = OneHandedChallengePolicy.preset(for: selection)?.customText
      {
        let allowed = Set(source.split(separator: " ").map(String.init))
        if result.prompt.isEmpty || !result.prompt.split(separator: " ").allSatisfy({ allowed.contains(String($0)) }) {
          failedRequirements.append("题目不属于所选布局的单手词表")
        }
      } else {
        failedRequirements.append("缺少单手布局与词表证据，旧结果无法验收")
      }
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
    presentation: ChallengePresentationSnapshot?,
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
    if let expected = required.wordLimit, actual.wordLimit != expected {
      failures.append("词数需要为 \(expected)（本次 \(actual.wordLimit.map(String.init) ?? "未知")）")
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
    let requiresPresentation = required.liveSpeedStyle != nil || required.paceCaretStyle != nil
      || required.tapeMode != nil || required.fontFamily != nil
      || required.keyboardGuideMode != nil
    guard !requiresPresentation || presentation != nil else {
      failures.append("缺少挑战显示设置快照，无法验收")
      return
    }
    if let expected = required.liveSpeedStyle,
      presentation?.liveSpeedStyle != expected
    {
      failures.append(
        "实时速度需要为 \(expected.displayName)（本次 \(presentation?.liveSpeedStyle.displayName ?? "未知")）")
    }
    if let expected = required.paceCaretStyle,
      presentation?.paceCaretStyle != expected
    {
      failures.append(
        "节奏光标需要为 \(expected.displayName)（本次 \(presentation?.paceCaretStyle.displayName ?? "未知")）")
    }
    if let expected = required.tapeMode,
      presentation?.tapeMode != expected
    {
      failures.append(
        "卷带需要为 \(expected.displayName)（本次 \(presentation?.tapeMode.displayName ?? "未知")）")
    }
    if let expected = required.fontFamily,
      presentation?.fontFamily != expected || presentation?.fontStayedAvailable != true
    {
      failures.append("需要全程使用 \(expected) 字体，旧结果或字体回退无法验收")
    }
    if let expected = required.keyboardGuideMode,
      presentation?.keyboardGuideMode != expected
    {
      failures.append("键盘图需要为 \(expected.displayName)")
    }
  }
}

enum LayoutFluidChallengePolicy {
  static func segmentSpeeds(
    _ result: CompletedTestResult, layouts: [KeyboardLayout]
  ) -> [(KeyboardLayout, Int)]? {
    guard let duration = result.configuration.duration, duration.isFinite,
      duration > 0, !layouts.isEmpty
    else { return nil }
    let segmentDuration = duration / Double(layouts.count)
    return layouts.enumerated().map { index, layout in
      let beginning = segmentDuration * Double(index)
      let ending = segmentDuration * Double(index + 1)
      let before = TypingReplay.inputGlyphs(
        prompt: result.prompt, events: result.replayEvents, through: beginning.nextDown)
        .filter { $0.state == .correct }.count
      let after = TypingReplay.inputGlyphs(
        prompt: result.prompt, events: result.replayEvents, through: ending.nextDown)
        .filter { $0.state == .correct }.count
      let wpm = Int((Double(after - before) / 5 / segmentDuration * 60).rounded())
      return (layout, wpm)
    }
  }
}

enum OneHandedChallengeSide: String, CaseIterable, Identifiable, Codable {
  case left, right
  var id: Self { self }
  var title: String { self == .left ? "左手" : "右手" }
  var filterPreset: LocalWordFilterPreset { self == .left ? .leftHand : .rightHand }
}

struct OneHandedChallengeSelection: Codable, Equatable {
  let layout: KeyboardLayout
  let side: OneHandedChallengeSide
}

enum OneHandedChallengePolicy {
  static func source(for selection: OneHandedChallengeSelection) -> String? {
    let lexicon = StarterLexicon.words + StarterLexicon.englishFiveLetterWords
      + StarterLexicon.englishDoubleLetterWords
      + TypingLanguage.englishLegal.ownedPracticeWords()
      + TypingLanguage.englishMedical.ownedPracticeWords()
      + TypingLanguage.englishShakespearean.ownedPracticeWords()
    guard let criteria = selection.side.filterPreset.criteria(layout: selection.layout),
      case .success(let words) = LocalWordFilter.words(
        in: lexicon, matching: criteria)
    else { return nil }
    var source: [String] = []
    var length = 0
    for word in Set(words).sorted() {
      let nextLength = length + word.count + (source.isEmpty ? 0 : 1)
      if nextLength > CustomTextPolicy.maximumLength { break }
      source.append(word)
      length = nextLength
    }
    return source.count >= 2 ? source.joined(separator: " ") : nil
  }

  static func preset(for selection: OneHandedChallengeSelection) -> SavedTestPreset? {
    guard let source = source(for: selection) else { return nil }
    return .init(configuration: .init(
      mode: .custom, duration: 3_600, wordLimit: 10_000, difficulty: .normal,
      rules: .init(), customTextCompletion: .words, customTextOrdering: .random),
      quoteID: nil, customText: source)
  }

  static func identify(source: String) -> OneHandedChallengeSelection? {
    for layout in KeyboardLayout.allCases {
      for side in OneHandedChallengeSide.allCases {
        let selection = OneHandedChallengeSelection(layout: layout, side: side)
        if self.source(for: selection) == source { return selection }
      }
    }
    return nil
  }
}

struct OneHandedChallengeSetupView: View {
  let onStart: (SavedTestPreset, OneHandedChallengeSelection) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var layout: KeyboardLayout = .ansiQwerty
  @State private var side: OneHandedChallengeSide = .left

  private var selection: OneHandedChallengeSelection { .init(layout: layout, side: side) }
  private var preset: SavedTestPreset? { OneHandedChallengePolicy.preset(for: selection) }

  var body: some View {
    NavigationStack {
      Form {
        Picker("键盘布局", selection: $layout) {
          ForEach(KeyboardLayout.allCases) { option in
            Text(option.displayName).tag(option)
          }
        }
        Picker("使用一侧", selection: $side) {
          ForEach(OneHandedChallengeSide.allCases) { option in
            Text(option.title).tag(option)
          }
        }
        Text("从 Typebar 自有英语词库筛选；一小时或一万词先到即结束。请自行遵守只用所选手输入，应用无法证明实际使用了哪只手。")
          .font(.caption).foregroundStyle(.secondary)
        if let preset {
          Text("符合条件的词：\(preset.customText?.split(separator: " ").count ?? 0)")
        } else {
          Text("这个布局与手侧在本地词库中不足两个词，请更换。")
            .foregroundStyle(.orange)
        }
      }
      .navigationTitle("单手万词")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("开始") {
            guard let preset else { return }
            onStart(preset, selection)
            dismiss()
          }.disabled(preset == nil)
        }
      }
    }
    .frame(minWidth: 470, minHeight: 280)
  }
}

enum TypebarChallengeLibrary {
  /// Independently authored Typebar text; only the reference's public word count and rules
  /// informed this challenge. No reference script text is read or bundled.
  private static let robotLogScript = [
    "The observatory opened before sunrise and a repair robot counted every window",
    "It polished one lens then checked copper wires for sparks or silence",
    "Outside rain tapped slowly while distant trains hummed below the empty bridge",
    "Inside a clock measured each careful step without asking anyone to hurry",
    "When the first signal arrived the robot answered with a clear steady tone",
    "By morning the lamps faded and the workshop remembered another patient night beneath a pale sky",
  ].joined(separator: " ")

  static let all: [TypebarChallenge] = [
    .init(
      id: "one-handed-bandit", title: "单手万词",
      description: "任选内置键盘布局的左手或右手词表；一小时与一万词，先到即结束。",
      legacyURLNames: ["oneArmedBandit"],
      preset: OneHandedChallengePolicy.preset(for: .init(layout: .ansiQwerty, side: .left))!,
      requirements: .init(requiresOneHandedSource: true), dailyEligible: false
    ),
    .init(
      id: "ten-words-of-pain",
      title: "十词符号挑战",
      description: "使用本机 Wingdings 字体、关闭键盘图，在大师模式下完成十词练习。",
      legacyURLNames: ["wingdings"],
      preset: .init(configuration: .words(10, difficulty: .master),
        quoteID: nil, customText: nil),
      requirements: .init(
        wpm: .minimum(60), accuracy: .exact(100),
        configuration: .init(mode: .words, difficulty: .master,
          wordLimit: 10, fontFamily: "Wingdings", keyboardGuideMode: .off)),
      dailyEligible: false
    ),
    .init(
      id: "robot-log",
      title: "机器人日志",
      description: "完整输入 Typebar 自写的 77 词机器人日志，不输入空格，达到 45 WPM 和完全准确。",
      legacyURLNames: ["beepBoop"],
      preset: .init(configuration: .init(
        mode: .custom, duration: nil, wordLimit: 77, difficulty: .normal,
        rules: .init(), customTextCompletion: .words, modifiers: [.noSpaces]),
        quoteID: nil, customText: robotLogScript),
      requirements: .init(
        wpm: .minimum(45), accuracy: .exact(100), exactFunboxes: [.noSpaces],
        requiredCustomWordLimit: 77,
        exactPrompt: TestModifierPolicy.transformed(
          robotLogScript, modifiers: [.noSpaces], language: .english)),
      dailyEligible: false
    ),
    .init(
      id: "mouse-warrior",
      title: "屏幕键盘勇者",
      description: "只使用屏幕键盘完成一小时计时练习，不启用趣味模式。",
      legacyURLNames: ["mouseWarrior"],
      preset: .init(configuration: .timed(seconds: 3_600), quoteID: nil, customText: nil),
      requirements: .init(
        minimumDuration: 3_600, exactFunboxes: [], requiresVirtualKeyboardOnly: true),
      dailyEligible: false
    ),
    .init(
      id: "one-hour-focus",
      title: "一小时专注",
      description: "在一小时的本机词流中维持舒适、稳定的输入节奏。",
      legacyURLNames: ["oneHourWarrior"],
      preset: .init(configuration: .timed(seconds: 3_600), quoteID: nil, customText: nil),
      requirements: .init(minimumDuration: 3_600, maximumAFKPercentage: 10)
    ),
    .init(
      id: "two-hour-endurance",
      title: "两小时耐力",
      description: "保持两小时连续输入，完成一段长时间练习。",
      legacyURLNames: ["doubleDown"],
      preset: .init(configuration: .timed(seconds: 7_200), quoteID: nil, customText: nil),
      requirements: .init(minimumDuration: 7_200)
    ),
    .init(
      id: "three-hour-endurance",
      title: "三小时耐力",
      description: "将稳定输入延续到第三个小时。",
      legacyURLNames: ["tripleTrouble"],
      preset: .init(configuration: .timed(seconds: 10_800), quoteID: nil, customText: nil),
      requirements: .init(minimumDuration: 10_800)
    ),
    .init(
      id: "four-hour-endurance",
      title: "四小时耐力",
      description: "完成四小时的长程输入练习。",
      legacyURLNames: ["quad"],
      preset: .init(configuration: .timed(seconds: 14_400), quoteID: nil, customText: nil),
      requirements: .init(minimumDuration: 14_400)
    ),
    .init(
      id: "eight-hour-endurance",
      title: "八小时耐力",
      description: "在整段八小时练习中保持节奏。",
      legacyURLNames: ["8Ball"],
      preset: .init(configuration: .timed(seconds: 28_800), quoteID: nil, customText: nil),
      requirements: .init(minimumDuration: 28_800)
    ),
    .init(
      id: "twelve-hour-endurance",
      title: "十二小时耐力",
      description: "持续完成十二小时的本机输入练习。",
      legacyURLNames: ["theBig12"],
      preset: .init(configuration: .timed(seconds: 43_200), quoteID: nil, customText: nil),
      requirements: .init(minimumDuration: 43_200)
    ),
    .init(
      id: "one-day-endurance",
      title: "一日耐力",
      description: "以一天为长度完成超长输入练习。",
      legacyURLNames: ["1Day"],
      preset: .init(configuration: .timed(seconds: 86_400), quoteID: nil, customText: nil),
      requirements: .init(minimumDuration: 86_400)
    ),
    .init(
      id: "steady-sixty",
      title: "稳态六十",
      description: "在五分钟练习中恰好达到 60 WPM，且关闭实时速度与节奏光标。",
      legacyURLNames: ["slowAndSteady"],
      preset: .init(configuration: .timed(seconds: 300), quoteID: nil, customText: nil),
      requirements: .init(
        wpm: .exact(60),
        configuration: .init(liveSpeedStyle: .off, paceCaretStyle: .off)
      )
    ),
    .init(
      id: "accuracy-ten-minutes",
      title: "十分钟精准",
      description: "在大师模式下保持十分钟，达到 60 WPM 和完全准确。",
      legacyURLNames: ["accuracyExpert"],
      preset: .init(configuration: .timed(seconds: 0, difficulty: .master), quoteID: nil, customText: nil),
      requirements: .init(
        wpm: .minimum(60), accuracy: .exact(100),
        minimumDuration: 600, maximumAFKPercentage: 5
      )
    ),
    .init(
      id: "accuracy-twenty-minutes",
      title: "二十分钟精准",
      description: "在大师模式下保持二十分钟，达到 60 WPM 和完全准确。",
      legacyURLNames: ["accuracyMaster"],
      preset: .init(configuration: .timed(seconds: 0, difficulty: .master), quoteID: nil, customText: nil),
      requirements: .init(
        wpm: .minimum(60), accuracy: .exact(100),
        minimumDuration: 1_200, maximumAFKPercentage: 5
      )
    ),
    .init(
      id: "accuracy-thirty-minutes",
      title: "三十分钟精准",
      description: "在大师模式下保持三十分钟，达到 60 WPM 和完全准确。",
      legacyURLNames: ["accuracyGod"],
      preset: .init(configuration: .timed(seconds: 0, difficulty: .master), quoteID: nil, customText: nil),
      requirements: .init(
        wpm: .minimum(60), accuracy: .exact(100),
        minimumDuration: 1_800, maximumAFKPercentage: 5
      )
    ),
    .init(
      id: "english-ten-thousand-hour",
      title: "英语万词一小时",
      description: "用 Typebar 自有的 English 10k 词库，开启数字和标点，练习一小时。",
      legacyURLNames: ["englishMaster"],
      preset: .init(
        configuration: .timed(
          seconds: 3_600, language: .english10k,
          contentOptions: .init(includePunctuation: true, includeNumbers: true)
        ),
        quoteID: nil, customText: nil
      ),
      requirements: .init(
        minimumDuration: 3_600,
        configuration: .init(language: .english10k, punctuation: true, numbers: true)
      )
    ),
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
    .init(
      id: "quiet-thirty",
      title: "静默三十",
      description: "关闭速度提示与滚动辅助，只凭手感完成短练习。",
      preset: .init(configuration: .timed(seconds: 30), quoteID: nil, customText: nil),
      requirements: .init(
        wpm: .minimum(35),
        accuracy: .minimum(94),
        minimumDuration: 30,
        configuration: .init(
          liveSpeedStyle: .off,
          paceCaretStyle: .off,
          tapeMode: .off
        )
      )
    ),
  ] + officialFunboxChallenges + officialMetricAndWordChallenges

  private static let officialMetricAndWordChallenges: [TypebarChallenge] = [
    .init(
      id: "sixty-nine-metrics", title: "四项六十九",
      description: "在六十九秒练习中，让速度、原始速度、准确率和一致性都恰好为六十九。",
      legacyURLNames: ["69"],
      preset: .init(configuration: .timed(seconds: 69), quoteID: nil, customText: nil),
      requirements: .init(
        wpm: .exact(69), rawWPM: .exact(69), accuracy: .exact(69),
        consistency: .exact(69)),
      dailyEligible: false
    ),
    .init(
      id: "alphabet-random-hundred", title: "字母随机百词",
      description: "从英文字母中随机抽取一百个单字符词，达到每分钟一百词。",
      legacyURLNames: ["speedSpacer"],
      preset: .init(configuration: .init(
        mode: .custom, duration: nil, wordLimit: 100, difficulty: .normal,
        rules: .init(), customTextCompletion: .words, customTextOrdering: .random),
        quoteID: nil,
        customText: (97...122).compactMap(UnicodeScalar.init).map(String.init).joined(separator: " ")),
      requirements: .init(wpm: .minimum(100)),
      dailyEligible: false
    ),
    .init(
      id: "short-word-random-hundred", title: "双字母百词",
      description: "从二十个 Typebar 自有双字母英语词中随机练习一百词，达到每分钟一百词。",
      legacyURLNames: ["bigramSalad"],
      preset: .init(configuration: .init(
        mode: .custom, duration: nil, wordLimit: 100, difficulty: .normal,
        rules: .init(), customTextCompletion: .words, customTextOrdering: .random),
        quoteID: nil,
        customText: [
          "am", "an", "as", "at", "be", "by", "do", "go", "he", "hi",
          "if", "in", "is", "it", "me", "my", "no", "of", "oh", "on",
        ].joined(separator: " ")),
      requirements: .init(wpm: .minimum(100)),
      dailyEligible: false
    ),
    repeatedWordChallenge("antidiseWhat", id: "long-word-sprint", title: "长词冲刺",
      description: "重复输入一个长英语词，达到每分钟二百词。",
      word: "antidisestablishmentarianism", count: 1, minimumWPM: 200),
    repeatedWordChallenge("iveGotThePower", id: "power-ten", title: "十词极速",
      description: "连续输入十次短词，达到每分钟四百词。",
      word: "power", count: 10, minimumWPM: 400),
    repeatedWordChallenge("developd", id: "develop-thousand", title: "千词重复",
      description: "重复同一个常见英语词一千次。",
      word: "develop", count: 1_000, minimumWPM: nil),
    repeatedWordChallenge("whatsThisWebsiteCalledAgain", id: "reference-name-thousand",
      title: "站名千次", description: "重复输入兼容挑战指定的站名一千次。",
      word: "monkeytype", count: 1_000, minimumWPM: nil),
    repeatedWordChallenge("simp", id: "single-word-thousand", title: "单词千次",
      description: "重复输入 Typebar 自有练习词一千次。",
      word: "typebar", count: 1_000, minimumWPM: nil),
    repeatedWordChallenge("trueSimp", id: "single-word-ten-thousand", title: "单词万次",
      description: "重复输入 Typebar 自有练习词一万次。",
      word: "typebar", count: 10_000, minimumWPM: nil),
    repeatedWordChallenge("simpLord", id: "single-word-hundred-thousand", title: "单词十万次",
      description: "重复输入 Typebar 自有练习词十万次。",
      word: "typebar", count: 100_000, minimumWPM: nil),
  ]

  private static func repeatedWordChallenge(
    _ legacyName: String, id: String, title: String, description: String,
    word: String, count: Int, minimumWPM: Int?
  ) -> TypebarChallenge {
    .init(
      id: id, title: title, description: description,
      legacyURLNames: [legacyName],
      preset: .init(configuration: .init(
        mode: .custom, duration: nil, wordLimit: count, difficulty: .normal,
        rules: .init(), customTextCompletion: .words, customTextOrdering: .inOrder),
        quoteID: nil, customText: word),
      requirements: .init(wpm: minimumWPM.map(ChallengeMetricRequirement.minimum)),
      dailyEligible: false
    )
  }

  private static let officialFunboxChallenges: [TypebarChallenge] = [
    .init(
      id: "three-layout-flow", title: "三布局流动",
      description: "在六十秒内轮换三种不同键盘布局，每一段都达到每分钟五十词。",
      legacyURLNames: ["beLikeWater"],
      preset: .init(configuration: TestConfiguration.timed(seconds: 60)
        .with(modifiers: [.layoutFluid]), quoteID: nil, customText: nil),
      requirements: .init(
        minimumDuration: 60, exactFunboxes: [.layoutFluid],
        layoutFluidMinimumWPM: 50),
      dailyEligible: false
    ),
    hourFunbox("rollercoaster", id: "round-hour", title: "环形一小时",
      description: "沿着环形提示完成一小时打字。", modifier: .roundVisual,
      minimumDuration: 3_600),
    hourFunbox("oneHourMirror", id: "mirror-hour", title: "镜面一小时",
      description: "面对镜像排列的文字持续练习一小时。", modifier: .mirrorVisual,
      minimumDuration: 3_600),
    hourFunbox("chooChoo", id: "choo-hour", title: "列车一小时",
      description: "跟上列车式文字流，完成整小时输入。", modifier: .chooVisual,
      minimumDuration: 3_600),
    .init(
      id: "mnemonic-twenty-five", title: "记忆二十五",
      description: "在大师难度下凭短暂预览输入二十五个词，关闭卷带。",
      legacyURLNames: ["mnemonist"],
      preset: .init(configuration: TestConfiguration.words(25, difficulty: .master)
        .with(modifiers: [.memory]), quoteID: nil, customText: nil),
      requirements: .init(configuration: .init(tapeMode: .off)),
      dailyEligible: false
    ),
    hourFunbox("earfquake", id: "earthquake-hour", title: "震动一小时",
      description: "在震动的文字提示中完成一小时练习。", modifier: .earthquakeVisual,
      minimumDuration: 3_600),
    hourFunbox("simonSez", id: "simon-hour", title: "指令一小时",
      description: "依照不断变化的输入提示练习一小时。", modifier: .simonSays,
      minimumDuration: 3_600),
    hourFunbox("accountant", id: "accounting-hour", title: "数字流一小时",
      description: "在计算器风格的词流中练习一小时。", modifier: .accountingStream,
      minimumDuration: 3_600),
    readAheadChallenge("hidden", id: "read-ahead-sixty", title: "提前阅读",
      description: "在六十秒提前阅读练习中达到每分钟一百词。", modifier: .readAhead),
    readAheadChallenge("iCanSeeTheFuture", id: "hard-read-ahead-sixty", title: "远望文字",
      description: "在更严格的提前阅读练习中保持每分钟一百词。", modifier: .readAheadHard),
    hourFunbox("whatAreWordsAtThisPoint", id: "gibberish-hour", title: "乱序词流",
      description: "挑战一小时的乱序词流。", modifier: .gibberishStream,
      minimumDuration: 60),
    hourFunbox("specials", id: "specials-hour", title: "特殊字符",
      description: "在特殊字符词流中进行长时间练习。", modifier: .specialCharacterStream,
      minimumDuration: 60),
    hourFunbox("aeiou", id: "listening-hour", title: "听写长跑",
      description: "听取朗读提示，完成长时间输入练习。", modifier: .listening,
      minimumDuration: 60),
    hourFunbox("asciiWarrior", id: "ascii-hour", title: "字符长跑",
      description: "用 ASCII 字符词流完成长时间练习。", modifier: .asciiStream,
      minimumDuration: 60),
    hourFunbox("iKiNdAlIkEhOwInEfFiCiEnTqWeRtYiS", id: "alternating-case-hour",
      title: "大小写交替", description: "跟随交替大小写的词流长时间输入。",
      modifier: .alternatingCase, minimumDuration: 60),
    hourFunbox("oneNauseousMonkey", id: "nausea-hour", title: "晃动一小时",
      description: "在晃动的文字提示中完成长时间练习。", modifier: .nauseaVisual,
      minimumDuration: 60),
  ]

  private static func hourFunbox(
    _ legacyName: String, id: String, title: String, description: String,
    modifier: TestModifier, minimumDuration: TimeInterval
  ) -> TypebarChallenge {
    .init(
      id: id, title: title, description: description,
      legacyURLNames: [legacyName],
      preset: .init(configuration: TestConfiguration.timed(seconds: 3_600)
        .with(modifiers: [modifier]), quoteID: nil, customText: nil),
      requirements: .init(minimumDuration: minimumDuration, exactFunboxes: [modifier]),
      dailyEligible: false
    )
  }

  private static func readAheadChallenge(
    _ legacyName: String, id: String, title: String, description: String,
    modifier: TestModifier
  ) -> TypebarChallenge {
    .init(
      id: id, title: title, description: description,
      legacyURLNames: [legacyName],
      preset: .init(configuration: TestConfiguration.timed(seconds: 60)
        .with(modifiers: [modifier]), quoteID: nil, customText: nil),
      requirements: .init(
        wpm: .minimum(100), minimumDuration: 60,
        exactFunboxes: [modifier], configuration: .init(tapeMode: .off)),
      dailyEligible: false
    )
  }

  static func challenge(id: String?) -> TypebarChallenge? {
    guard let id else { return nil }
    return all.first { $0.id == id }
  }

  static func dailyChallenge(on date: Date = .now, calendar: Calendar = .current)
    -> TypebarChallenge
  {
    let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
    let dailyChoices = all.filter {
      $0.dailyEligible && !$0.preset.configuration.isInfinite
        && ($0.preset.configuration.duration ?? 0) <= 3_600
    }
    return dailyChoices[day % dailyChoices.count]
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
