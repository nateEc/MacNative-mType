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

/// Keeps application-termination confirmation scoped to the active practice
/// windows. The state is value based so the multi-window behavior is covered
/// without requiring an AppKit event loop in client tests.
struct LongTestTerminationProtectionState {
  private var protectedWindowIdentifiers = Set<ObjectIdentifier>()
  private(set) var permitsCurrentTermination = false
  private(set) var isConfirmationInFlight = false

  var requiresConfirmation: Bool { !protectedWindowIdentifiers.isEmpty }

  mutating func update(windowIdentifier: ObjectIdentifier, requiresConfirmation: Bool) {
    if requiresConfirmation {
      protectedWindowIdentifiers.insert(windowIdentifier)
    } else {
      protectedWindowIdentifiers.remove(windowIdentifier)
    }
    if !self.requiresConfirmation, !isConfirmationInFlight {
      permitsCurrentTermination = false
    }
  }

  mutating func remove(windowIdentifier: ObjectIdentifier) {
    update(windowIdentifier: windowIdentifier, requiresConfirmation: false)
  }

  mutating func beginConfirmation() -> Bool {
    guard requiresConfirmation, !permitsCurrentTermination, !isConfirmationInFlight else {
      return false
    }
    isConfirmationInFlight = true
    return true
  }

  mutating func resolveConfirmation(approved: Bool) {
    isConfirmationInFlight = false
    permitsCurrentTermination = approved && requiresConfirmation
  }

  func protects(windowIdentifier: ObjectIdentifier) -> Bool {
    protectedWindowIdentifiers.contains(windowIdentifier)
  }
}

/// Connects the value state to real AppKit windows without retaining them.
/// Window delegates and the application delegate both run on the main actor.
@MainActor
final class LongTestTerminationProtectionRegistry {
  static let shared = LongTestTerminationProtectionRegistry()

  private final class WindowReference {
    weak var window: NSWindow?

    init(_ window: NSWindow) {
      self.window = window
    }
  }

  private var state = LongTestTerminationProtectionState()
  private var windows: [ObjectIdentifier: WindowReference] = [:]

  var requiresConfirmation: Bool {
    removeDeallocatedWindows()
    return state.requiresConfirmation
  }

  var permitsCurrentTermination: Bool { state.permitsCurrentTermination }
  var isConfirmationInFlight: Bool { state.isConfirmationInFlight }

  func update(window: NSWindow, requiresConfirmation: Bool) {
    let identifier = ObjectIdentifier(window)
    if requiresConfirmation {
      windows[identifier] = WindowReference(window)
    } else {
      windows[identifier] = nil
    }
    state.update(windowIdentifier: identifier, requiresConfirmation: requiresConfirmation)
  }

  func remove(window: NSWindow) {
    let identifier = ObjectIdentifier(window)
    windows[identifier] = nil
    state.remove(windowIdentifier: identifier)
  }

  /// Marks that a single application-level confirmation may begin.
  func beginConfirmation() -> Bool {
    removeDeallocatedWindows()
    return state.beginConfirmation()
  }

  /// Returns a protected, visible practice window for a document-modal sheet.
  /// A caller can fall back to an app-modal alert when none is available.
  func confirmationWindow() -> NSWindow? {
    removeDeallocatedWindows()
    if let keyWindow = NSApp.keyWindow,
       state.protects(windowIdentifier: ObjectIdentifier(keyWindow)) {
      return keyWindow
    }
    if let visibleWindow = windows.values.compactMap(\.window).first(where: \.isVisible) {
      return visibleWindow
    }
    return nil
  }

  func resolveConfirmation(approved: Bool) {
    state.resolveConfirmation(approved: approved)
  }

  private func removeDeallocatedWindows() {
    let deallocatedIdentifiers = windows.compactMap { identifier, reference in
      reference.window == nil ? identifier : nil
    }
    for identifier in deallocatedIdentifiers {
      windows[identifier] = nil
      state.remove(windowIdentifier: identifier)
    }
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
    context.coordinator.configure(requiresConfirmation: requiresConfirmation)
    DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
    return view
  }

  func updateNSView(_ view: NSView, context: Context) {
    context.coordinator.configure(requiresConfirmation: requiresConfirmation)
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
    private var requiresConfirmation = false

    func configure(requiresConfirmation: Bool) {
      self.requiresConfirmation = requiresConfirmation
      guard let window else { return }
      LongTestTerminationProtectionRegistry.shared.update(
        window: window, requiresConfirmation: requiresConfirmation)
    }

    func attach(to candidate: NSWindow?) {
      guard let candidate else { return }
      if window !== candidate {
        detach()
        window = candidate
      }
      LongTestTerminationProtectionRegistry.shared.update(
        window: candidate, requiresConfirmation: requiresConfirmation)
      guard candidate.delegate !== self else { return }
      forwardedDelegate = candidate.delegate
      candidate.delegate = self
    }

    func detach() {
      guard let window else { return }
      if window.delegate === self {
        window.delegate = forwardedDelegate
      }
      LongTestTerminationProtectionRegistry.shared.remove(window: window)
      self.window = nil
      forwardedDelegate = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
      if LongTestTerminationProtectionRegistry.shared.isConfirmationInFlight {
        return false
      }
      guard permitsForwardedDelegateClose(sender) else { return false }
      guard requiresConfirmation,
            !allowsConfirmedClose,
            !LongTestTerminationProtectionRegistry.shared.permitsCurrentTermination else {
        return true
      }
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
