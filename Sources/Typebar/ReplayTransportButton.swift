import AppKit
import SwiftUI

/// Use the standard macOS control for transport keyboard/accessibility actions.
struct ReplayTransportButton: NSViewRepresentable {
  let title: String
  var enabled = true
  let action: () -> Void
  @Environment(\.isEnabled) private var environmentEnabled

  final class Coordinator: NSObject {
    var action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func pressed(_ sender: NSButton) { action() }
  }

  func makeCoordinator() -> Coordinator { Coordinator(action: action) }

  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.pressed(_:)))
    button.bezelStyle = .rounded
    button.setButtonType(.momentaryPushIn)
    button.setAccessibilityElement(true)
    button.setAccessibilityRole(.button)
    return button
  }

  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.action = action
    button.title = title
    button.setAccessibilityLabel(title)
    button.isEnabled = enabled && environmentEnabled
  }
}
