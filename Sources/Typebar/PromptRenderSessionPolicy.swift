/// Session-dependent prompt decisions. A prepared session may be rendered
/// before it replaces the currently visible placeholder, so every decision
/// here must come from that prepared session rather than ContentView state.
struct PromptRenderSessionPolicy {
  let highlightMode: PromptHighlightMode
  let usesIndependentPromptCarets: Bool
  let paceGuideIndex: Int?

  init(session: TypingSession, highlightMode requestedHighlightMode: PromptHighlightMode,
    usesTapePractice: Bool, mainCaretDrawsMarker: Bool, paceCaretDrawsMarker: Bool
  ) {
    let effect = PracticeVisualEffect.make(modifiers: session.configuration.modifiers)
    let nativeOverlay = (mainCaretDrawsMarker || paceCaretDrawsMarker)
      && !usesTapePractice && !effect.usesASL && !effect.usesChoo
      && PromptFieldProjectionPolicy.supports(session.configuration)
    usesIndependentPromptCarets = nativeOverlay || usesTapePractice || effect.usesChoo || effect.usesASL
    let allowsWords = PromptHighlightAvailabilityPolicy.allowsWordRanges(
      languageUsesSpaceDelimitedWords: session.usesWordCommitInput,
      usesTapePractice: usesTapePractice, modifiers: session.configuration.modifiers)
    highlightMode = requestedHighlightMode == .off ? .off : (allowsWords ? requestedHighlightMode : .letter)
    if usesIndependentPromptCarets {
      paceGuideIndex = nil
    } else if let frame = session.paceCaretFrame() {
      paceGuideIndex = session.paceCaretGlyphIndex(for: frame.target)
    } else {
      paceGuideIndex = nil
    }
  }
}
