import Foundation

/// A selected custom-word test can carry the existing one-hour/ten-thousand
/// dual bound without retaining challenge qualification. Never a global default.
struct CustomWordDurationSelection {
  private var selectedWordLimit: Int?
  private(set) var duration: TimeInterval?

  mutating func accept(_ configuration: TestConfiguration) {
    selectedWordLimit = nil
    duration = nil
    guard configuration.mode == .custom, configuration.customTextCompletion == .words,
      configuration.duration != nil, SettingsJSONConfigurationPolicy.isValid(configuration) else { return }
    selectedWordLimit = configuration.wordLimit
    duration = configuration.duration
  }

  mutating func reconcile(mode: TestMode, completion: CustomTextCompletion, wordLimit: Int) {
    guard mode == .custom, completion == .words, selectedWordLimit == wordLimit else {
      selectedWordLimit = nil
      duration = nil
      return
    }
  }

  func duration(mode: TestMode, completion: CustomTextCompletion, wordLimit: Int) -> TimeInterval? {
    mode == .custom && completion == .words && selectedWordLimit == wordLimit ? duration : nil
  }
}
