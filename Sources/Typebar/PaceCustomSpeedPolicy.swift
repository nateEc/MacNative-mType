import Foundation

enum PaceCustomSpeedPolicy {
  static func isValid(_ wpm: Double) -> Bool { wpm.isFinite && wpm >= 0 }

  static func normalized(_ wpm: Double) -> Double { isValid(wpm) ? wpm : 100 }

  static func isLegacyRepresentable(_ wpm: Double) -> Bool {
    isValid(wpm) && (10...300).contains(wpm) && wpm.rounded(.towardZero) == wpm
  }

  static func canonicalWpm(displayedValue: Double, unit: TypingSpeedUnit) -> Double? {
    guard isValid(displayedValue) else { return nil }
    let wpm: Double
    switch unit {
    case .wpm: wpm = displayedValue
    case .cpm: wpm = displayedValue / 5
    case .wps: wpm = displayedValue * 60
    case .cps: wpm = displayedValue * 12
    case .wph: wpm = displayedValue / 60
    }
    return isValid(wpm) && (displayedValue == 0 || wpm > 0) ? wpm : nil
  }

  static func displayedValue(wpm: Double, unit: TypingSpeedUnit) -> Double? {
    guard isValid(wpm) else { return nil }
    let displayed: Double
    switch unit {
    case .wpm: displayed = wpm
    case .cpm: displayed = wpm * 5
    case .wps: displayed = wpm / 60
    case .cps: displayed = wpm / 12
    case .wph: displayed = wpm * 60
    }
    return isValid(displayed) && (wpm == 0 || displayed > 0) ? displayed : nil
  }

  static func parse(_ draft: String, unit: TypingSpeedUnit) -> Double? {
    guard let value = Double(draft.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
    return canonicalWpm(displayedValue: value, unit: unit)
  }

  @MainActor
  static func apply(_ wpm: Double, to settings: AppSettings, activateCustom: Bool) -> Bool {
    guard isValid(wpm) else { return false }
    if activateCustom {
      settings.paceGuideCustomWpm = wpm
      settings.paceGuideMode = .custom
    } else if wpm != settings.paceGuideCustomWpm {
      settings.paceGuideCustomWpm = wpm
      if settings.paceGuideMode == .off { settings.paceGuideMode = .custom }
    }
    return true
  }
}
