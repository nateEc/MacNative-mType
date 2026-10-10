import AppKit
import SwiftUI

/// A separate candidate row; empty composition still reserves one text line.
struct BelowCompositionPrompt: NSViewRepresentable {
  let text: String
  let font: NSFont
  let color: NSColor

  func makeNSView(context: Context) -> NSTextField {
    let view = NSTextField(wrappingLabelWithString: " ")
    view.alignment = .center
    view.isSelectable = false
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return view
  }

  func updateNSView(_ view: NSTextField, context: Context) {
    view.stringValue = text.isEmpty ? " " : text
    view.font = font
    view.textColor = color
    view.setAccessibilityLabel(text.isEmpty ? "组合输入候选行" : "正在组合：\(text)")
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
    let width = max(1, proposal.width ?? nsView.bounds.width)
    let height = nsView.cell?.cellSize(forBounds:
      .init(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height
      ?? font.boundingRectForFont.height
    return .init(width: width, height: ceil(max(height, font.ascender - font.descender)))
  }
}
