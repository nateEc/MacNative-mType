import Foundation

/// Progressively measures one immutable viewport sequence. The caller owns the
/// live publication contract (attempt, target, input, style, width) through
/// isCurrent; task tickets prevent reentrant restart or cancellation from
/// publishing an obsolete batch or completion.
@MainActor final class PromptViewportPreparationTask {
  enum Failure: Error { case invalidBatchSize, unsupportedWindow }

  private var task: Task<Void, Never>?
  private var ticket: UUID?
  var isPreparing: Bool { ticket != nil }

  @discardableResult
  func start(sequence: PromptViewportFieldLayoutSequence, batchSize: Int,
    isCurrent: @escaping @MainActor () -> Bool,
    onBatch: @escaping @MainActor (PromptViewportFieldLayoutSequence.DrawingSnapshot) -> Void,
    completion: @escaping @MainActor (Result<Void, Error>) -> Void
  ) -> Task<Void, Never> {
    cancel()
    let request = UUID()
    ticket = request
    let running = Task { @MainActor [weak self] in
      guard batchSize > 0 else {
        self?.finish(request: request, result: .failure(Failure.invalidBatchSize),
          isCurrent: isCurrent, completion: completion)
        return
      }
      while sequence.nextField < sequence.fieldCount {
        do {
          // Do not retain the owner across the yield. Closing the host after
          // a published batch must deallocate and cancel this preparation.
          guard let owner = self else { return }
          guard owner.ticket == request, !Task.isCancelled, isCurrent() else {
            owner.finishSilently(request: request)
            return
          }
          let start = sequence.nextField
          let end = start + min(batchSize, sequence.fieldCount - start)
          guard let window = sequence.append(fields: start..<end),
            let snapshot = sequence.drawingSnapshot(windows: [window]) else {
            owner.finish(request: request, result: .failure(Failure.unsupportedWindow),
              isCurrent: isCurrent, completion: completion)
            return
          }
          guard owner.ticket == request, !Task.isCancelled, isCurrent() else {
            owner.finishSilently(request: request)
            return
          }
          onBatch(snapshot)
          guard owner.ticket == request, !Task.isCancelled, isCurrent() else {
            owner.finishSilently(request: request)
            return
          }
        }
        await Task.yield()
      }
      self?.finish(request: request, result: .success(()),
        isCurrent: isCurrent, completion: completion)
    }
    task = running
    return running
  }

  private func finish(request: UUID, result: Result<Void, Error>,
    isCurrent: () -> Bool, completion: (Result<Void, Error>) -> Void) {
    guard ticket == request else { return }
    task = nil
    ticket = nil
    guard !Task.isCancelled, isCurrent() else { return }
    completion(result)
  }

  private func finishSilently(request: UUID) {
    guard ticket == request else { return }
    task = nil
    ticket = nil
  }

  func cancel() {
    ticket = nil
    task?.cancel()
    task = nil
  }

  deinit { task?.cancel() }
}
