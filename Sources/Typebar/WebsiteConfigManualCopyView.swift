import AppKit
import SwiftUI

struct WebsiteConfigManualCopyView: View {
  let json: String
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("配置 JSON").font(.title2.weight(.semibold))
        Spacer()
        Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      Text("点击文本可全选，然后按 ⌘C 手动复制。")
        .foregroundStyle(.secondary)
      WebsiteConfigReadOnlyText(json: json).frame(minHeight: 330)
    }
    .padding(24)
    .frame(minWidth: 680, idealWidth: 760, minHeight: 440)
  }
}

struct WebsiteConfigReadOnlyText: NSViewRepresentable {
  let json: String
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.documentView = WebsiteConfigCopyTextView(frame: scroll.bounds)
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    (scroll.documentView as? WebsiteConfigCopyTextView)?.string = json
  }
}

final class WebsiteConfigCopyTextView: NSTextView {
  override init(frame frameRect: NSRect, textContainer container: NSTextContainer? = nil) {
    super.init(frame: frameRect, textContainer: container)
    isEditable = false
    isSelectable = true
    isRichText = false
    isVerticallyResizable = true
    autoresizingMask = [.width]
    textContainer?.widthTracksTextView = true
    textContainerInset = NSSize(width: 10, height: 10)
    font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    setAccessibilityLabel("只读配置 JSON")
    setAccessibilityIdentifier("website-config-manual-copy")
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
    selectAll(nil)
  }
}
