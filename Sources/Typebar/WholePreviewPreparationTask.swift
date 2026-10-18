import Foundation

/// Owns one preparation request. Cancellation stops cooperative generation;
/// the ticket also prevents obsolete success/failure from publishing.
/// The caller captures immutable inputs and cancels on navigation or reset.
@MainActor final class WholePreviewPreparationTask {
  private var task: Task<Void, Never>?
  private var ticket: UUID?

  var isPreparing: Bool { ticket != nil }

  @discardableResult
  func start<Prepared>(
    operation: @escaping @MainActor () async throws -> Prepared,
    completion: @escaping @MainActor (Result<Prepared, Error>) -> Void
  ) -> Task<Void, Never> {
    cancel()
    let request = UUID()
    ticket = request
    let running = Task { @MainActor [weak self] in
      let result: Result<Prepared, Error>
      do {
        try Task.checkCancellation()
        result = .success(try await operation())
      } catch {
        result = .failure(error)
      }
      guard let self, self.ticket == request else { return }
      // Clear before calling out: completion may start another request.
      self.task = nil
      self.ticket = nil
      guard !Task.isCancelled else { return }
      completion(result)
    }
    task = running
    return running
  }

  func cancel() {
    ticket = nil
    task?.cancel()
    task = nil
  }

  deinit { task?.cancel() }
}
