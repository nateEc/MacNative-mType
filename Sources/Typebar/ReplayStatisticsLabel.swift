import AppKit
import SwiftUI

struct ReplayStatisticsLabel: NSViewRepresentable {
  let text: String
  let position: String

  func makeNSView(context: Context) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    label.textColor = .secondaryLabelColor
    label.alignment = .right
    label.setAccessibilityElement(true)
    label.setAccessibilityRole(.staticText)
    label.setAccessibilityIdentifier("replay.statistics")
    return label
  }

  func updateNSView(_ label: NSTextField, context: Context) {
    label.stringValue = text
    label.toolTip = position
    label.setAccessibilityValue(text)
    label.setAccessibilityHelp(position)
  }
}
