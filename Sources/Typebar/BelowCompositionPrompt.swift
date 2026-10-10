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
    let displayed = collapsedWhitespace
    view.stringValue = displayed.isEmpty ? " " : displayed
    view.font = font
    view.textColor = color
    view.setAccessibilityLabel(text.isEmpty ? "组合输入候选行" : "正在组合：\(text)")
  }

  // The reference's normal CSS whitespace collapses ASCII spaces, tabs and LF.
  // Keep the original candidate for accessibility and never alter input state.
  // Dynamic CR is retained in the raw candidate but has zero advance in WebKit.
  private var collapsedWhitespace: String {
    var result = String.UnicodeScalarView()
    var pendingSpace = false
    var hasLineContent = false
    for scalar in text.unicodeScalars {
      if scalar == "\r" { continue }
      if scalar == " " || scalar == "\t" || scalar == "\n" {
        pendingSpace = hasLineContent
      } else {
        if pendingSpace { result.append(" ") }
        result.append(scalar)
        pendingSpace = false
        hasLineContent = true
      }
    }
    return String(result)
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
    let width = max(1, proposal.width ?? nsView.bounds.width)
    let height = nsView.cell?.cellSize(forBounds:
      .init(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height
      ?? font.boundingRectForFont.height
    return .init(width: width, height: ceil(max(height, font.ascender - font.descender)))
  }
}
