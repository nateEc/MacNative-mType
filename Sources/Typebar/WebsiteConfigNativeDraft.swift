import Foundation

enum WebsiteConfigNativeDraftError: Error { case incompleteRuntime, inconsistentCoverage }

/// Complete typed preflight, NOT an applied configuration. No legacy snapshot
/// normalization, resource activation, preference write or live event replay.
struct WebsiteConfigNativeDraft {
  static let fieldGroups: [Set<String>] = [WebsiteConfigNativeInputRules.mappedKeys,
    WebsiteConfigNativePresentation.mappedKeys, WebsiteConfigNativeBehavior.mappedKeys,
    WebsiteConfigNativeKeyboardTypography.mappedKeys, WebsiteConfigNativeTestParameters.mappedKeys,
    WebsiteConfigNativeQuoteSelection.mappedKeys, WebsiteConfigNativeGenerators.mappedKeys,
    WebsiteConfigNativeThemes.mappedKeys, WebsiteConfigNativePagePreferences.mappedKeys]
  static var mappedKeys: Set<String> { fieldGroups.reduce(into: Set<String>()) { $0.formUnion($1) } }

  let prepared: WebsiteConfigPreparedImport
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
    let keys = WebsiteConfigSchema(catalogs: WebsiteConfigNativeProfile.catalogs).keys
    guard Self.mappedKeys == keys, Self.fieldGroups.reduce(0, { $0 + $1.count }) == keys.count else {
      throw WebsiteConfigNativeDraftError.inconsistentCoverage
    }
    let runtime = prepared.projection.runtime
    guard Set(runtime.keys) == keys else { throw WebsiteConfigNativeDraftError.incompleteRuntime }
    self.prepared = prepared
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
}
