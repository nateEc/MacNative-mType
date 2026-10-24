import SwiftUI

struct WebsiteConfigStartupNotice: View {
  let state: WebsiteConfigStartupController.State
  let recover: () -> Void
  let continueUsingLegacy: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if case .failed(let message) = state {
        Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
      } else {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text(state == .restoring ? "正在恢复已保存的 Monkeytype 配置…" : "正在等待账户与窗口就绪，再恢复保存的配置…")
        }
      }
      HStack {
        if case .failed = state { Button("检查保存的配置…", action: recover) }
        Spacer()
        Button("使用 Typebar 设置继续", action: continueUsingLegacy)
      }
    }
    .font(.callout).padding(14)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    .accessibilityIdentifier("website-config-startup")
  }
}
