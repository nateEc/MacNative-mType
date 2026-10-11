import Foundation

/// Explicit QA-only, bounded evidence; never accepts prompt or input text.
enum CompositionProjectionDiagnostics {
  struct Budget {
    private var remaining = 20

    mutating func admit(enabled: Bool, expected: Bool, available: Bool, marked: Bool) -> Bool {
      guard enabled, expected, !available, marked, remaining > 0 else { return false }
      remaining -= 1
      return true
    }
  }

  static func isEnabled(environment: [String: String]) -> Bool {
    environment["TYPEBAR_QA_IN_MEMORY_STORE"] == "1"
      && environment["TYPEBAR_QA_COMPOSITION_DIAGNOSTICS"] == "1"
  }

  static func record(started: Bool, finished: Bool, fieldAvailable: Bool) -> String {
    "typebar-composition projection=unavailable started=\(started) finished=\(finished) fieldAvailable=\(fieldAvailable)\n"
  }

  @MainActor private static var budget = Budget()
  private static let enabled = isEnabled(environment: ProcessInfo.processInfo.environment)

  @MainActor static func observe(expected: Bool, available: Bool, marked: Bool,
    session: TypingSession) {
    #if DEBUG
    guard budget.admit(enabled: enabled,
      expected: expected, available: available, marked: marked) else { return }
    let line = record(started: session.hasStarted, finished: session.isFinished,
      fieldAvailable: session.promptCompositionField != nil)
    try? FileHandle.standardError.write(contentsOf: Data(line.utf8))
    #endif
  }
}
