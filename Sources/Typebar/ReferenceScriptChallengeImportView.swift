import SwiftUI
import UniformTypeIdentifiers

/// One focused native handoff: identify the expected file, disclose result
/// storage, then let the user choose a file they have rights to use.
struct ReferenceScriptChallengeImportView: View {
  @Environment(\.dismiss) private var dismiss
  let title: String
  let specification: ReferenceScriptChallengePolicy.Specification
  let onVerified: (ReferenceScriptChallengePolicy.VerifiedScript) -> Bool

  @State private var acknowledgesRightsAndStorage = false
  @State private var importing = false
  @State private var importError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("导入挑战脚本", systemImage: "doc.text")
        .font(.title2.weight(.semibold))
      Text(title).font(.headline)
      VStack(alignment: .leading, spacing: 6) {
        Text("需要固定版本的纯文本文件")
          .font(.subheadline.weight(.medium))
        Text(specification.fileName)
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
        Text("Typebar 不附带或下载脚本；文件只会在你选择后读取并核对内容。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

      Toggle(isOn: $acknowledgesRightsAndStorage) {
        Text("我有权使用此文本，并了解保存成绩会保留完整提示，可能随我的备份或同步传输。")
          .fixedSize(horizontal: false, vertical: true)
      }
      if let importError {
        Label(importError, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .font(.caption)
          .fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Button("取消") { dismiss() }
        Spacer()
        Button("选择 TXT 文件…") { importing = true }
          .buttonStyle(.borderedProminent)
          .disabled(!acknowledgesRightsAndStorage)
      }
    }
    .padding(28)
    .frame(width: 500)
    .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText]) { result in
      do {
        let url = try result.get()
        let verified = try ReferenceScriptChallengePolicy.verifiedScript(
          at: url, for: specification)
        if onVerified(verified) {
          dismiss()
        } else {
          importError = "当前练习暂时不允许切换挑战；请先结束或退出本轮测试。"
        }
      } catch {
        importError = (error as? LocalizedError)?.errorDescription
          ?? "无法读取所选文件；请确认它是固定版本的 UTF-8 纯文本。"
      }
    }
  }
}
