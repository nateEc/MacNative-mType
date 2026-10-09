import Foundation

/// Opt-in timing-only evidence for isolated QA packages. Never includes text,
/// account identifiers, calendar dates, or practice result payloads.
enum TimerDeliveryDiagnostics {
  enum Phase: String, CaseIterable {
    case clockStarted = "clock-started"
    case clockStopped = "clock-stopped"
    case lateDelivery = "late-delivery"
    case inputStarted = "input-started"
    case inputFinished = "input-finished"
  }

  private static let phaseOrigin = ProcessInfo.processInfo.systemUptime
  static func isEnabled(info: [String: Any], environment: [String: String]) -> Bool {
    QAStoreMode.usesInMemoryStore(info: info)
      && environment["TYPEBAR_QA_TIMER_DIAGNOSTICS"] == "1"
  }

  static let enabled = isEnabled(info: Bundle.main.infoDictionary ?? [:],
    environment: ProcessInfo.processInfo.environment)

  static func record(deliveryGap: TimeInterval, preflight: TimeInterval,
    elapsed: TimeInterval, previousSecond: Int, firstDueSecond: Int,
    severeCount: Int, failed: Bool) -> String {
    String(format: "typebar-timer deliveryGap=%.6f preflight=%.6f elapsed=%.6f previous=%d due=%d drift=%.6f severe=%d failed=%d\n",
      locale: Locale(identifier: "en_US_POSIX"), deliveryGap, preflight, elapsed,
      previousSecond, firstDueSecond, elapsed - Double(firstDueSecond), severeCount, failed ? 1 : 0)
  }

  static func phaseRecord(phase: Phase, offset: TimeInterval, duration: TimeInterval,
    hasStarted: Bool, isFinished: Bool) -> String {
    String(format: "typebar-phase phase=%@ offset=%.6f duration=%.6f started=%d finished=%d\n",
      locale: Locale(identifier: "en_US_POSIX"), phase.rawValue, offset, duration,
      hasStarted ? 1 : 0, isFinished ? 1 : 0)
  }

  static func trace(_ phase: Phase, duration: TimeInterval = 0,
    hasStarted: Bool, isFinished: Bool) {
    guard enabled else { return }
    let origin = phaseOrigin
    let offset = ProcessInfo.processInfo.systemUptime - origin
    let line = phaseRecord(phase: phase, offset: max(0, offset), duration: duration,
      hasStarted: hasStarted, isFinished: isFinished)
    try? FileHandle.standardError.write(contentsOf: Data(line.utf8))
  }
}
