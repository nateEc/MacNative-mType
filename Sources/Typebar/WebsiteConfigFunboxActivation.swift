import Foundation

/// Configuration effects of admitted Funbox activation, before quote/Lazy
/// initialization. Rendering, timers and selection-memory restoration have
/// their own owners; this stage only returns a new value and setter events.
@MainActor enum WebsiteConfigFunboxActivation {
  static func prepare(_ original: WebsiteConfigNativeDraft, pointsPerRem: Double,
    context: WebsiteConfigRuntimeContext, onJoiningScriptClear: (() -> Void)? = nil) throws -> WebsiteConfigNativeDraft {
    var current = original
    func apply(_ key: String, _ value: WebsiteConfigValue) throws {
      let edited: WebsiteConfigNativeDraft
      do {
        edited = try WebsiteConfigNativeProfile.editDraft(current, key: key, value: value,
          pointsPerRem: pointsPerRem, context: context, nosave: true)
      } catch WebsiteConfigNativeDraftError.rejectedEdit {
        // applyConfig ignores a normal setter false result (notably Memory
        // with tape mode). Later setters still run; actual errors propagate.
        return
      }
      var projection = edited.projection
      projection.events = current.projection.events + projection.events
      projection.rejectedKeys = current.projection.rejectedKeys + projection.rejectedKeys
      current = try current.replacingProjection(projection, memory: edited.lazyMemory, pointsPerRem: pointsPerRem)
    }
    if JoiningScriptFunboxPolicy.shouldClearAll(modifiers: original.generators.requestedModifiers,
      language: original.testParameters.language) {
      try apply("funbox", .array([]))
      onJoiningScriptClear?()
      return current
    }
    for funbox in original.generators.funboxes {
      switch funbox {
      case .modifier(.simonSays): try apply("keymapMode", .string("next"))
      case .modifier(.listening): try apply("keymapMode", .string("off"))
      case .modifier(.mirrorKeyboard):
        guard let layout = current.projection.runtime["layout"] else {
          throw WebsiteConfigNativeKeyboardTypographyError.missingField("layout")
        }
        try apply("layout", layout == .string("default") ? .string("qwerty") : layout)
        try apply("keymapLayout", .string("overrideSync"))
      case .modifier(.layoutFluid):
        guard case .array(let layouts)? = current.projection.runtime["customLayoutfluid"] else {
          throw WebsiteConfigNativeGeneratorsError.invalidField("customLayoutfluid")
        }
        let layout = layouts.first ?? .string("qwerty")
        try apply("layout", layout); try apply("keymapLayout", layout)
      case .modifier(.memory):
        try apply("showAllLines", .bool(true))
        if current.projection.runtime["keymapMode"] == .string("next") { try apply("keymapMode", .string("react")) }
      default: break
      }
    }
    return current
  }
}
