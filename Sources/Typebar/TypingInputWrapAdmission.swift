import Foundation

/// Ephemeral platform admission, never part of saved practice or replay.
/// The engine calls this only for a potentially growing, uncommitted word.
struct TypingInputWrapAdmission {
  var slowTimer = false
  let rejects: (TypingSession, [UInt16]) -> Bool
}
