import SwiftUI

enum ActiveResultTagEditorPolicy {
  static func candidate(rawTag: String, currentTags: [String]) -> String? {
    guard currentTags.count < ResultTagPolicy.maximumCount else { return nil }
    let updated = ResultTagPolicy.appending(rawTag, to: currentTags)
    guard updated.count > currentTags.count else { return nil }
    return updated.last
  }
}

struct ActiveResultTagEditor: View {
  @Environment(\.dismiss) private var dismiss
  let currentTags: [String]
  let onApply: (String) -> Void
  @State private var text = ""
  @FocusState private var inputFocused: Bool

  private var candidate: String? {
    ActiveResultTagEditorPolicy.candidate(rawTag: text, currentTags: currentTags)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("标签名称") {
          TextField("最多 \(ResultTagPolicy.maximumLength) 个字符", text: $text)
            .focused($inputFocused)
          if currentTags.count >= ResultTagPolicy.maximumCount {
            Text("已达到 \(ResultTagPolicy.maximumCount) 个活动标签；请先关闭一个标签。")
              .foregroundStyle(.red)
          } else if !text.isEmpty, candidate == nil {
            Text("请输入新的非空标签，且不要与现有标签重复。")
              .foregroundStyle(.red)
          }
        }
        Section {
          Text("标签只保存在 Typebar 数据中，并从下一次开始的练习生效；当前练习保持原有标签。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
      .navigationTitle("新建活动标签")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
            .keyboardShortcut(.cancelAction)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("创建并启用") {
            guard let candidate else { return }
            onApply(candidate)
            dismiss()
          }
          .keyboardShortcut(.defaultAction)
          .disabled(candidate == nil)
        }
      }
    }
    .frame(width: 430, height: 260)
    .onAppear { inputFocused = true }
  }
}
