import Foundation

/// Opt-in timing-only evidence for isolated QA packages. Never includes text,
/// account identifiers, calendar dates, or practice result payloads.
enum TimerDeliveryDiagnostics {
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
}
