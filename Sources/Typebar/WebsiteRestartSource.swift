import Foundation

enum WebsiteRestartSource: String, Decodable {
  case testPage, resultPage
  static func capture(outcome: TestOutcome, alreadyDeparted: Bool) -> Self {
    guard !alreadyDeparted else { return .testPage }
    switch outcome {
    case .completed, .failed, .invalidAFK, .bailedOut: return .resultPage
    case .active, .abandoned: return .testPage
    }
  }
  func drawsRandomTheme(mode: RandomThemeMode) -> Bool { self == .resultPage && mode != .off }
}
