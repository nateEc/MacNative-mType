import SwiftUI

struct PaceGuideSpeedEditor: View {
  @Environment(\.dismiss) private var dismiss
  let unit: TypingSpeedUnit
  let onApply: (Int) -> Void
  @State private var displayedSpeed: Double
  @FocusState private var speedFocused: Bool

  init(unit: TypingSpeedUnit, initialWpm: Int, onApply: @escaping (Int) -> Void) {
    self.unit = unit
    self.onApply = onApply
    _displayedSpeed = State(initialValue: unit.converted(wpm: initialWpm))
  }

  private var canonicalWpm: Int {
    unit.canonicalWpm(fromDisplayedValue: displayedSpeed)
  }

  private var isValid: Bool {
    displayedSpeed.isFinite
      && PaceGuidePolicy.minimumWpm...PaceGuidePolicy.maximumWpm ~= canonicalWpm
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("目标速度") {
          TextField(
            unit.displayName, value: $displayedSpeed,
            format: .number.precision(.fractionLength(0...2)))
            .focused($speedFocused)
          LabeledContent("换算后", value: "\(canonicalWpm) WPM")
            .foregroundStyle(isValid ? Color.secondary : Color.red)
        }
        Section {
          Text("允许范围为 \(PaceGuidePolicy.minimumWpm)–\(PaceGuidePolicy.maximumWpm) WPM；应用后会用当前配置重新生成练习。")
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
            onApply(canonicalWpm)
            dismiss()
          }
          .keyboardShortcut(.defaultAction)
          .disabled(!isValid)
        }
      }
    }
    .frame(width: 420, height: 250)
    .onAppear { speedFocused = true }
  }
}
