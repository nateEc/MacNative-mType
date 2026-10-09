import Observation
import SwiftUI

/// Delivery state belongs to the statistics subtree, not the whole practice view.
@MainActor @Observable final class LiveStatsClockSignal {
  var second = 0
}

@MainActor struct LiveStatsClockContent<Content: View>: View {
  let signal: LiveStatsClockSignal
  let content: () -> Content

  var body: some View {
    _ = signal.second
    return content()
  }
}
