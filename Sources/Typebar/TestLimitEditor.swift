import SwiftUI

enum OfficialTestLimitInput {
  /// JavaScript's largest exactly representable integer, preserving the
  /// reference configuration's Number semantics through native round trips.
  static let maximumValue = 9_007_199_254_740_991

  static func value(from text: String) -> Int? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let value = Int(trimmed), (0...maximumValue).contains(value) else {
      return nil
    }
    return value
  }
}

enum TestLimitKind {
  case time
  case words

  var title: String {
    switch self {
    case .time: "自定义时间"
    case .words: "自定义字数"
    }
  }

  var sectionTitle: String {
    switch self {
    case .time: "练习秒数"
    case .words: "练习词数"
    }
  }

  var unit: String {
    switch self {
    case .time: "秒"
    case .words: "词"
    }
  }
}

struct TestLimitEditor: View {
  @Environment(\.dismiss) private var dismiss
  let kind: TestLimitKind
  let onApply: (Int) -> Void
  @State private var text: String
  @FocusState private var inputFocused: Bool

  init(kind: TestLimitKind, initialValue: Int, onApply: @escaping (Int) -> Void) {
    self.kind = kind
    self.onApply = onApply
    _text = State(initialValue: String(max(0, initialValue)))
  }

  private var value: Int? { OfficialTestLimitInput.value(from: text) }

  var body: some View {
    NavigationStack {
      Form {
        Section(kind.sectionTitle) {
          TextField(kind.unit, text: $text)
            .focused($inputFocused)
          if let value {
            LabeledContent("将应用", value: value == 0 ? "无限" : "\(value) \(kind.unit)")
              .foregroundStyle(.secondary)
          } else {
            Text("请输入非负整数。")
              .foregroundStyle(.red)
          }
        }
        Section {
          Text("0 表示无限；大型有限测试会按需生成文本，不会一次性占用大量内存。应用后会退出挑战并重新开始练习。")
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
    .frame(width: 420, height: 270)
    .onAppear { inputFocused = true }
  }
}
