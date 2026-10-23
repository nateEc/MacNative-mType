import Foundation

/// Main-actor delivery only. The host owns visibility, rendering and resource publication.
@MainActor
final class WebsiteConfigBackgroundPlayer {
  typealias Now = @MainActor () -> Double
  typealias Sleep = @MainActor (Double) async throws -> Void
  enum State: Equatable { case stopped, playing, paused, finished, failed }
  enum Failure: Error, Equatable { case invalidClock, waitFailed }
  private(set) var state: State = .stopped
  private(set) var currentSample: WebsiteConfigBackgroundPlayback.Sample?
  private(set) var failure: Failure?
  private struct Run {
    let playback: WebsiteConfigBackgroundPlayback
    let present: @MainActor (WebsiteConfigBackgroundPlayback.Sample) -> Void
    let failed: @MainActor (Failure) -> Void
    var startedAt: Double
    var lastNow: Double
    var elapsedOffset = 0.0
    var lastIndex: Int?
  }
  private let now: Now
  private let sleep: Sleep
  private var run: Run?
  private var generation = UUID()
  private var task: Task<Void, Never>?

  init(now: Now? = nil, sleep: Sleep? = nil) {
    let clock = ContinuousClock(), origin = clock.now
    self.now = now ?? {
      let parts = origin.duration(to: clock.now).components
      return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
    self.sleep = sleep ?? { try await Task.sleep(for: .seconds($0)) }
  }
  deinit { task?.cancel() }

  func start(_ playback: WebsiteConfigBackgroundPlayback,
    present: @escaping @MainActor (WebsiteConfigBackgroundPlayback.Sample) -> Void,
    failed: @escaping @MainActor (Failure) -> Void = { _ in }) {
    stop()
    let token = generation, time = now()
    guard token == generation else { return }
    guard time.isFinite else {
      state = .failed; failure = .invalidClock; failed(.invalidClock)
      return
    }
    run = .init(playback: playback, present: present, failed: failed, startedAt: time, lastNow: time)
    state = .playing
    advance(token, at: time)
  }

  func pause() {
    guard state == .playing else { return }
    retireWait()
    advance(generation, pausing: true)
  }

  func resume() {
    guard state == .paused, var run else { return }
    retireWait()
    let token = generation, time = now()
    guard token == generation else { return }
    guard time.isFinite, time >= run.lastNow else { fail(.invalidClock, token: token); return }
    run.startedAt = time; run.lastNow = time
    self.run = run; state = .playing
    advance(token, at: time)
  }

  func stop() {
    retireWait()
    run = nil; currentSample = nil; failure = nil; state = .stopped
  }

  private func retireWait() {
    generation = UUID()
    task?.cancel(); task = nil
  }

  private func fail(_ error: Failure, token: UUID) {
    guard token == generation else { return }
    let callback = run?.failed
    retireWait()
    run = nil; failure = error; state = .failed
    // Keep the last good frame; clearing the host's layer is a separate decision.
    callback?(error)
  }

  private func advance(_ token: UUID, at suppliedTime: Double? = nil, pausing: Bool = false) {
    guard token == generation, state == .playing, var run else { return }
    let time = suppliedTime ?? now()
    guard token == generation else { return }
    guard time.isFinite, time >= run.lastNow else { fail(.invalidClock, token: token); return }
    let elapsed = run.elapsedOffset + (time - run.startedAt)
    guard elapsed.isFinite, elapsed >= 0,
      let sample = try? run.playback.sample(elapsed: elapsed)
    else { fail(.invalidClock, token: token); return }
    run.lastNow = time
    let changed = run.lastIndex != sample.frameIndex
    run.lastIndex = sample.frameIndex
    if pausing {
      run.elapsedOffset = elapsed; run.startedAt = time
      state = .paused
    }
    if sample.timeUntilNextFrame == nil { state = .finished }
    self.run = state == .finished ? nil : run
    currentSample = sample
    if changed { run.present(sample) }
    // A presentation can replace/pause/stop synchronously; never arm its retired run.
    guard token == generation, state == .playing, let delay = sample.timeUntilNextFrame else { return }
    arm(delay, sampledAt: time, token: token)
  }

  private func remainingWait(_ delay: Double, sampledAt: Double, token: UUID) -> Double? {
    guard token == generation, state == .playing, var run else { return nil }
    let time = now()
    guard token == generation else { return nil }
    let consumed = time - sampledAt
    guard time.isFinite, time >= run.lastNow, consumed.isFinite, consumed >= 0
    else { fail(.invalidClock, token: token); return nil }
    run.lastNow = time; self.run = run
    return min(max(0, delay - consumed), 60)
  }

  private func arm(_ delay: Double, sampledAt: Double, token: UUID) {
    let sleeper = sleep
    task = Task { @MainActor [weak self] in
      do {
        try Task.checkCancellation()
        // Compute inside the Task, after both presentation work and actor-queue delay.
        guard let remaining = self?.remainingWait(delay, sampledAt: sampledAt, token: token) else { return }
        try Task.checkCancellation()
        try await sleeper(remaining)
        try Task.checkCancellation()
      } catch {
        // An uncancelled sleeper throwing CancellationError is still a failed wait.
        guard !Task.isCancelled else { return }
        self?.fail(.waitFailed, token: token)
        return
      }
      guard let self, token == self.generation, self.state == .playing else { return }
      self.task = nil
      self.advance(token)
    }
  }
}
