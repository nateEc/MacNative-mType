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
  var accessibilityLabel = "只读配置 JSON"
  var accessibilityIdentifier = "website-config-manual-copy"
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.documentView = WebsiteConfigCopyTextView(frame: scroll.bounds)
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let text = scroll.documentView as? WebsiteConfigCopyTextView else { return }
    text.string = json
    text.setAccessibilityLabel(accessibilityLabel)
    text.setAccessibilityIdentifier(accessibilityIdentifier)
  }
}

final class WebsiteConfigCopyTextView: NSTextView {
  override init(frame frameRect: NSRect, textContainer container: NSTextContainer? = nil) {
    let resolved = container ?? NSTextContainer(size: .init(width: frameRect.width, height: .greatestFiniteMagnitude))
    let storage = container == nil ? NSTextStorage() : nil
    if let storage {
      let layout = NSLayoutManager()
      storage.addLayoutManager(layout)
      layout.addTextContainer(resolved)
    }
    super.init(frame: frameRect, textContainer: resolved)
    // The text view must adopt the complete network before its temporary owner is released.
    withExtendedLifetime(storage) {}
    isEditable = false
    isSelectable = true
    isRichText = false
    isVerticallyResizable = true
    isHorizontallyResizable = false
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
