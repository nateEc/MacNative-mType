import AppKit
import SwiftUI

/// Mirrors the reference before-unload prompt for an active long test. A
/// completed, abandoned, or short test closes normally.
enum LongTestCloseProtectionPolicy {
  static func requiresConfirmation(for session: TypingSession, savedLongText: Bool = false) -> Bool {
    session.hasStarted && !session.isFinished
      && QuickRestartSafetyPolicy.requiresShift(
        for: session.configuration, savedLongText: savedLongText)
  }
}

/// Adds close confirmation without replacing or dropping the window delegate
/// installed by SwiftUI. AppKit declares `NSWindow.delegate` as weak and calls
/// its optional `windowShouldClose(_:)` callback before closing a window.
struct WindowCloseConfirmationBridge: NSViewRepresentable {
  let requiresConfirmation: Bool

  func makeCoordinator() -> Coordinator { .init() }

  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    context.coordinator.requiresConfirmation = requiresConfirmation
    DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
    return view
  }

  func updateNSView(_ view: NSView, context: Context) {
    context.coordinator.requiresConfirmation = requiresConfirmation
    DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
  }

  static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
    coordinator.detach()
  }

  @MainActor
  final class Coordinator: NSObject, NSWindowDelegate {
    private weak var window: NSWindow?
    nonisolated(unsafe) private weak var forwardedDelegate: (any NSWindowDelegate)?
    private var isPresentingConfirmation = false
    private var allowsConfirmedClose = false
    var requiresConfirmation = false

    func attach(to candidate: NSWindow?) {
      guard let candidate else { return }
      if window !== candidate {
        detach()
        window = candidate
      }
      guard candidate.delegate !== self else { return }
      forwardedDelegate = candidate.delegate
      candidate.delegate = self
    }

    func detach() {
      guard let window else { return }
      if window.delegate === self {
        window.delegate = forwardedDelegate
      }
      self.window = nil
      forwardedDelegate = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
      guard permitsForwardedDelegateClose(sender) else { return false }
      guard requiresConfirmation, !allowsConfirmedClose else { return true }
      guard !isPresentingConfirmation else { return false }

      isPresentingConfirmation = true
      let alert = NSAlert()
      alert.messageText = "退出长测试？"
      alert.informativeText = "关闭窗口会丢失本次尚未完成的输入。"
      alert.addButton(withTitle: "继续关闭")
      alert.addButton(withTitle: "取消")
      alert.beginSheetModal(for: sender) { [weak self, weak sender] response in
        guard let self else { return }
        self.isPresentingConfirmation = false
        guard response == .alertFirstButtonReturn, let sender else { return }
        self.allowsConfirmedClose = true
        sender.performClose(nil)
        self.allowsConfirmedClose = false
      }
      return false
    }

    nonisolated override func responds(to selector: Selector!) -> Bool {
      if super.responds(to: selector) { return true }
      return forwardedDelegate?.responds(to: selector) == true
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
      guard !super.responds(to: selector) else { return super.forwardingTarget(for: selector) }
      guard forwardedDelegate?.responds(to: selector) == true else {
        return super.forwardingTarget(for: selector)
      }
      return forwardedDelegate
    }

    private func permitsForwardedDelegateClose(_ sender: NSWindow) -> Bool {
      forwardedDelegate?.windowShouldClose?(sender) ?? true
    }
  }
}
