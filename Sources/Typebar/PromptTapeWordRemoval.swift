import Foundation

/// Process-local presentation identity, never a prompt/input/replay mutation.
/// Horizontal disappearance is distinct from a vertical prefix boundary.
struct PromptTapeWordRemoval: Equatable {
  let attemptID: UUID
  let wordIndices: Set<Int>
}
