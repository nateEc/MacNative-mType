import Foundation

/// Live UI callbacks are not replay actions: recovery deletions and word
/// transitions must not invent additional physical-input sounds.
enum TypingLiveInputFeedback {
  static func insertBatch(
    _ text: String, into session: inout TypingSession, forceError: Bool = false,
    origin: TypingInputOrigin = .physicalKeyboard, at date: Date = .now,
    defersAutomaticInput: Bool = false, wrapAdmission: TypingInputWrapAdmission? = nil
  ) -> [Bool] {
    session.insertBatch(text, forceError: forceError, at: date, origin: origin,
      defersAutomaticInput: defersAutomaticInput, wrapAdmission: wrapAdmission)
  }

  static func delete(
    from session: inout TypingSession, wholeWord: Bool, at date: Date = .now
  ) -> [Bool] {
    let before = session.typed
    if wholeWord { session.deleteWordBackward(at: date) }
    else { session.deleteBackward(at: date) }
    return session.typed == before ? [] : [true]
  }
}
