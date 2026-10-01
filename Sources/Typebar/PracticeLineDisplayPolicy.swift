import Foundation

enum PracticeLineDisplayPolicy {
  static func shouldShowAllLines(
    settingEnabled: Bool, tapeMode: PracticeTapeMode, testMode: TestMode,
    hasTimeLimit _: Bool
  ) -> Bool {
    guard settingEnabled, tapeMode == .off else { return false }
    return testMode == .words || testMode == .quote || testMode == .custom
  }
}
