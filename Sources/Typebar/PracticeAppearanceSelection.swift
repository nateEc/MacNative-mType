import SwiftUI

/// Display consumers use the current window's profile, leaving native legacy
/// preferences and the completed result's scoring configuration untouched.
struct PracticeAppearanceSelection: Equatable {
  let progress: LiveProgressStyle, speed: LiveMetricStyle, accuracy: LiveMetricStyle, burst: LiveMetricStyle
  let color: LiveStatsColor, opacity: LiveStatsOpacity, unit: TypingSpeedUnit
  let alwaysShowDecimalPlaces: Bool, startGraphsAtZero: Bool, showTypingCompanion: Bool
  private let website: Bool
  @MainActor init(draft: WebsiteConfigNativeDraft?, settings: AppSettings) {
    let p = draft?.presentation; website = p != nil
    progress = p?.liveProgressStyle ?? settings.liveProgressStyle
    speed = p?.liveSpeedStyle ?? settings.liveSpeedStyle
    accuracy = p?.liveAccuracyStyle ?? settings.liveAccuracyStyle
    burst = p?.liveBurstStyle ?? settings.liveBurstStyle
    color = p?.liveStatsColor ?? settings.liveStatsColor
    opacity = p?.liveStatsOpacity ?? settings.liveStatsOpacity
    unit = p?.typingSpeedUnit ?? settings.typingSpeedUnit
    alwaysShowDecimalPlaces = p?.alwaysShowDecimalPlaces ?? settings.alwaysShowDecimalPlaces
    startGraphsAtZero = p?.startGraphsAtZero ?? settings.startGraphsAtZero
    showTypingCompanion = p?.showTypingCompanion ?? settings.showTypingCompanion
  }
  func foreground(theme: ResolvedTheme) -> Color {
    guard website else { return color.resolved(accent: theme.accent) }
    switch color {
    case .accent: return theme.accent
    case .secondary: return theme.secondaryText
    case .primary: return theme.text
    case .black: return .black
    }
  }
}
