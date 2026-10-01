import Foundation

/// Anonymous physical presses, independent of text input and composition.
/// Physical pairing and result-log ordering are separate: simultaneous releases
/// precede presses in the terminal projection, but samples stay in press order.
struct PhysicalKeyTiming {
  struct Snapshot {
    var durations: [TimeInterval] = []
    var spacings: [TimeInterval] = []
    var overlap: TimeInterval = 0
  }

  private struct Press {
    let code: UInt16
    let down: Date
    var up: Date?
  }

  private struct Edge {
    let time: TimeInterval
    /// A sample slot denotes a down edge; nil denotes a release.
    let sample: Int?
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
      presses.append(Press(code: code, down: date))
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
    let downTimes = presses.map { offset($0.down) }
    let end = offset(finishedAt)
    let lastPreStart = downTimes.lastIndex { $0 < 0 }
    let postEndCodes = Set(presses.indices.compactMap {
      downTimes[$0] > end ? presses[$0].code : nil
    })
    var snapshot = Snapshot()
    var previousDown: TimeInterval?
    var edgesByCode: [UInt16: [Edge]] = [:]

    for (index, press) in presses.enumerated() {
      let down = downTimes[index]
      // Filter downs and releases independently. A release belonging to a
      // discarded pre-start down can still close a later logical press.
      if down <= end, down >= 0 || index == lastPreStart {
        edgesByCode[press.code, default: []].append(Edge(time: down, sample: snapshot.durations.count))
        snapshot.durations.append(0)
        if let previousDown { snapshot.spacings.append(Self.rounded(down - previousDown)) }
        previousDown = max(0, down)
      }
      let up = press.up.map(offset) ?? Self.rounded(down + estimate)
      if up >= 0, up <= end || !postEndCodes.contains(press.code) {
        edgesByCode[press.code, default: []].append(Edge(time: up, sample: nil))
      }
    }

    // Resolve each physical code independently into logical presence spans.
    // Rebinding a down changes the duration's sample owner, not when this code
    // first became present. Unpaired logical downs keep their zero sample.
    var endpoints: [(time: TimeInterval, change: Int)] = []
    endpoints.reserveCapacity(presses.count * 2)
    for var edges in edgesByCode.values {
      edges.sort {
        if $0.time != $1.time { return $0.time < $1.time }
        return ($0.sample ?? -1) < ($1.sample ?? -1)
      }
      var owner: Edge?
      var presentSince: TimeInterval?
      for edge in edges {
        if edge.sample != nil {
          owner = edge
          if presentSince == nil { presentSince = edge.time }
        } else if let current = owner, let sample = current.sample, let since = presentSince {
          snapshot.durations[sample] = Self.rounded(edge.time - current.time)
          endpoints.append((since, 1))
          endpoints.append((edge.time, -1))
          owner = nil
          presentSince = nil
        }
      }
      // An open logical span participates in closed overlap episodes, but
      // does not acquire a fabricated release at the test boundary.
      if let presentSince { endpoints.append((presentSince, 1)) }
    }

    // Integrate closed concurrent-presence episodes, without counting pairs
    // twice or including the final unclosed episode. End edges win ties here
    // too: a handoff can close one episode and start another at the same tick.
    endpoints.sort {
      $0.time == $1.time ? $0.change < $1.change : $0.time < $1.time
    }
    var held = 0
    var previousTime: TimeInterval?
    var pendingOverlap: TimeInterval = 0
    for endpoint in endpoints {
      if held >= 2, let previousTime { pendingOverlap += endpoint.time - previousTime }
      held += endpoint.change
      if held < 2 {
        snapshot.overlap += pendingOverlap
        pendingOverlap = 0
      }
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
