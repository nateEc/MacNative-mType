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
  let owner: UUID
  private let target: WebsiteConfigNativePagePreferences
  private let pointsPerRem: Double
  private(set) var snapshot: Snapshot
  private(set) var phase: Phase = .readingLocal
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var started = false

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
    whileCurrent: @escaping @MainActor () -> Bool) {
    guard !started else { return }; started = true
    phase = .readingLocal
    task = Task { @MainActor [weak self] in
      guard let self else { return }
      @MainActor func current() -> Bool {
        guard !Task.isCancelled, whileCurrent() else {
          // A later explicit preparation may retry a retired admission. Do not
          // leave an expired producer looking like a permanently running load.
          started = false; phase = .retired; return false
        }
        return true
      }
      guard current() else { return }
      let local: WebsiteConfigBackgroundResource.Local
      do { local = try await readLocal() }
      catch {
        guard current() else { return }
        // Source getFile rejection precedes every DOM change.
        phase = .localReadFailed; return
      }
      guard current() else { return }
      let identity = UUID()
      // The source captures the URL before getFile, but reads filters and fit
      // when that read completes. Later filter commands do not repaint img.
      let selectedPreferences = preferencesNow?() ?? target
      @MainActor func publish(_ resource: WebsiteConfigBackgroundResource, phase: Phase) {
        snapshot = .init(owner: owner, identity: identity, resource: resource,
          preferences: selectedPreferences, pointsPerRem: pointsPerRem)
        self.phase = phase
      }
      do {
        if case .absent = local, target.backgroundAddress.stringUnits?.isEmpty != true {
          // Replacing img clears the old pixels before the request completes.
          publish(.init(source: .remote(target.backgroundAddress), state: .none), phase: .loading)
          let remote: WebsiteConfigBackgroundResource.Remote
          do { remote = try await fetchRemote(target.backgroundAddress, limits.encodedBytes) }
          catch {
            guard current() else { return }
            remote = .failed(address: target.backgroundAddress)
          }
          guard current() else { return }
          publish(try .prepare(preferences: target, local: local, remote: remote, limits: limits), phase: .settled)
        } else {
          publish(try .prepare(preferences: target, local: local, limits: limits), phase: .settled)
        }
      } catch {
        guard current() else { return }
        publish(.init(source: snapshot.resource.source, state: .failed(.transport)), phase: .settled)
      }
    }
  }
  func cancel() { task?.cancel() }
  func waitForCompletion() async { await task?.value }
}
