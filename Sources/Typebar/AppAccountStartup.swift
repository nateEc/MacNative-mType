import Observation

/// One account bootstrap shared by the app's windows. Closing one window does
/// not restart authentication or cancel another window's readiness dependency.
@MainActor @Observable final class AppAccountStartup {
  private(set) var isReady = false
  @ObservationIgnored private var work: Task<Void, Never>?
  func restore(using action: @escaping @MainActor () async -> Void) async {
    if isReady { return }
    if let work { await work.value; return }
    let task = Task { @MainActor in
      await action()
      self.isReady = true
    }
    work = task
    await task.value
    work = nil
  }
}
