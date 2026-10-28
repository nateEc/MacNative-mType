import Foundation
import Observation

/// Explicit window-owned capability. It never creates a default configuration
/// path, chooses a different content provider or rolls back accepted history.
@MainActor @Observable final class WebsitePracticeRestartController {
  private(set) var isPreparing = false
  private(set) var message: String?
  private(set) var exhaustedMessage: String?
  struct Delivery {
    let source: WebsiteRestartSource
    let owner: UUID
    let attempt: UUID
    let publication: UUID
  }
  private struct Readers {
    let quotes: @MainActor (TypingLanguage) async throws -> [OfflineQuote]
    let external: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> WebsiteConfigSessionBuilder.External)?
  }
  private struct Request {
    let ticket: UUID
    let accepted: WebsiteConfigCommitCoordinator.RestartAdmission
    let readers: Readers
    let initializationReport: WebsiteConfigInitializationReport
    let source: WebsiteRestartSource
  }
  @ObservationIgnored private weak var page: PracticePageSessionStore?
  @ObservationIgnored private let coordinator: WebsiteConfigCommitCoordinator
  @ObservationIgnored private weak var notices: LocalNoticeCenter?
  @ObservationIgnored private var readers: Readers?
  @ObservationIgnored private var work: Task<Void, Never>?
  @ObservationIgnored private var admission: WebsiteConfigCommitCoordinator.RestartAdmission?
  @ObservationIgnored private var ticket = UUID()
  @ObservationIgnored private var stopped = false
  @ObservationIgnored private var didRestart: (@MainActor (Delivery) -> Void)?

  init(page: PracticePageSessionStore, coordinator: WebsiteConfigCommitCoordinator,
    notices: LocalNoticeCenter? = nil,
    loadQuotes: @escaping @MainActor (TypingLanguage) async throws -> [OfflineQuote],
    loadExternal: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> WebsiteConfigSessionBuilder.External)?,
    didRestart: (@MainActor (Delivery) -> Void)? = nil) {
    self.page = page; self.coordinator = coordinator; self.notices = notices
    readers = .init(quotes: loadQuotes, external: loadExternal)
    self.didRestart = didRestart
  }
  @discardableResult
  func request(repeatingRequested: Bool = false) -> Bool {
    guard let request = begin(repeatingRequested: repeatingRequested, current: UUID()) else { return false }
    work = Task { [weak self] in _ = await self?.complete(request) }
    return true
  }
  /// Runs in the caller's task so cancellation is checked before delivery,
  /// while sharing the same admission/busy state as ordinary restart buttons.
  /// The caller must supply a fresh operation ID for every invocation.
  func requestAndWait(requestID: UUID, repeatingRequested: Bool = false) async throws -> Bool {
    try Task.checkCancellation()
    guard let request = begin(repeatingRequested: repeatingRequested, current: requestID) else { return false }
    let advanced = await complete(request)
    // Once advance installed the attempt, a synchronous delivery observer
    // cannot retroactively turn that successful delivery into cancellation.
    if !advanced { try Task.checkCancellation() }
    return advanced
  }
  func cancel(requestID: UUID) {
    guard isPreparing, ticket == requestID else { return }
    cancel()
  }
  private func begin(repeatingRequested: Bool, current: UUID) -> Request? {
    guard !stopped, !isPreparing, let page, let readers else { return nil }
    let source = WebsiteRestartSource.capture(outcome: page.state.session.outcome,
      alreadyDeparted: page.state.restartDepartureAttemptID == page.state.session.automaticInputAttemptID)
    ticket = current
    isPreparing = true; message = nil; exhaustedMessage = nil
    let accepted: WebsiteConfigCommitCoordinator.RestartAdmission
    do { accepted = try coordinator.beginRestart(for: page, repeatingRequested: repeatingRequested, recoveringWith: self) }
    catch {
      if ticket == current && !stopped {
        isPreparing = false
        message = error is CancellationError ? "重开已取消。" : "当前尝试尚不能重开；请检查锁定状态或配置拥有者。"
      }
      return nil
    }
    guard ticket == current, !stopped else { _ = coordinator.cancel(accepted); return nil }
    admission = accepted
    return .init(ticket: current, accepted: accepted, readers: readers,
      initializationReport: .init(notices: notices, lazyModeNotices: page.lazyModeNotices), source: source)
  }
  private func complete(_ request: Request) async -> Bool {
    let current = request.ticket, accepted = request.accepted, readers = request.readers
    var delivered: Delivery?
    defer {
      if ticket == current { isPreparing = false; work = nil; admission = nil }
      // advance has released the page reservation. A late cancellation cannot
      // undo delivery, but a replaced/stopped controller must not act on it.
      if let delivered, !stopped, let page, page.restartController === self,
        page.state.session.automaticInputAttemptID == delivered.attempt,
        page.state.presentation?.publication.applicationID == delivered.publication {
        didRestart?(delivered)
      }
    }
    do {
      let ready = try await coordinator.prepareRestart(accepted,
        initializationReport: request.initializationReport,
        loadQuotes: readers.quotes, loadExternal: readers.external)
      guard ticket == current, !stopped, !Task.isCancelled, let page else {
        _ = coordinator.cancel(ready); return false
      }
      switch try coordinator.advance(ready, to: page) {
      case .advanced:
        message = nil
        if let publication = page.state.presentation?.publication {
          delivered = .init(source: request.source, owner: page.owner,
            attempt: page.state.session.automaticInputAttemptID, publication: publication.applicationID)
        }
        return true
      case .busy, .conflict, .unavailable, .stale:
        _ = coordinator.cancel(ready)
        message = "新一轮未能开始；已接受的旧尝试不会重复记账，请重试。"
        return false
      }
    } catch {
      _ = coordinator.cancel(accepted)
      if ticket == current && !stopped {
        if let final = request.initializationReport.finalMessage {
          message = final; exhaustedMessage = final
        } else if case WebsiteConfigSessionBuildError.quoteRecoveryLimitReached = error {
          message = error.localizedDescription
        } else {
          message = error is CancellationError
            ? "重开已取消；已关闭的尝试不恢复计时，可重试。"
            : "新一轮准备失败；旧尝试已关闭，可重试。"
        }
      }
      return false
    }
  }
  func cancel() {
    exhaustedMessage = nil
    ticket = UUID(); work?.cancel(); work = nil
    if let admission { _ = coordinator.cancel(admission) }
    admission = nil; isPreparing = false
    if !stopped { message = "重开已取消；已关闭的尝试不恢复计时，可重试。" }
  }
  func stop() {
    stopped = true; cancel(); readers = nil; didRestart = nil; message = nil
  }
}
