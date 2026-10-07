import Foundation

enum PracticeLineDisplayPolicy {
  static func shouldShowAllLines(
    settingEnabled: Bool, tapeMode: PracticeTapeMode, configuration: TestConfiguration
  ) -> Bool {
    guard settingEnabled, tapeMode == .off else { return false }
    switch configuration.mode {
    case .time: return false
    case .custom:
      return configuration.customTextCompletion != .time && !configuration.isInfinite
    case .words, .quote, .zen: return true
    }
  }
}
