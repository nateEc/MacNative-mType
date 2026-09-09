import SwiftUI

struct KeyboardGuideScaleEditor: View {
  @Environment(\.dismiss) private var dismiss
  let onApply: (Double) -> Void
  @State private var scale: Double
  @FocusState private var scaleFocused: Bool

  init(initialScale: Double, onApply: @escaping (Double) -> Void) {
    self.onApply = onApply
    _scale = State(initialValue: KeyboardGuideScalePolicy.normalized(initialScale))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("键盘提示大小") {
          TextField(
            "倍数", value: $scale,
            format: .number.precision(.fractionLength(1)))
            .focused($scaleFocused)
          Stepper(
            "\(scale, format: .number.precision(.fractionLength(1)))×",
            value: $scale, in: KeyboardGuideScalePolicy.range, step: 0.1)
        }
        Section {
          Text("允许范围为 0.5–3.5 倍，且必须使用 0.1 的步长。应用后立即更新屏幕键盘，不会重开当前练习。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
      .navigationTitle("键盘提示大小")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
            .keyboardShortcut(.cancelAction)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("应用") {
            onApply(scale)
            dismiss()
          }
          .keyboardShortcut(.defaultAction)
          .disabled(!KeyboardGuideScalePolicy.isValidInput(scale))
        }
      }
    }
    .frame(width: 420, height: 270)
    .onAppear { scaleFocused = true }
  }
}
