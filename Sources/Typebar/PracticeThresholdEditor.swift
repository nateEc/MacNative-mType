import SwiftUI

enum PracticeThresholdInputKind: Equatable {
  case speed
  case accuracy
  case wordBurst
}

enum PracticeThresholdInput {
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
  @MainActor
  static func apply(
    _ value: Double, kind: PracticeThresholdEditorKind, to settings: AppSettings
  ) {
    switch kind {
    case .minimumWpm:
      settings.minimumWpm = value
    case .minimumAccuracy:
      settings.minimumAccuracy = value
    case .minimumWordBurst(let mode):
      settings.minimumWordBurstWpm = value
      if value > 0 { settings.minimumWordBurstMode = mode }
    }
  }
}

enum PracticeThresholdEditorKind: Equatable, Identifiable {
  case minimumWpm
  case minimumAccuracy
  case minimumWordBurst(MinimumWordBurstMode)

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
    case .minimumWpm: "有限练习完成时，速度低于该值会判定失败。"
    case .minimumAccuracy: "有限练习完成时，准确率低于该值会判定失败。"
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
  let onApply: (Double) -> Void
  @State private var text: String
  @FocusState private var inputFocused: Bool

  init(
    kind: PracticeThresholdEditorKind, unit: TypingSpeedUnit, initialCanonicalValue: Double,
    onApply: @escaping (Double) -> Void
  ) {
    self.kind = kind
    self.unit = unit
    self.onApply = onApply
    let displayed = kind.inputKind == .accuracy
      ? initialCanonicalValue : unit.converted(wpm: initialCanonicalValue)
    _text = State(initialValue: String(displayed))
  }

  private var value: Double? {
    PracticeThresholdInput.value(from: text, kind: kind.inputKind, unit: unit)
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
            LabeledContent("将应用", value: value == 0 ? "关闭" : "\(display) \(kind.inputKind == .accuracy ? "%" : "WPM")")
              .foregroundStyle(.secondary)
          } else {
            Text(kind.inputKind == .wordBurst ? "请输入非负整数。" : "请输入有效的非负数字。")
              .foregroundStyle(.red)
          }
        }
        Section {
          Text("\(kind.explanation) 输入 0 会关闭该规则；应用后会退出挑战并重新开始练习。")
            .font(.caption)
            .foregroundStyle(.secondary)
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
            onApply(value)
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
