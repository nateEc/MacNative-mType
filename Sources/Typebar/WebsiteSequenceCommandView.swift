import SwiftUI

enum WebsiteSequenceCommandKind: CaseIterable {
  case polyglot, layoutFluid
  var title: String { self == .polyglot ? "修改多语组合" : "修改布局序列" }
  var placeholder: String { self == .polyglot ? "english german" : "qwerty dvorak colemak" }
  var inputHelp: String {
    self == .polyglot ? "输入至少两个语言 ID，以单个空格分隔，例如 english german。"
      : "输入 2 至 15 个布局 ID，以单个空格分隔，例如 qwerty dvorak。"
  }
  var behaviorHelp: String {
    self == .polyglot ? "保存组合不会自动启用 Polyglot。通常会重开练习；No Quit 活动时只保存，当前练习继续。"
      : "保存序列不会自动启用 Layoutfluid。已启用时保存会重开，未启用时当前练习继续；No Quit 活动时不能修改。"
  }
  var inputLabel: String { self == .polyglot ? "多语语言 ID，以单个空格分隔" : "布局 ID，以单个空格分隔" }
  var buttonTitle: String { self == .polyglot ? "保存组合" : "保存布局序列" }
  var accessibilityPrefix: String { self == .polyglot ? "website-polyglot-command" : "website-layoutfluid-command" }
  @MainActor
  func submit(_ form: WebsiteConfigPracticeEditForm,
    apply: @escaping @MainActor (WebsiteConfigPracticeEdit) async throws -> String) {
    switch self {
    case .polyglot: form.startPolyglotLanguages(apply: apply)
    case .layoutFluid: form.startLayoutFluidLayouts(apply: apply)
    }
  }
}

/// Capture the opened publication, not whichever profile happens to be current
/// when an asynchronous edit finally reaches the workflow.
struct WebsiteSequenceCommandPresentation: Identifiable {
  let id: UUID
  let draft: WebsiteConfigNativeDraft
  let kind: WebsiteSequenceCommandKind
  init(publication: WebsiteConfigCommitCoordinator.Publication, kind: WebsiteSequenceCommandKind = .polyglot) {
    id = publication.applicationID; draft = publication.draft; self.kind = kind
  }
}

struct WebsiteSequenceCommandView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var form: WebsiteConfigPracticeEditForm
  let canApply: Bool
  let kind: WebsiteSequenceCommandKind
  let apply: @MainActor (WebsiteConfigPracticeEdit) async throws -> String

  init(presentation: WebsiteSequenceCommandPresentation, canApply: Bool,
    apply: @escaping @MainActor (WebsiteConfigPracticeEdit) async throws -> String) {
    self.init(form: .init(draft: presentation.draft), kind: presentation.kind, canApply: canApply, apply: apply)
  }
  init(form: WebsiteConfigPracticeEditForm, kind: WebsiteSequenceCommandKind = .polyglot, canApply: Bool,
    apply: @escaping @MainActor (WebsiteConfigPracticeEdit) async throws -> String) {
    _form = State(initialValue: form); self.kind = kind; self.canApply = canApply; self.apply = apply
  }
  var body: some View {
    let input = Binding<String>(get: {
      kind == .polyglot ? form.polyglotLanguages : form.layoutFluidLayouts
    }, set: { value in
      if kind == .polyglot { form.polyglotLanguages = value } else { form.layoutFluidLayouts = value }
    })
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(kind.title).font(.title2.weight(.semibold))
        Spacer()
        Button("关闭") { form.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
      }
      Text(kind.inputHelp)
        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      TextField(kind.placeholder, text: input)
        .font(.system(.body, design: .monospaced)).textFieldStyle(.roundedBorder)
        .accessibilityLabel(kind.inputLabel)
        .accessibilityIdentifier(kind.accessibilityPrefix + "-input")
        .disabled(!canApply || form.isWorking)
      Text(kind.behaviorHelp)
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if let message = form.message {
        Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier(kind.accessibilityPrefix + "-message")
      } else if !canApply {
        Text("配置已变化或正在准备，请关闭后重新打开此命令。")
          .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        if form.isWorking { ProgressView().controlSize(.small) }
        Spacer()
        Button(kind.buttonTitle) { kind.submit(form, apply: apply) }
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier(kind.accessibilityPrefix + "-apply")
          .disabled(!canApply || form.isWorking)
      }
    }
    .padding(24).frame(minWidth: 460, idealWidth: 540)
    .onDisappear { form.cancel() }
  }
}
