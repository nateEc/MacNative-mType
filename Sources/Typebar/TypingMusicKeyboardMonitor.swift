import AppKit
import IOKit.hidsystem

/// App-local keyboard observation; it never forwards text or triggers audio.
@MainActor
final class TypingMusicKeyboardMonitor: NSObject {
  typealias Handler = @MainActor (NSEvent) -> NSEvent?
  typealias Install = @MainActor (NSEvent.EventTypeMask, @escaping Handler) -> Any?
  private let sound: TypingFeedbackSound
  private let install: Install
  private let remove: @MainActor (Any) -> Void
  private let modifierFlags: @MainActor () -> NSEvent.ModifierFlags
  private let practiceScope: @MainActor () -> UUID?
  private let notificationCenter: NotificationCenter
  private var activePracticeScope: UUID?
  private var token: Any?
  private var generation: UUID?
  // Physical transition history deliberately survives practice resets. The
  // sound controller owns the separately resettable logical Shift sides.
  private var pressedModifierKeys: Set<UInt16> = []

  init(sound: TypingFeedbackSound = .shared,
    install: @escaping Install = { NSEvent.addLocalMonitorForEvents(matching: $0, handler: $1) },
    remove: @escaping @MainActor (Any) -> Void = { NSEvent.removeMonitor($0) },
    modifierFlags: @escaping @MainActor () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags },
    practiceScope: @escaping @MainActor () -> UUID? = { TypingMusicPracticeScopeRegistry.shared.currentIdentifier },
    notificationCenter: NotificationCenter = .default) {
    self.sound = sound
    self.install = install
    self.remove = remove
    self.modifierFlags = modifierFlags
    self.practiceScope = practiceScope
    self.notificationCenter = notificationCenter
    super.init()
  }

  func start() {
    guard generation == nil else { return }
    let current = UUID()
    generation = current
    pressedModifierKeys.removeAll(keepingCapacity: true)
    activePracticeScope = practiceScope()
    // Caps Lock is observable even before the first key event. Practice Shift
    // starts clear, as it does when the reference initializes its test page.
    sound.updateModifierFlags(modifierFlags().intersection(.capsLock))
    let installed = install([.keyDown, .flagsChanged]) { [weak self] event in
      guard let self, self.generation == current else { return event }
      if event.type == .keyDown || event.type == .flagsChanged { self.refreshPracticeScope() }
      switch event.type {
      case .keyDown:
        self.sound.recordKeyDown(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
      case .flagsChanged:
        self.recordModifierEvent(event)
      default: break
      }
      return event
    }
    if generation == current {
      token = installed
      if installed == nil { generation = nil }
      else {
        for name in [NSWindow.didBecomeKeyNotification, TypingMusicPracticeScopeRegistry.didChange] {
          notificationCenter.addObserver(self, selector: #selector(scopeChanged(_:)), name: name, object: nil)
        }
        // Reconcile a page change during a synchronous registration callback.
        refreshPracticeScope()
      }
    } else if let installed {
      // A synchronous stop during registration must not leak the new token.
      remove(installed)
    }
  }

  /// Owned by the application delegate, not individual windows. AppKit asks
  /// that monitors be removed explicitly, before their owner's destruction.
  func stop() {
    generation = nil
    notificationCenter.removeObserver(self)
    activePracticeScope = nil
    pressedModifierKeys.removeAll(keepingCapacity: true)
    let installed = token
    token = nil
    if let installed { remove(installed) }
  }

  func refreshCapsLock() {
    guard generation != nil else { return }
    sound.synchronizeCapsLock(modifierFlags().contains(.capsLock))
  }

  func refreshPracticeScope() {
    guard generation != nil else { return }
    let selected = practiceScope()
    guard selected != activePracticeScope else { return }
    activePracticeScope = selected
    sound.resetPracticeShift()
  }

  @objc private func scopeChanged(_ notification: Notification) { refreshPracticeScope() }

  private func recordModifierEvent(_ event: NSEvent) {
    if event.keyCode == 57 {
      // Caps Lock flags change on both toggle directions, not on a normal
      // press/release pair. Even toggle-off is a non-piano key press.
      sound.recordKeyDown(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
      return
    }
    guard let modifier = Self.modifier(for: event.keyCode) else {
      sound.synchronizeCapsLock(event.modifierFlags.contains(.capsLock))
      return
    }
    let hardwareBits = event.modifierFlags.rawValue & modifier.familyBits
    let isDown: Bool
    if hardwareBits != 0 {
      isDown = event.modifierFlags.rawValue & modifier.keyBit != 0
    } else if !event.modifierFlags.contains(modifier.flag) {
      isDown = false
    } else {
      // Synthesized events may omit device-dependent flags. Use the observed
      // side's transitions rather than interpreting a held opposite side as
      // a fresh press. Real device flags are authoritative when present.
      isDown = !pressedModifierKeys.contains(event.keyCode)
    }
    if isDown {
      pressedModifierKeys.insert(event.keyCode)
    } else {
      pressedModifierKeys.remove(event.keyCode)
    }
    sound.recordModifierTransition(keyCode: event.keyCode, isDown: isDown, modifierFlags: event.modifierFlags,
      tracksPracticeShift: activePracticeScope != nil)
  }

  private static func modifier(for code: UInt16)
    -> (flag: NSEvent.ModifierFlags, keyBit: UInt, familyBits: UInt)? {
    let flag: NSEvent.ModifierFlags
    let left: Int32, right: Int32
    let isLeft: Bool
    switch code {
    case 56, 60:
      flag = .shift; left = NX_DEVICELSHIFTKEYMASK; right = NX_DEVICERSHIFTKEYMASK; isLeft = code == 56
    case 59, 62:
      flag = .control; left = NX_DEVICELCTLKEYMASK; right = NX_DEVICERCTLKEYMASK; isLeft = code == 59
    case 58, 61:
      flag = .option; left = NX_DEVICELALTKEYMASK; right = NX_DEVICERALTKEYMASK; isLeft = code == 58
    case 55, 54:
      flag = .command; left = NX_DEVICELCMDKEYMASK; right = NX_DEVICERCMDKEYMASK; isLeft = code == 55
    default: return nil
    }
    return (flag, UInt(isLeft ? left : right), UInt(left | right))
  }
}
