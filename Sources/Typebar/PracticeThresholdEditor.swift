import SwiftUI

enum PracticeThresholdInputKind: Equatable {
  case speed
  case accuracy
  case wordBurst
}

enum PracticeThresholdInput {
  static func editorValue(from text: String, kind: PracticeThresholdInputKind, unit: TypingSpeedUnit,
    initialCanonicalValue: Double, preserveStoredValue: Bool) -> Double? {
    let displayed = kind == .accuracy ? initialCanonicalValue : unit.converted(wpm: initialCanonicalValue)
    if preserveStoredValue, initialCanonicalValue.isFinite, initialCanonicalValue >= 0,
      displayed.isFinite, kind != .accuracy || initialCanonicalValue <= 100,
      text.trimmingCharacters(in: .whitespacesAndNewlines) == String(displayed) {
      return initialCanonicalValue
    }
    return value(from: text, kind: kind, unit: unit)
  }

  static func value(
    from text: String, kind: PracticeThresholdInputKind, unit: TypingSpeedUnit
  ) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let displayed = Double(trimmed), displayed.isFinite,
      displayed >= 0
    else { return nil }
    switch kind {
    case .accuracy:
      return displayed <= 100 ? displayed : nil
    case .speed:
      let canonical = unit.canonicalWpmValue(fromDisplayedValue: displayed)
      return canonical.isFinite && canonical >= 0 ? canonical : nil
    case .wordBurst:
      guard displayed.rounded(.towardZero) == displayed else { return nil }
      let canonical = unit.canonicalWpmValue(fromDisplayedValue: displayed)
      return canonical.isFinite && canonical >= 0 ? canonical : nil
    }
  }
}

enum PracticeThresholdApplication {
  @discardableResult
  @MainActor
  static func apply(
    _ value: Double, kind: PracticeThresholdEditorKind, to settings: AppSettings,
    onConfigurationSave: () -> Void = {}
  ) -> Bool {
    guard settings.allowsRestartingConfigurationChange, value.isFinite, value >= 0 else { return false }
    if case .minimumAccuracy = kind, value > 100 { return false }
    if settings.hasThresholdProfile {
      let change: PracticeThresholdConfiguration.Change
      switch kind {
      case .minimumWpm: change = .minimumWpm(mode: .custom, customValue: value)
      case .minimumAccuracy: change = .minimumAccuracy(mode: .custom, customValue: value)
      case .minimumWordBurst(let mode): change = .minimumWordBurst(mode: mode, customValue: value)
      }
      guard settings.updateThresholdConfiguration(change) else { return false }
      onConfigurationSave()
      return true
    }
    switch kind {
    case .minimumWpm:
      settings.minimumWpm = value
    case .minimumAccuracy:
      settings.minimumAccuracy = value
    case .minimumWordBurst(let mode):
      settings.minimumWordBurstWpm = value
      if value > 0 { settings.minimumWordBurstMode = mode }
    }
    onConfigurationSave()
    return true
  }
}

enum PracticeThresholdEditorKind: Equatable, Identifiable {
  case minimumWpm
  case minimumAccuracy
  case minimumWordBurst(MinimumWordBurstMode)

  @MainActor
  func initialCanonicalValue(in settings: AppSettings) -> Double {
    if let source = settings.thresholdConfiguration {
      switch self {
      case .minimumWpm: return source.minimumWpmCustomValue
      case .minimumAccuracy: return source.minimumAccuracyCustomValue
      case .minimumWordBurst: return source.minimumWordBurstCustomValue
      }
    }
    switch self {
    case .minimumWpm: return settings.minimumWpm
    case .minimumAccuracy: return settings.minimumAccuracy
    case .minimumWordBurst: return settings.minimumWordBurstWpm
    }
  }

  var id: String {
    switch self {
    case .minimumWpm: "minimumWpm"
    case .minimumAccuracy: "minimumAccuracy"
    case .minimumWordBurst(let mode): "minimumWordBurst.\(mode.rawValue)"
    }
  }

