import Foundation
import Observation

/// Background selection belongs to the full-config event, independently of
/// font/text initialization. Only already-admitted bytes reach the renderer.
@MainActor @Observable final class WebsiteConfigBackgroundDisplay {
  struct Snapshot {
    let owner: UUID
    let identity: UUID
    let resource: WebsiteConfigBackgroundResource
    let preferences: WebsiteConfigNativePagePreferences
    let pointsPerRem: Double
    var fitOverride: CustomBackgroundFit? = nil
    var filterOverride: WebsiteConfigNativePagePreferences.BackgroundFilter? = nil
    func fitting(_ fit: CustomBackgroundFit) -> Self { var copy = self; copy.fitOverride = fit; return copy }
    func filtering(_ filter: WebsiteConfigNativePagePreferences.BackgroundFilter) -> Self { var copy = self; copy.filterOverride = filter; return copy }
  }
  enum Phase { case readingLocal, loading, settled, localReadFailed, retired }
  enum Invocation: Equatable, Sendable { case event, command }
  let owner: UUID
  private let target: WebsiteConfigNativePagePreferences
  private let pointsPerRem: Double
  private(set) var snapshot: Snapshot
  private(set) var phase: Phase = .readingLocal
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var applications: [Task<Void, Never>] = []
  @ObservationIgnored private var started = false
  @ObservationIgnored private var run = UUID()

  init(owner: UUID, preferences: WebsiteConfigNativePagePreferences, pointsPerRem: Double, previous: Snapshot?) {
    self.owner = owner; target = preferences; self.pointsPerRem = pointsPerRem
    snapshot = previous ?? .init(owner: owner, identity: UUID(), resource: .init(source: nil, state: .none),
      preferences: preferences, pointsPerRem: pointsPerRem)
  }
  func matches(_ draft: WebsiteConfigNativeDraft) -> Bool {
    let p = draft.pagePreferences
    return p.backgroundAddress == target.backgroundAddress && p.backgroundFit == target.backgroundFit
      && p.backgroundFilter == target.backgroundFilter
  }
  func start(readLocal: @escaping @MainActor () async throws -> WebsiteConfigBackgroundResource.Local,
    fetchRemote: @escaping @MainActor (WebsiteConfigValue, Int) async throws -> WebsiteConfigBackgroundResource.Remote,
    limits: WebsiteConfigBackgroundResource.Limits = .init(),
    preferencesNow: (@MainActor () -> WebsiteConfigNativePagePreferences?)? = nil,
    invocations: [Invocation] = [.event],
    onReadFailure: (@MainActor (Invocation, Error) -> Void)? = nil,
    whileCurrent: @escaping @MainActor () -> Bool) {
    guard !started, !invocations.isEmpty else { return }; started = true
    task?.cancel()
    applications.forEach { $0.cancel() }; applications.removeAll()
    let generation = UUID(); run = generation
    phase = .readingLocal
    task = Task { @MainActor [weak self] in
      guard let self else { return }
      var children: [Task<Void, Never>] = []
      for invocation in invocations {
        guard self.run == generation, !Task.isCancelled else { break }
        // Begin the event application before the explicit command without
        // waiting for either read to finish. All producers stay on MainActor.
        await withCheckedContinuation { (entered: CheckedContinuation<Void, Never>) in
          let child = Task { @MainActor [weak self] in
            entered.resume()
            guard let self else { return }
            await self.apply(readLocal: readLocal, fetchRemote: fetchRemote, limits: limits,
              preferencesNow: preferencesNow, invocation: invocation, generation: generation,
              onReadFailure: onReadFailure, whileCurrent: whileCurrent)
          }
          children.append(child); self.applications.append(child)
        }
      }
      for child in children { await child.value }
      if self.run == generation { self.applications.removeAll() }
    }
  }
  private func apply(readLocal: @escaping @MainActor () async throws -> WebsiteConfigBackgroundResource.Local,
    fetchRemote: @escaping @MainActor (WebsiteConfigValue, Int) async throws -> WebsiteConfigBackgroundResource.Remote,
    limits: WebsiteConfigBackgroundResource.Limits,
    preferencesNow: (@MainActor () -> WebsiteConfigNativePagePreferences?)?, invocation: Invocation, generation: UUID,
    onReadFailure: (@MainActor (Invocation, Error) -> Void)?, whileCurrent: @escaping @MainActor () -> Bool) async {
    @MainActor func current() -> Bool {
      guard run == generation else { return false }
      guard !Task.isCancelled, whileCurrent(), run == generation, !Task.isCancelled else {
        if run == generation { started = false; phase = .retired }
        return false
      }
      return true
    }
    guard current() else { return }
    let local: WebsiteConfigBackgroundResource.Local
    do { local = try await readLocal() }
    catch {
      guard current() else { return }
      phase = .localReadFailed
      onReadFailure?(invocation, error)
      return
    }
    guard current() else { return }
    let identity = UUID()
    // Each read completion selects its own image. A later completion may
    // replace it even when that application was requested earlier.
    let selectedPreferences = preferencesNow?() ?? target
    @MainActor func publish(_ resource: WebsiteConfigBackgroundResource, phase: Phase) {
      snapshot = .init(owner: owner, identity: identity, resource: resource,
        preferences: selectedPreferences, pointsPerRem: pointsPerRem)
      self.phase = phase
    }
    do {
      if case .absent = local, target.backgroundAddress.stringUnits?.isEmpty != true {
        publish(.init(source: .remote(target.backgroundAddress), state: .none), phase: .loading)
        let remote: WebsiteConfigBackgroundResource.Remote
        do { remote = try await fetchRemote(target.backgroundAddress, limits.encodedBytes) }
        catch {
          guard current(), snapshot.identity == identity else { return }
          remote = .failed(address: target.backgroundAddress)
        }
        // A completed download belongs to the selected image, not whichever
        // image another overlapping local read selected in the meantime.
        guard current(), snapshot.identity == identity else { return }
        publish(try .prepare(preferences: target, local: local, remote: remote, limits: limits), phase: .settled)
      } else {
        publish(try .prepare(preferences: target, local: local, limits: limits), phase: .settled)
      }
    } catch {
      guard current(), snapshot.identity == identity else { return }
      publish(.init(source: snapshot.resource.source, state: .failed(.transport)), phase: .settled)
    }
  }
  func cancel() {
    task?.cancel(); applications.forEach { $0.cancel() }
    started = false; phase = .retired
  }
  func waitForCompletion() async { await task?.value }
}
