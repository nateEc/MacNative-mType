import Foundation

/// Value-owned test-page listener and generation transition. Memory is
/// installed only with the complete configuration, never in old defaults.
@MainActor enum WebsiteConfigLazyModeLifecycle {
  enum NoticeTransition: Equatable { case disabled(polyglot: Bool), restored }
  /// A same-value setter still saves. Compare events, not final value equality;
  /// earlier application events must not be mistaken for new init saves.
  static func savesConfigurationDuringGeneration(from original: WebsiteConfigNativeDraft,
    to prepared: WebsiteConfigNativeDraft) -> Bool {
    prepared.projection.events.dropFirst(original.projection.events.count).contains { $0.nosave == false }
  }

  static func prepare(_ draft: WebsiteConfigNativeDraft, pointsPerRem: Double,
    replayApplicationEvents: Bool, onNoticeTransition: ((NoticeTransition) -> Void)? = nil) throws -> WebsiteConfigNativeDraft {
    let applied = replayApplicationEvents ? try applyingEvents(draft, pointsPerRem: pointsPerRem) : draft
    return try preparingGeneration(applied, pointsPerRem: pointsPerRem, onNoticeTransition: onNoticeTransition)
  }

  /// Synchronous config listeners run before restart initialization. Keep this
  /// separate from language-support normalization, which belongs to init.
  static func applyingEvents(_ draft: WebsiteConfigNativeDraft, pointsPerRem: Double) throws -> WebsiteConfigNativeDraft {
    func text(_ value: WebsiteConfigValue?) -> String? {
      value?.stringUnits.map { String(decoding: $0, as: UTF16.self) }
    }
    var projection = draft.projection, memory = draft.lazyMemory
    var language: String
    var lazy: Bool
    do {
      let initial: [String: WebsiteConfigValue]
      if case .received(let value) = draft.origin { initial = value.runtimeAtBoundary }
      else if case .edited(let value) = draft.origin { initial = value.previousRuntime }
      else { initial = try WebsiteConfigNativeProfile.defaultDocument().values }
      guard let name = text(initial["language"]), case .bool(let enabled)? = initial["lazyMode"] else {
        throw WebsiteConfigNativeDraftError.incompleteRuntime
      }
      language = name; lazy = enabled
    }
    func assignLazy(_ enabled: Bool, nosave: Bool) {
      projection.events.append(.init(key: "lazyMode", previousValue: .bool(lazy), newValue: .bool(enabled), nosave: nosave))
      lazy = enabled
      if !nosave && language.hasPrefix("arabic") { memory.prefersArabic = enabled }
    }
    do {
      let events: ArraySlice<WebsiteConfigApplicationEvent>
      if case .received(let value) = draft.origin {
        events = projection.events.dropFirst(value.appliedEventCount)
        projection.events = Array(projection.events.prefix(value.appliedEventCount))
      } else { events = projection.events[...]; projection.events = [] }
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
    projection.runtime["lazyMode"] = .bool(lazy)
    return try draft.replacingProjection(projection, memory: memory, pointsPerRem: pointsPerRem)
      .markingReceivedEventsApplied(pointsPerRem: pointsPerRem)
  }

  private static func preparingGeneration(_ draft: WebsiteConfigNativeDraft,
    pointsPerRem: Double, onNoticeTransition: ((NoticeTransition) -> Void)?) throws -> WebsiteConfigNativeDraft {
    var projection = draft.projection, memory = draft.lazyMemory
    guard let units = projection.runtime["language"]?.stringUnits else {
      throw WebsiteConfigNativeDraftError.incompleteRuntime
    }
    let language = String(decoding: units, as: UTF16.self)
    var lazy = draft.generators.lazyMode
    func assignLazy(_ enabled: Bool) {
      projection.events.append(.init(key: "lazyMode", previousValue: .bool(lazy), newValue: .bool(enabled), nosave: false))
      lazy = enabled
      if language.hasPrefix("arabic") { memory.prefersArabic = enabled }
    }
    guard let base = WebsiteLanguageIdentity.language(for: language) else {
      throw WebsiteConfigNativeTestParametersError.invalidField("language")
    }
    let baseSupports = base.supportsLazyLatinInput
    let allowed = draft.generators.requestsPolyglot
      ? draft.generators.polyglotLanguages.contains(where: \.supportsLazyLatinInput)
      : (baseSupports || draft.testParameters.mode == .custom)
    switch (lazy, allowed, memory.remember) {
    case (true, false, _):
      memory.remember = true
      onNoticeTransition?(.disabled(polyglot: draft.generators.requestsPolyglot))
      assignLazy(false)
    case (_, true, true):
      assignLazy(true); memory.remember = false
      onNoticeTransition?(.restored)
    default: break
    }
    // Source cleanup uses the base language even for polyglot, not the
    // aggregate admission above.
    if !lazy && baseSupports { memory.remember = false }
    projection.runtime["lazyMode"] = .bool(lazy)
    return try draft.replacingProjection(projection, memory: memory, pointsPerRem: pointsPerRem)
  }
}
