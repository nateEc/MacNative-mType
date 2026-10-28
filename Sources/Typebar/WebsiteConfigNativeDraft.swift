import Foundation

enum WebsiteConfigNativeDraftError: Error { case incompleteRuntime, inconsistentCoverage, rejectedEdit }

struct WebsiteConfigPreparedEdit {
  let key: String
  let previousRuntime: [String: WebsiteConfigValue]
  let projection: WebsiteConfigRuntimeProjection
  let previousStore: [String: WebsiteConfigValue]
  init(key: String, previousRuntime: [String: WebsiteConfigValue], projection: WebsiteConfigRuntimeProjection,
    previousStore: [String: WebsiteConfigValue]? = nil) {
    self.key = key; self.previousRuntime = previousRuntime; self.projection = projection
    self.previousStore = previousStore ?? previousRuntime
  }
}

struct WebsiteConfigReceivedProjection {
  var projection: WebsiteConfigRuntimeProjection
  var runtimeAtBoundary: [String: WebsiteConfigValue]
  var storeAtBoundary: [String: WebsiteConfigValue]
  var appliedEventCount: Int
}

/// Complete typed preflight, NOT an applied configuration. No legacy snapshot
/// normalization, resource activation, preference write or live event replay.
struct WebsiteConfigNativeDraft {
  static let fieldGroups: [Set<String>] = [WebsiteConfigNativeInputRules.mappedKeys,
    WebsiteConfigNativePresentation.mappedKeys, WebsiteConfigNativeBehavior.mappedKeys,
    WebsiteConfigNativeKeyboardTypography.mappedKeys, WebsiteConfigNativeTestParameters.mappedKeys,
    WebsiteConfigNativeQuoteSelection.mappedKeys, WebsiteConfigNativeGenerators.mappedKeys,
    WebsiteConfigNativeThemes.mappedKeys, WebsiteConfigNativePagePreferences.mappedKeys]
  static var mappedKeys: Set<String> { fieldGroups.reduce(into: Set<String>()) { $0.formUnion($1) } }

  enum Origin {
    case imported(WebsiteConfigPreparedImport), restored(WebsiteConfigPreparedRestoration)
    case edited(WebsiteConfigPreparedEdit)
    case received(WebsiteConfigReceivedProjection)
    var projection: WebsiteConfigRuntimeProjection {
      switch self {
      case .imported(let value): value.projection
      case .restored(let value): value.projection
      case .edited(let value): value.projection
      case .received(let value): value.projection
      }
    }
  }
  let origin: Origin
  var lazyMemory = WebsiteConfigLazyModeMemory()
  var funboxMemory = WebsiteConfigFunboxMemory()
  var projection: WebsiteConfigRuntimeProjection { origin.projection }
  /// Separate value state for the settings store. Full application publishes
  /// its requested snapshot after synchronous events; later ordinary setters
  /// update just their assigned fields, retaining unrelated store differences.
  /// This is window-owned state, not an extra persisted configuration.
  var settingsStoreValues: [String: WebsiteConfigValue] {
    let projection = projection
    if case .received(let value) = origin {
      var store = value.storeAtBoundary
      for event in projection.events.dropFirst(value.appliedEventCount) {
        if let new = event.newValue, store[event.key] != nil { store[event.key] = new }
      }
      return store
    }
    var values: [String: WebsiteConfigValue]
    let events: ArraySlice<WebsiteConfigApplicationEvent>
    if let finish = projection.events.lastIndex(where: { $0.key == "fullConfigChangeFinished" }) {
      values = projection.requested
      events = projection.events.suffix(from: finish + 1)
    } else {
      if case .edited(let edit) = origin { values = edit.previousStore }
      else { values = projection.requested }
      events = projection.events[...]
    }
    for event in events {
      if let value = event.newValue, values[event.key] != nil { values[event.key] = value }
    }
    return values
  }
  /// Restore evidence is never presented as an original JSON import.
  var prepared: WebsiteConfigPreparedImport? {
    guard case .imported(let prepared) = origin else { return nil }; return prepared
  }
  let inputRules: WebsiteConfigNativeInputRules
  let presentation: WebsiteConfigNativePresentation
  let behavior: WebsiteConfigNativeBehavior
  let keyboardTypography: WebsiteConfigNativeKeyboardTypography
  let testParameters: WebsiteConfigNativeTestParameters
  let quoteSelection: WebsiteConfigNativeQuoteSelection
  let generators: WebsiteConfigNativeGenerators
  let themes: WebsiteConfigNativeThemes
  let pagePreferences: WebsiteConfigNativePagePreferences

  @MainActor
  init(prepared: WebsiteConfigPreparedImport, pointsPerRem: Double) throws {
    try self.init(origin: .imported(prepared), pointsPerRem: pointsPerRem)
  }

