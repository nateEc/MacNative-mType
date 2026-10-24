import Foundation

/// Value-owned test-page listener and generation transition. Memory is
/// installed only with the complete configuration, never in old defaults.
@MainActor enum WebsiteConfigLazyModeLifecycle {
  static func prepare(_ draft: WebsiteConfigNativeDraft, pointsPerRem: Double,
    replayApplicationEvents: Bool) throws -> WebsiteConfigNativeDraft {
    func text(_ value: WebsiteConfigValue?) -> String? {
      value?.stringUnits.map { String(decoding: $0, as: UTF16.self) }
    }
    var projection = draft.projection, memory = draft.lazyMemory
    var language: String
    var lazy: Bool
    if replayApplicationEvents {
      let initial: [String: WebsiteConfigValue]
      if case .edited(let value) = draft.origin { initial = value.previousRuntime }
      else { initial = try WebsiteConfigNativeProfile.defaultDocument().values }
      guard let name = text(initial["language"]), case .bool(let enabled)? = initial["lazyMode"] else {
        throw WebsiteConfigNativeDraftError.incompleteRuntime
      }
      language = name; lazy = enabled
    } else {
      guard let name = text(draft.projection.runtime["language"]) else { throw WebsiteConfigNativeDraftError.incompleteRuntime }
      language = name
      lazy = draft.generators.lazyMode
    }
    func assignLazy(_ enabled: Bool, nosave: Bool) {
      projection.events.append(.init(key: "lazyMode", previousValue: .bool(lazy), newValue: .bool(enabled), nosave: nosave))
      lazy = enabled
      if !nosave && language.hasPrefix("arabic") { memory.prefersArabic = enabled }
    }
    if replayApplicationEvents {
      let events = projection.events; projection.events = []
      for var event in events {
        if event.key == "lazyMode" {
          event.previousValue = .bool(lazy)
          if case .bool(let value)? = event.newValue {
            lazy = value
            if event.nosave != true && language.hasPrefix("arabic") { memory.prefersArabic = value }
          }
        }
        projection.events.append(event)
        if event.key == "language", let name = text(event.newValue) {
          language = name
          if name.hasPrefix("arabic") && memory.prefersArabic { assignLazy(true, nosave: true) }
        }
      }
    }
    guard let base = WebsiteLanguageIdentity.language(for: language) else {
      throw WebsiteConfigNativeTestParametersError.invalidField("language")
    }
    let baseSupports = base.supportsLazyLatinInput
    let allowed = draft.generators.requestsPolyglot
      ? draft.generators.polyglotLanguages.contains(where: \.supportsLazyLatinInput)
      : (baseSupports || draft.testParameters.mode == .custom)
    switch (lazy, allowed, memory.remember) {
    case (true, false, _): memory.remember = true; assignLazy(false, nosave: false)
    case (_, true, true): assignLazy(true, nosave: false); memory.remember = false
    default: break
    }
    // Source cleanup uses the base language even for polyglot, not the
    // aggregate admission above.
    if !lazy && baseSupports { memory.remember = false }
    projection.runtime["lazyMode"] = .bool(lazy)
    return try draft.replacingProjection(projection, memory: memory, pointsPerRem: pointsPerRem)
  }
}
