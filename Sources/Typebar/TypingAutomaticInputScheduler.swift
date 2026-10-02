import Foundation

/// One native main-queue turn per callback. Tickets prevent a canceled or
/// replaced attempt's old closure from consuming a new attempt's request.
@MainActor
final class TypingAutomaticInputScheduler {
  typealias Action = @MainActor @Sendable () -> Void
  private let enqueue: (@escaping Action) -> Void
  private var pending: (attempt: UUID, ticket: UUID)?

  init(enqueue: @escaping (@escaping Action) -> Void = { action in
    DispatchQueue.main.async(execute: action)
  }) {
    self.enqueue = enqueue
  }

  func schedule(for attemptID: UUID, action: @escaping Action) {
    guard pending?.attempt != attemptID else { return }
    let ticket = UUID()
    pending = (attemptID, ticket)
    enqueue { [weak self] in
      guard let self, self.pending?.ticket == ticket else { return }
      self.pending = nil
      action()
    }
  }

  func cancel() { pending = nil }
}