  @MainActor
  init(restoration: WebsiteConfigPreparedRestoration, pointsPerRem: Double) throws {
    try self.init(origin: .restored(restoration), pointsPerRem: pointsPerRem)
  }

  @MainActor
  init(edit: WebsiteConfigPreparedEdit, pointsPerRem: Double) throws {
    guard edit.projection.rejectedKeys.isEmpty else { throw WebsiteConfigNativeDraftError.rejectedEdit }
    try self.init(origin: .edited(edit), pointsPerRem: pointsPerRem)
  }
  @MainActor
  init(funboxSelection edit: WebsiteConfigPreparedEdit, pointsPerRem: Double) throws {
    guard edit.key == "funbox", edit.projection.rejectedKeys.allSatisfy({ $0 == "funbox" }) else {
      throw WebsiteConfigNativeDraftError.rejectedEdit
    }
    try self.init(origin: .edited(edit), pointsPerRem: pointsPerRem)
  }

  @MainActor
  init(received outcome: WebsiteSharedSettingsReceiver.Outcome, pointsPerRem: Double) throws {
    guard !outcome.parseRejected else { throw WebsiteSharedSettingsReceiver.Failure.invalidPayload }
    try self.init(origin: .received(.init(projection: .init(requested: outcome.state.runtime,
      runtime: outcome.state.runtime, rejectedKeys: [], events: outcome.events),
      runtimeAtBoundary: outcome.state.runtime, storeAtBoundary: outcome.state.settingsStore,
      appliedEventCount: outcome.events.count)), pointsPerRem: pointsPerRem)
    lazyMemory = outcome.state.lazyMemory
  }

  @MainActor
  private init(origin: Origin, pointsPerRem: Double) throws {
    let keys = WebsiteConfigSchema(catalogs: WebsiteConfigNativeProfile.catalogs).keys
    guard Self.mappedKeys == keys, Self.fieldGroups.reduce(0, { $0 + $1.count }) == keys.count else {
      throw WebsiteConfigNativeDraftError.inconsistentCoverage
    }
    let runtime = origin.projection.runtime
    guard Set(runtime.keys) == keys else { throw WebsiteConfigNativeDraftError.incompleteRuntime }
    self.origin = origin
    inputRules = try .init(runtime: runtime)
    presentation = try .init(runtime: runtime)
    behavior = try .init(runtime: runtime)
    keyboardTypography = try .init(runtime: runtime, pointsPerRem: pointsPerRem)
    testParameters = try .init(runtime: runtime)
    quoteSelection = try .init(runtime: runtime)
    generators = try .init(runtime: runtime)
    themes = try .init(runtime: runtime)
    pagePreferences = try .init(runtime: runtime)
  }

  /// Add admitted listener effects without losing the original transport or
  /// setter origin. Every typed owner is rebuilt from the resulting runtime.
  @MainActor
  func replacingProjection(_ projection: WebsiteConfigRuntimeProjection,
    memory: WebsiteConfigLazyModeMemory, pointsPerRem: Double) throws -> Self {
    let origin: Origin
    switch self.origin {
    case .imported(var value): value.projection = projection; origin = .imported(value)
    case .restored(let value): origin = .restored(.init(origin: value.origin, loaded: value.loaded,
      projection: projection, websiteStorage: value.websiteStorage))
    case .edited(let value): origin = .edited(.init(key: value.key, previousRuntime: value.previousRuntime,
      projection: projection, previousStore: value.previousStore))
    case .received(var value): value.projection = projection; origin = .received(value)
    }
    var result = try Self(origin: origin, pointsPerRem: pointsPerRem)
    result.lazyMemory = memory
    result.funboxMemory = funboxMemory
    return result
  }

  @MainActor
  func receivingRuntimeEffect(_ runtime: [String: WebsiteConfigValue], pointsPerRem: Double) throws -> Self {
    // A listener prefix is a new runtime boundary, not a replay of the prior
    // import/setter. Reuse the received-projection shape to freeze its store;
    // this does not create a shared receipt or mark any new setter accepted.
    var result = try Self(origin: .received(.init(projection: .init(requested: projection.requested,
      runtime: runtime, rejectedKeys: [], events: []), runtimeAtBoundary: runtime,
      storeAtBoundary: settingsStoreValues, appliedEventCount: 0)), pointsPerRem: pointsPerRem)
    result.lazyMemory = lazyMemory; result.funboxMemory = funboxMemory
    return result
  }

  @MainActor
  func markingReceivedEventsApplied(pointsPerRem: Double) throws -> Self {
    guard case .received(var value) = origin else { return self }
    value.runtimeAtBoundary = projection.runtime; value.storeAtBoundary = settingsStoreValues
    value.appliedEventCount = projection.events.count
    var result = try Self(origin: .received(value), pointsPerRem: pointsPerRem)
    result.lazyMemory = lazyMemory; result.funboxMemory = funboxMemory
    return result
  }
}