  var inputKind: PracticeThresholdInputKind {
    switch self {
    case .minimumWpm: .speed
    case .minimumAccuracy: .accuracy
    case .minimumWordBurst: .wordBurst
    }
  }

  var title: String {
    switch self {
    case .minimumWpm: "最低整体速度"
    case .minimumAccuracy: "最低准确率"
    case .minimumWordBurst(.fixed): "最低单词速度 · 固定"
    case .minimumWordBurst(.flex): "最低单词速度 · 弹性"
    case .minimumWordBurst(.off): "最低单词速度"
    }
  }

  var explanation: String {
    switch self {
    case .minimumWpm: "开始后的每个整秒检查；完成至少四个词后，速度低于该值会判定失败。"
    case .minimumAccuracy: "开始后的每个整秒检查；准确率低于该值会判定失败。"
    case .minimumWordBurst(.fixed): "每个可测单词都使用同一速度门槛。"
    case .minimumWordBurst(.flex): "较长单词会使用逐步放宽的速度门槛。"
    case .minimumWordBurst(.off): ""
    }
  }
}

struct PracticeThresholdEditor: View {
  @Environment(\.dismiss) private var dismiss
  let kind: PracticeThresholdEditorKind
  let unit: TypingSpeedUnit
  let preservesZeroMode: Bool
  let initialCanonicalValue: Double
  let onApply: (Double) -> Bool
  @State private var text: String
  @State private var applicationFailed = false
  @FocusState private var inputFocused: Bool

  init(
    kind: PracticeThresholdEditorKind, unit: TypingSpeedUnit, initialCanonicalValue: Double,
    preservesZeroMode: Bool = false,
    onApply: @escaping (Double) -> Bool
  ) {
    self.kind = kind
    self.unit = unit
    self.onApply = onApply
    self.preservesZeroMode = preservesZeroMode
    self.initialCanonicalValue = initialCanonicalValue
    let displayed = kind.inputKind == .accuracy
      ? initialCanonicalValue : unit.converted(wpm: initialCanonicalValue)
    _text = State(initialValue: String(displayed))
  }

  private var value: Double? {
    PracticeThresholdInput.editorValue(from: text, kind: kind.inputKind, unit: unit,
      initialCanonicalValue: initialCanonicalValue, preserveStoredValue: preservesZeroMode)
  }

  private var inputUnit: String {
    kind.inputKind == .accuracy ? "%" : unit.displayName
  }

  var body: some View {
    NavigationStack {
      Form {
        Section(kind.title) {
          TextField(inputUnit, text: $text)
            .focused($inputFocused)
          if let value {
            let display = value.formatted(.number.precision(.fractionLength(0...4)))
            LabeledContent("将应用", value: value == 0 && !preservesZeroMode ? "关闭" : "\(display) \(kind.inputKind == .accuracy ? "%" : "WPM")")
              .foregroundStyle(.secondary)
          } else {
            Text(kind.inputKind == .wordBurst ? "请输入非负整数。" : "请输入有效的非负数字。")
              .foregroundStyle(.red)
          }
        }
        Section {
          Text(kind.explanation + (preservesZeroMode
            ? " 输入 0 会保留所选自定义模式；关闭请使用关闭命令。应用后会退出挑战并重新开始练习。"
            : " 输入 0 会关闭该规则；应用后会退出挑战并重新开始练习。"))
            .font(.caption)
            .foregroundStyle(.secondary)
          if applicationFailed {
            Text("未能应用，原设置已保留。请检查锁定状态或配置存储。")
              .font(.caption).foregroundStyle(.red)
          }
        }
      }
      .formStyle(.grouped)
      .navigationTitle(kind.title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
            .keyboardShortcut(.cancelAction)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("应用") {
            guard let value else { return }
            guard onApply(value) else { applicationFailed = true; return }
            dismiss()
          }
          .keyboardShortcut(.defaultAction)
          .disabled(value == nil)
        }
      }
    }
    .frame(width: 430, height: 280)
    .onAppear { inputFocused = true }
  }
}
