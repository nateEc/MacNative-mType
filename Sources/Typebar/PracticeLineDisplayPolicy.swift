import Foundation

enum PracticeLineDisplayPolicy {
  static func shouldShowAllLines(
    settingEnabled: Bool, tapeMode: PracticeTapeMode, testMode: TestMode,
    hasTimeLimit: Bool
  ) -> Bool {
    guard settingEnabled, tapeMode == .off, !hasTimeLimit else { return false }
    return testMode == .words || testMode == .quote || testMode == .custom
  }
}
