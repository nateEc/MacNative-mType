import Foundation
import Observation

/// Explicit window-owned capability. It never creates a default configuration
/// path, chooses a different content provider or rolls back accepted history.
@MainActor @Observable final class WebsitePracticeRestartController {
  private(set) var isPreparing = false
  private(set) var message: String?
  private struct Readers {
    let quotes: @MainActor (TypingLanguage) async throws -> [OfflineQuote]
    let external: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> WebsiteConfigSessionBuilder.External)?
  }
  @ObservationIgnored private weak var page: PracticePageSessionStore?
  @ObservationIgnored private let coordinator: WebsiteConfigCommitCoordinator
  @ObservationIgnored private var readers: Readers?
  @ObservationIgnored private var work: Task<Void, Never>?
  @ObservationIgnored private var admission: WebsiteConfigCommitCoordinator.RestartAdmission?
  @ObservationIgnored private var ticket = UUID()
  @ObservationIgnored private var stopped = false

  init(page: PracticePageSessionStore, coordinator: WebsiteConfigCommitCoordinator,
    loadQuotes: @escaping @MainActor (TypingLanguage) async throws -> [OfflineQuote],
    loadExternal: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> WebsiteConfigSessionBuilder.External)?) {
    self.page = page; self.coordinator = coordinator
    readers = .init(quotes: loadQuotes, external: loadExternal)
  }
  @discardableResult
  func request(repeatingRequested: Bool = false) -> Bool {
    guard !stopped, !isPreparing, let page, let readers else { return false }
    let current = UUID(); ticket = current
    isPreparing = true; message = nil
    let accepted: WebsiteConfigCommitCoordinator.RestartAdmission
    do { accepted = try coordinator.beginRestart(for: page, repeatingRequested: repeatingRequested) }
    catch {
      if ticket == current && !stopped {
        isPreparing = false
        message = error is CancellationError ? "重开已取消。" : "当前尝试尚不能重开；请检查锁定状态或配置拥有者。"
      }
      return false
    }
    guard ticket == current, !stopped else { _ = coordinator.cancel(accepted); return false }
    admission = accepted
    work = Task { [weak self] in
      guard let self else { return }
      defer {
        if self.ticket == current { self.isPreparing = false; self.work = nil; self.admission = nil }
      }
      do {
        let ready = try await self.coordinator.prepareRestart(accepted,
          loadQuotes: readers.quotes, loadExternal: readers.external)
        guard self.ticket == current, !self.stopped, !Task.isCancelled, let page = self.page else {
          _ = self.coordinator.cancel(ready); return
        }
        switch try self.coordinator.advance(ready, to: page) {
        case .advanced: self.message = nil
        case .busy, .conflict, .unavailable, .stale:
          _ = self.coordinator.cancel(ready)
          self.message = "新一轮未能开始；已接受的旧尝试不会重复记账，请重试。"
        }
      } catch {
        _ = self.coordinator.cancel(accepted)
        if self.ticket == current && !self.stopped {
          self.message = "新一轮准备失败；旧尝试已关闭，可重试。"
        }
      }
    }
    return true
  }
  func cancel() {
    ticket = UUID(); work?.cancel(); work = nil
    if let admission { _ = coordinator.cancel(admission) }
    admission = nil; isPreparing = false
    if !stopped { message = "重开已取消；已关闭的尝试不恢复计时，可重试。" }
  }
  func stop() {
    stopped = true; cancel(); readers = nil; message = nil
  }
}
