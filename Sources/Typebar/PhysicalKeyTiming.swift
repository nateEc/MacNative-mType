import Foundation

/// Anonymous physical presses, independent of text input and composition.
/// A press owns its release, so result sample order never depends on release order.
struct PhysicalKeyTiming {
  struct Snapshot {
    var durations: [TimeInterval] = []
    var spacings: [TimeInterval] = []
    var overlap: TimeInterval = 0
  }

  private struct Press {
    let down: Date
    var up: Date?
  }

  private var presses: [Press] = []
  private var active: [UInt16: Int] = [:]
  private var latestDown: [UInt16: Date] = [:]
  private var firstRelease: [UInt16: Date] = [:]
  private var lastEventDate: Date?

  mutating func record(code: UInt16, down: Bool, isRepeat: Bool, at date: Date) {
    guard date.timeIntervalSinceReferenceDate.isFinite,
      lastEventDate.map({ date >= $0 }) ?? true
    else { return }
    if down {
      guard !isRepeat else { return }
      close(code: code, at: date)
      active[code] = presses.count
      latestDown[code] = date
      presses.append(Press(down: date))
    } else {
      close(code: code, at: date)
    }
    lastEventDate = date
  }

  private mutating func close(code: UInt16, at date: Date) {
    guard let index = active.removeValue(forKey: code) else { return }
    presses[index].up = date
    if firstRelease[code] == nil { firstRelease[code] = date }
  }

  /// Terminal projection only: estimated releases never mutate live input state.
  /// Keep the last pre-start press, and do not clip its hold or a synthetic
  /// release to the test boundary. Existing persisted results remain unchanged.
  func snapshot(startedAt: Date, finishedAt: Date) -> Snapshot {
    guard !presses.isEmpty else { return Snapshot() }
    func offset(_ date: Date) -> TimeInterval {
      Self.rounded(date.timeIntervalSince(startedAt))
    }

    // The reference estimate pairs the first release of each physical code
    // with its latest down, not every completed press. Reused codes therefore
    // can contribute nothing; zero/negative pairs use the 80ms fallback.
    let candidates = firstRelease.compactMap { code, date -> TimeInterval? in
      guard let down = latestDown[code] else { return nil }
      let duration = offset(date) - offset(down)
      return duration > 0 ? duration : nil
    }
    let estimate = candidates.isEmpty
      ? 0.08 : Self.rounded(candidates.reduce(0, +) / Double(candidates.count))
    let lastPreStart = presses.lastIndex { $0.down < startedAt }
    var snapshot = Snapshot()
    var previousDown: TimeInterval?
    var endpoints: [(time: TimeInterval, change: Int)] = []
    endpoints.reserveCapacity(presses.count * 2)

    for (index, press) in presses.enumerated() {
      guard press.down <= finishedAt,
        press.down >= startedAt || index == lastPreStart
      else { continue }
      let down = offset(press.down)
      let up: TimeInterval?
      if let releasedAt = press.up {
        up = releasedAt >= startedAt ? offset(releasedAt) : nil
      } else {
        up = Self.rounded(down + estimate)
      }
      snapshot.durations.append(up.map { Self.rounded(max(0, $0 - down)) } ?? 0)
      if let previousDown { snapshot.spacings.append(Self.rounded(down - previousDown)) }
      previousDown = max(0, down)
      if let up, up > down {
        endpoints.append((down, 1))
        endpoints.append((up, -1))
      }
    }

    // Integrate the portion covered by at least two intervals. This is a
    // union, not the sum of pairwise intersections (which overcounts 3+ keys).
    endpoints.sort { $0.time < $1.time }
    var held = 0
    var previousTime: TimeInterval?
    for endpoint in endpoints {
      if held >= 2, let previousTime { snapshot.overlap += endpoint.time - previousTime }
      held += endpoint.change
      previousTime = endpoint.time
    }
    snapshot.overlap = Self.rounded(snapshot.overlap)
    return snapshot
  }

  /// Hundredth-millisecond resolution, expressed in the client's seconds.
  private static func rounded(_ seconds: TimeInterval) -> TimeInterval {
    (seconds * 100_000).rounded() / 100_000
  }
}
