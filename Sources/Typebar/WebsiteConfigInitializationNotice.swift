import SwiftUI

struct WebsiteConfigInitializationNotice: View {
  let message: String
  let retry: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("未能开始新一轮", systemImage: "exclamationmark.triangle")
        .font(.callout.weight(.semibold)).foregroundStyle(.orange)
      Text(verbatim: message).font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
      Button("重新开始", action: retry).buttonStyle(.bordered).keyboardShortcut("r", modifiers: .command)
    }
    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
  }
}

/// Replace only the typing region; the page's owner and accepted session live
/// above this boundary and remain available for an explicit retry.
struct WebsiteConfigInitializationRegion<Content: View>: View {
  let message: String?
  let retry: () -> Void
  let content: () -> Content
  init(message: String?, retry: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
    self.message = message; self.retry = retry; self.content = content
  }
  var body: some View {
    if let message { WebsiteConfigInitializationNotice(message: message, retry: retry) }
    else { content() }
  }
}
