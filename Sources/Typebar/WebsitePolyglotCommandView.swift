import SwiftUI

/// Capture the opened publication, not whichever profile happens to be current
/// when an asynchronous edit finally reaches the workflow.
struct WebsitePolyglotCommandPresentation: Identifiable {
  let id: UUID
  let draft: WebsiteConfigNativeDraft
  init(publication: WebsiteConfigCommitCoordinator.Publication) {
    id = publication.applicationID; draft = publication.draft
  }
}

struct WebsitePolyglotCommandView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var form: WebsiteConfigPracticeEditForm
  let canApply: Bool
  let apply: @MainActor (WebsiteConfigPracticeEdit) async throws -> String

  init(presentation: WebsitePolyglotCommandPresentation, canApply: Bool,
    apply: @escaping @MainActor (WebsiteConfigPracticeEdit) async throws -> String) {
    self.init(form: .init(draft: presentation.draft), canApply: canApply, apply: apply)
  }
  init(form: WebsiteConfigPracticeEditForm, canApply: Bool,
    apply: @escaping @MainActor (WebsiteConfigPracticeEdit) async throws -> String) {
    _form = State(initialValue: form); self.canApply = canApply; self.apply = apply
  }
  var body: some View {
    @Bindable var form = form
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("修改多语组合").font(.title2.weight(.semibold))
        Spacer()
        Button("关闭") { form.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
      }
      Text("输入至少两个语言 ID，以单个空格分隔，例如 english german。")
        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      TextField("english german", text: $form.polyglotLanguages)
        .font(.system(.body, design: .monospaced)).textFieldStyle(.roundedBorder)
        .accessibilityLabel("多语语言 ID，以单个空格分隔")
        .accessibilityIdentifier("website-polyglot-command-input")
        .disabled(!canApply || form.isWorking)
      Text("保存组合不会自动启用 Polyglot。通常会重开练习；No Quit 活动时只保存，当前练习继续。")
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if let message = form.message {
        Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("website-polyglot-command-message")
      } else if !canApply {
        Text("配置已变化或正在准备，请关闭后重新打开此命令。")
          .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        if form.isWorking { ProgressView().controlSize(.small) }
        Spacer()
        Button("保存组合") { form.startPolyglotLanguages(apply: apply) }
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("website-polyglot-command-apply")
          .disabled(!canApply || form.isWorking)
      }
    }
    .padding(24).frame(minWidth: 460, idealWidth: 540)
    .onDisappear { form.cancel() }
  }
}
