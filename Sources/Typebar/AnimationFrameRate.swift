import Foundation
import SwiftUI

/// Controls how often Typebar's code-drawn animated views ask SwiftUI to
/// refresh. The pinned reference accepts integer values from 15 through 1000,
/// where 1000 represents the display's native cadence rather than a practical
/// promise to render that many frames per second.
enum AnimationFrameRatePolicy {
  static let nativeFrameRate = 1_000
  static let supportedRange = 15...nativeFrameRate

  static func normalized(_ frameRate: Int) -> Int {
    min(max(frameRate, supportedRange.lowerBound), supportedRange.upperBound)
  }

  static func minimumInterval(for frameRate: Int) -> TimeInterval {
    1 / Double(normalized(frameRate))
  }
}

private struct TypebarAnimationFrameRateKey: EnvironmentKey {
  static let defaultValue = AnimationFrameRatePolicy.nativeFrameRate
}

extension EnvironmentValues {
  var typebarAnimationFrameRate: Int {
    get { self[TypebarAnimationFrameRateKey.self] }
    set { self[TypebarAnimationFrameRateKey.self] = AnimationFrameRatePolicy.normalized(newValue) }
  }
}
