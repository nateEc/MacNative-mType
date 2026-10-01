/// Anonymous feedback selection, kept separate from sound playback so that
/// tests never need a speaker, audio device, or reference sound asset.
struct TypingInputSoundPlan: Equatable {
  static func isAudibleCompositionUpdate(previous: String, current: String) -> Bool {
    // Clearing marked text precedes confirmation as well as cancellation;
    // neither is a second candidate keystroke. Confirmation uses input feedback.
    !current.isEmpty && current != previous
  }

  let playsClick: Bool
  let playsError: Bool

  init(inputWasCorrect: Bool?, blindMode: Bool, clickEnabled: Bool, errorEnabled: Bool) {
    playsError = inputWasCorrect == false && errorEnabled && !blindMode
    playsClick = inputWasCorrect != nil && !playsError && clickEnabled
  }
}
