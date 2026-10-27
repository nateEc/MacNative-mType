import Foundation
import Observation

struct WebsiteConfigStartupOptions: Equatable {
  var accountReady: Bool
  /// Explicit test/managed-storage injection. nil selects the native location.
  var applicationSupport: URL? = nil
}

@MainActor @Observable final class WebsiteConfigStartupController {
  enum State: Equatable { case idle, waiting, restoring, failed(String), finished }
  private(set) var state: State = .idle
  @ObservationIgnored private(set) var lastFailure: Error?
  var isBlocking: Bool { state != .finished }
  var isRestoring: Bool { state == .restoring }
  var failureMessage: String? { if case .failed(let text) = state { text } else { nil } }
  @ObservationIgnored private weak var page: PracticePageSessionStore?
  @ObservationIgnored private var directory: URL?
  @ObservationIgnored private var workflow: WebsiteConfigImportWorkflow?
  @ObservationIgnored private var work: Task<Void, Never>?
  @ObservationIgnored private var onContinue: (@MainActor () -> Void)?
  @ObservationIgnored private var request = UUID()
  @ObservationIgnored private var stopped = false

  func update(page: PracticePageSessionStore, accountReady: Bool, ownerReady: Bool,
    probe: () throws -> URL?, onPending: () -> Void, onContinue: @escaping @MainActor () -> Void,
    makeWorkflow: @escaping @MainActor (URL) throws -> WebsiteConfigImportWorkflow, systemIsDark: Bool) {
    guard !stopped, state != .finished, failureMessage == nil else { return }
    self.page = page; self.onContinue = onContinue
    page.setStartupInputSuspended(true)
    if state == .idle {
      // An explicit publication already owns the window: never replace it with
      // a startup replay delivered late by an account/bootstrap notification.
      if page.state.practice != nil { finish(); return }
      do { directory = try probe() }
      catch { fail("保存的配置无法安全读取。可在配置面板重试，或明确选择使用 Typebar 设置继续。") ; return }
      guard directory != nil else { finish(); return }
      state = .waiting
      onPending()
    }
    if state == .restoring {
      if !ownerReady {
        cancelWork()
        fail("恢复期间窗口拥有者已变化；请手动重试，或选择使用 Typebar 设置继续。")
      }
      return
    }
    guard state == .waiting, accountReady, ownerReady, let directory else { return }
    state = .restoring
    let current = UUID(); request = current
    work = Task { [weak self] in
      guard let self, !Task.isCancelled, !self.stopped else { return }
      defer { if self.request == current { self.work = nil; self.workflow = nil } }
      do {
        let workflow = try makeWorkflow(directory)
        self.workflow = workflow
        _ = try await workflow.apply(json: nil, systemIsDark: systemIsDark)
        guard self.request == current, !self.stopped, !Task.isCancelled else { return }
        self.finish()
      } catch {
        guard self.request == current, !self.stopped else { return }
        self.lastFailure = error
        self.fail("保存的配置未能恢复，原记录未被重置。请在配置面板检查来源后重试，或明确选择使用 Typebar 设置继续。")
      }
    }
  }
  func continueUsingLegacy() {
    guard !stopped, isBlocking else { return }
    cancelWork()
    let action = onContinue
    finish()
    action?()
  }
  func prepareForManualRecovery() {
    guard !stopped, isBlocking else { return }
    cancelWork()
    fail("自动恢复已停止。可在配置面板恢复，或选择使用 Typebar 设置继续。")
  }
  func completedManually() {
    guard !stopped else { return }
    // No cancellation of the newly committed manual application.
    request = UUID(); work?.cancel(); work = nil; workflow = nil
    finish()
  }
  func savedArchivePreparationFailed(_ message: String, page: PracticePageSessionStore,
    onContinue: @escaping @MainActor () -> Void) {
    guard !stopped else { return }
    cancelWork(); self.page = page; self.onContinue = onContinue
    fail(message)
  }
  func stop() {
    stopped = true; cancelWork(); onContinue = nil
    state = .finished
    page?.setStartupInputSuspended(false); page = nil
  }
  private func fail(_ message: String) {
    page?.setStartupInputSuspended(true); state = .failed(message)
  }
  private func finish() {
    lastFailure = nil
    state = .finished; page?.setStartupInputSuspended(false)
    onContinue = nil
  }
  private func cancelWork() {
    request = UUID(); work?.cancel(); work = nil
    workflow?.cancel(); workflow = nil
  }
}
