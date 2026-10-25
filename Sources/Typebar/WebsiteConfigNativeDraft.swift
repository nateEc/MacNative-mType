import Foundation

enum WebsiteConfigNativeDraftError: Error { case incompleteRuntime, inconsistentCoverage, rejectedEdit }

struct WebsiteConfigPreparedEdit {
  let key: String
  let previousRuntime: [String: WebsiteConfigValue]
  let projection: WebsiteConfigRuntimeProjection
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
    var projection: WebsiteConfigRuntimeProjection {
      switch self {
      case .imported(let value): value.projection
      case .restored(let value): value.projection
      case .edited(let value): value.projection
      }
    }
  }
  let origin: Origin
  var lazyMemory = WebsiteConfigLazyModeMemory()
  var funboxMemory = WebsiteConfigFunboxMemory()
  var projection: WebsiteConfigRuntimeProjection { origin.projection }
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
    case .edited(let value): origin = .edited(.init(key: value.key, previousRuntime: value.previousRuntime, projection: projection))
    }
    var result = try Self(origin: origin, pointsPerRem: pointsPerRem)
    result.lazyMemory = memory
    result.funboxMemory = funboxMemory
    return result
  }
}
