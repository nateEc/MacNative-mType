import Foundation

/// Stopwatch runs outlive the last letter action. Keep ranges, not one task
/// per second, and coalesce only writes whose deadlines have already passed.
struct ReplayStatisticsClock: Equatable {
  private struct Run: Equatable {
    let origin: Double
    let offset: Double
    var next: Double
    let last: Double
    func deadline(_ second: Double) -> Double { max(origin, origin + second * 1000 - offset) }
  }
  private var runs: [Run] = []
  private(set) var seconds = 0.0
  var hasPending: Bool { !runs.isEmpty }

  init(firstOffset: Double = 0) { seek(to: firstOffset) }

  mutating func seek(to offset: Double) {
    runs.removeAll()
    seconds = offset.isFinite ? max(0, offset.rounded(.down)) : 0
  }

  mutating func pause(at now: Double) {
    advance(to: now)
    runs.removeAll()
  }

  mutating func play(from offset: Double, through end: Double, at now: Double) {
    advance(to: now)
    seconds = offset.isFinite ? max(0, offset.rounded(.down)) : 0
    guard offset.isFinite, end.isFinite, now.isFinite, offset >= 0, end >= offset,
      (now * 1000).isFinite, (offset * 1000).isFinite else { return }
    runs.append(.init(origin: now * 1000, offset: offset * 1000,
      next: (offset + 0.5).rounded(.down), last: (end + 0.5).rounded(.down)))
    advance(to: now)
  }

  mutating func advance(to now: Double) {
    guard hasPending, now.isFinite, (now * 1000).isFinite else { return }
    let milliseconds = now * 1000
    var lastDeadline = -Double.infinity
    var nextRuns: [Run] = []
    for var run in runs {
      guard run.deadline(run.next) <= milliseconds else { nextRuns.append(run); continue }
      var due = min(run.last, max(run.next, ((milliseconds - run.origin + run.offset) / 1000).rounded(.down)))
      if due > run.next, run.deadline(due) > milliseconds { due -= 1 }
      if due < run.last, due + 1 > due, run.deadline(due + 1) <= milliseconds { due += 1 }
      let deadline = run.deadline(due)
      // Equal deadlines follow registration order; later runs are visited last.
      if deadline >= lastDeadline { seconds = due; lastDeadline = deadline }
      if due < run.last, due + 1 > due { run.next = due + 1; nextRuns.append(run) }
    }
    runs = nextRuns
  }
}
