import AppKit
import OSLog

/// Bounded, explicit instrumentation for an isolated debug QA package. The
/// record schema accepts counts and flags, never prompt or candidate text.
enum NativeTextInputDiagnostics {
  enum Phase: String {
    case keyDown, insert, marked, unmark, retired
  }

  struct Budget {
    private var remaining = 96
    mutating func admit(enabled: Bool) -> Bool {
      guard enabled, remaining > 0 else { return false }
      remaining -= 1
      return true
    }
  }

  static func isEnabled(info: [String: Any], environment: [String: String]) -> Bool {
    QAStoreMode.usesInMemoryStore(info: info)
      && environment["TYPEBAR_QA_NATIVE_INPUT_DIAGNOSTICS"] == "1"
  }

  static func record(phase: Phase, keyCode: Int = -1, units: Int = -1,
    basicUnits: Int = -1, option: Bool = false, shift: Bool = false,
    command: Bool = false, control: Bool = false,
    admitted: Bool, retired: Bool, marked: Bool,
    applicationActive: Bool = false, windowKey: Bool = false,
    firstResponder: Bool = false, contextOwner: Int = -1) -> String {
    "phase=\(phase.rawValue) key=\(keyCode) units=\(units) basicUnits=\(basicUnits) option=\(option) shift=\(shift) command=\(command) control=\(control) admitted=\(admitted) retired=\(retired) marked=\(marked) applicationActive=\(applicationActive) windowKey=\(windowKey) firstResponder=\(firstResponder) contextOwner=\(contextOwner)"
  }

  #if DEBUG
  private static let enabled = isEnabled(info: Bundle.main.infoDictionary ?? [:],
    environment: ProcessInfo.processInfo.environment)
  private static let logger = Logger(subsystem: "app.typebar.qa.native-input", category: "delivery")
  @MainActor private static var budget = Budget()

  @MainActor static func keyDown(_ event: NSEvent, input: TypingInputView) {
    guard enabled, event.type == .keyDown else { return }
    emit(record(phase: .keyDown, keyCode: Int(event.keyCode),
      units: event.characters?.utf16.count ?? -1,
      basicUnits: event.charactersIgnoringModifiers?.utf16.count ?? -1,
      option: event.modifierFlags.contains(.option), shift: event.modifierFlags.contains(.shift),
      command: event.modifierFlags.contains(.command), control: event.modifierFlags.contains(.control),
      admitted: input.acceptsTextInput, retired: input.isRetired, marked: input.hasMarkedText(),
      applicationActive: NSApp?.isActive == true, windowKey: input.window?.isKeyWindow == true,
      firstResponder: input.window?.firstResponder === input, contextOwner: contextOwner(input)))
  }

  @MainActor static func observe(_ phase: Phase, value: Any? = nil, input: TypingInputView) {
    guard enabled else { return }
    let units = (value as? NSAttributedString)?.length ?? (value as? String)?.utf16.count ?? -1
    emit(record(phase: phase, units: units, admitted: input.acceptsTextInput,
      retired: input.isRetired, marked: input.hasMarkedText(),
      applicationActive: NSApp?.isActive == true, windowKey: input.window?.isKeyWindow == true,
      firstResponder: input.window?.firstResponder === input, contextOwner: contextOwner(input)))
  }

  @MainActor private static func contextOwner(_ input: TypingInputView) -> Int {
    guard let current = NSTextInputContext.current else { return -1 }
    return (current.client as AnyObject) === input ? 1 : 0
  }

  @MainActor private static func emit(_ line: String) {
    guard budget.admit(enabled: enabled) else { return }
    logger.notice("\(line, privacy: .public)")
  }
  #endif
}
