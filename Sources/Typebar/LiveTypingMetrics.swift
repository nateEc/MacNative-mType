import Foundation

/// One consistent snapshot for the practice screen's native live metrics.
/// Visibility, sizing, color and opacity remain the view's responsibility.
struct LiveTypingMetrics: Equatable {
  let speed: String
  let rawSpeed: String
  let burst: String
  let accuracy: String
  let errorCount: Int?

  init(session: TypingSession, at date: Date, blindMode: Bool? = nil, unit: TypingSpeedUnit) {
    let isBlind = blindMode ?? session.configuration.rules.blindMode
    let rawWpm = session.rawWpm(at: date)
    speed = unit.formatted(wpm: isBlind ? rawWpm : session.wpm(at: date))
    rawSpeed = unit.formatted(wpm: rawWpm)
    burst = unit.formatted(wpm: session.burstWpm)
    accuracy = isBlind ? "100%" : "\(Int(session.liveAccuracyForDisplay.rounded(.down)))%"
    errorCount = isBlind ? nil : session.errors
  }
}
