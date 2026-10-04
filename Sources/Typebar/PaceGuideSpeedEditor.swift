import SwiftUI

struct PaceGuideSpeedEditor: View {
  @Environment(\.dismiss) private var dismiss
  let unit: TypingSpeedUnit
  let onApply: (Double) -> Void
  private let initialWpm: Double
  private let initialDraft: String
  @State private var draft: String
  @FocusState private var speedFocused: Bool

  init(unit: TypingSpeedUnit, initialWpm: Double, onApply: @escaping (Double) -> Void) {
    // Preserve an enormous canonical target even when its displayed unit
    // multiplication would overflow. The editor then explicitly labels WPM.
    self.unit = PaceCustomSpeedPolicy.displayedValue(wpm: initialWpm, unit: unit) != nil ? unit : .wpm
    self.onApply = onApply
    self.initialWpm = initialWpm
    self.initialDraft = String(PaceCustomSpeedPolicy.displayedValue(wpm: initialWpm, unit: self.unit) ?? initialWpm)
    _draft = State(initialValue: initialDraft)
  }

  private var canonicalWpm: Double? {
    if draft == initialDraft, PaceCustomSpeedPolicy.isValid(initialWpm) { return initialWpm }
    return PaceCustomSpeedPolicy.parse(draft, unit: unit)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("目标速度") {
          TextField(unit.displayName, text: $draft)
            .focused($speedFocused)
          LabeledContent("换算后", value: canonicalWpm.map { "\($0) WPM" } ?? "请输入非负有限数字")
            .foregroundStyle(canonicalWpm != nil ? Color.secondary : Color.red)
        }
        Section {
          Text("可输入非负小数，没有 300 WPM 上限；低于 1 WPM 时不显示节奏目标。应用只更新节奏，不清空本轮输入。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
      .navigationTitle("自定义节奏")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
            .keyboardShortcut(.cancelAction)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("应用") {
            guard let canonicalWpm else { return }
            onApply(canonicalWpm)
            dismiss()
          }
          .keyboardShortcut(.defaultAction)
          .disabled(canonicalWpm == nil)
        }
      }
    }
    .frame(width: 420, height: 250)
    .onAppear { speedFocused = true }
  }
}
