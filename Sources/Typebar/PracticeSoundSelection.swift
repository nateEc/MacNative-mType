import Foundation

struct PracticeSoundSelection: Equatable {
  let click: TypingClickSoundStyle?
  let error: TypingErrorSoundStyle?
  let warning: TimeWarningOffset
  let warningStyle: TimeWarningSoundStyle
  let volume: Double
  let blindMode: Bool
  @MainActor init(draft: WebsiteConfigNativeDraft?, settings: AppSettings, blindMode: Bool) {
    if let behavior = draft?.behavior {
      click = behavior.clickSoundStyle; error = behavior.errorSoundStyle
      warning = behavior.timeWarningOffset; volume = behavior.soundVolume
    } else {
      click = settings.playKeyclickSound ? settings.clickSoundStyle : nil
      error = settings.playErrorBeep ? settings.errorSoundStyle : nil
      warning = settings.timeWarningOffset; volume = settings.soundVolume
    }
    warningStyle = settings.timeWarningSoundStyle; self.blindMode = blindMode
  }
  @MainActor func playInput(_ correct: Bool?, on player: TypingFeedbackSound) {
    let plan = TypingInputSoundPlan(inputWasCorrect: correct, blindMode: blindMode,
      clickEnabled: click != nil, errorEnabled: error != nil)
    if plan.playsClick, let click { player.playClick(style: click, volume: volume) }
    if plan.playsError, let error { player.playError(style: error, volume: volume) }
  }
  @MainActor func playWarning(remaining: Int, previous: Int?, on player: TypingFeedbackSound) {
    guard TimeWarningPolicy.shouldPlay(remainingSeconds: remaining, previousSecond: previous, offset: warning) else { return }
    player.playTimeWarning(style: warningStyle, volume: volume)
  }
  @MainActor func playFinish(previous: TestOutcome, outcome: TestOutcome, started: Bool, on player: TypingFeedbackSound) {
    player.playPracticeFinish(previousOutcome: previous, outcome: outcome, hasStarted: started,
      clickEnabled: click != nil, style: click ?? .tink, volume: volume)
  }
  @MainActor func afterCommand(_ target: SoundCommandTarget, on player: TypingFeedbackSound) {
    switch target {
    case .click: if let click { player.playClick(style: click, volume: volume) }
    case .error: if let error { player.playError(style: error, volume: volume) }
    case .timeWarning(let offset): if offset != .off { player.playTimeWarning(style: warningStyle, volume: volume) }
    case .volume: break // The pinned subgroup returns playClick without calling it.
    }
  }
  @MainActor func hover(_ target: SoundCommandTarget, on player: TypingFeedbackSound) {
    switch target {
    case .click(let style?): player.previewClick(style: style, volume: volume)
    case .error(let style?): player.previewError(style: style, volume: volume)
    case .timeWarning(let offset) where offset != .off: player.playTimeWarning(style: warningStyle, volume: volume)
    default: break
    }
  }
}

@MainActor final class WebsitePracticeSoundOutput {
  let player: TypingFeedbackSound
  private var previous: PracticeSoundSelection?
  init(parent: TypingFeedbackSound) { player = parent.makeIsolatedPlayer() }
  func apply(_ selection: PracticeSoundSelection) {
    if previous?.volume != selection.volume { player.setVolume(selection.volume) }
    if previous == nil || previous?.click != selection.click { player.configureClickSound(style: selection.click) }
    previous = selection
  }
  func stop() { player.clearAllSounds() }
}
