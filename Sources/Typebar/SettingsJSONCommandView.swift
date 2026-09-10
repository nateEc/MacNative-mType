import AppKit
import SwiftUI

enum SettingsJSONCommandMode: String, Equatable {
  case importSettings
  case exportSettings

  var title: String {
    switch self {
    case .importSettings: "导入设置 JSON"
    case .exportSettings: "导出设置 JSON"
    }
  }
}

struct SettingsJSONCommandPresentation: Identifiable, Equatable {
  let id = UUID()
  let mode: SettingsJSONCommandMode
  let initialJSON: String
  let initialError: String?
}

struct SettingsJSONCommandView: View {
  let presentation: SettingsJSONCommandPresentation
  let onImport: (String) throws -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var json: String
  @State private var message: String?
  @State private var isError = false

  init(
    presentation: SettingsJSONCommandPresentation,
    onImport: @escaping (String) throws -> Void
  ) {
    self.presentation = presentation
    self.onImport = onImport
    _json = State(initialValue: presentation.initialJSON)
    _message = State(initialValue: presentation.initialError)
    _isError = State(initialValue: presentation.initialError != nil)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text(presentation.mode.title)
            .font(.title2.weight(.semibold))
          Text(description)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("关闭") { dismiss() }
          .keyboardShortcut(.cancelAction)
      }

      TextEditor(text: $json)
        .font(.system(.body, design: .monospaced))
        .scrollContentBackground(.hidden)
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
          RoundedRectangle(cornerRadius: 10)
            .stroke(.separator, lineWidth: 1)
        }
        .frame(minHeight: 330)
        .accessibilityLabel("设置 JSON")

      if let message {
        Label(message, systemImage: isError ? "exclamationmark.triangle" : "checkmark.circle")
          .font(.callout)
          .foregroundStyle(isError ? Color.red : Color.secondary)
      }

      HStack {
        Text("仅包含偏好设置与自定义主题、键盘布局；不含成绩、练习文本、凭据或本地文件。")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        actionButton
      }
    }
    .padding(24)
    .frame(minWidth: 680, idealWidth: 760, minHeight: 500)
  }

  private var description: String {
    switch presentation.mode {
    case .importSettings:
      "粘贴由 Typebar 导出的完整文档。内容通过校验后才会应用。"
    case .exportSettings:
      "复制这份版本化文档，可在另一台 Mac 的 Typebar 中导入。"
    }
  }

  @ViewBuilder
  private var actionButton: some View {
    switch presentation.mode {
    case .importSettings:
      Button("检查并应用") {
        do {
          try onImport(json)
          isError = false
          message = "设置已导入，当前练习已重新开始。"
        } catch {
          isError = true
          message = error.localizedDescription
        }
      }
      .keyboardShortcut(.defaultAction)
    case .exportSettings:
      Button("复制 JSON") {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(json, forType: .string) {
          isError = false
          message = "设置 JSON 已复制。"
        } else {
          isError = true
          message = "无法写入剪贴板，请在编辑器中手动复制。"
        }
      }
      .keyboardShortcut(.defaultAction)
    }
  }
}
