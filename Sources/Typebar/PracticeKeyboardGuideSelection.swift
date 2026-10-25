import Foundation

/// Visual preferences belong to the current publication, independently of the
/// physical input mapping and any legacy custom or system keyboard rows.
struct PracticeKeyboardGuideSelection: Equatable {
  let mode: KeyboardGuideMode
  let scale: Double
  let legendStyle: KeyboardGuideLegendStyle
  let keysMode: KeyboardGuideKeysMode
  let style: KeyboardGuideStyle
  let allowsLegacyRows: Bool

  @MainActor init(draft: WebsiteConfigNativeDraft?, settings: AppSettings,
    legacyMode: KeyboardGuideMode? = nil) {
    let keyboard = draft?.keyboardTypography
    mode = keyboard?.guideMode ?? legacyMode ?? settings.effectiveKeyboardGuideMode
    scale = keyboard?.guideScale ?? settings.keyboardGuideScale
    legendStyle = keyboard?.guideLegendStyle ?? settings.keyboardGuideLegendStyle
    keysMode = keyboard?.guideKeys ?? settings.keyboardGuideKeysMode
    style = keyboard?.guideStyle ?? settings.keyboardGuideStyle
    allowsLegacyRows = keyboard == nil
  }
}
