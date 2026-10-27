import AppKit
import SwiftUI

/// Offline schema/default preparation. Admission does not install a font,
/// activate a word source or apply/persist native settings.
@MainActor
enum WebsiteConfigNativeProfile {
  static let catalogs = WebsiteConfigCatalogs(
    languages: Set(WebsiteLanguageIdentity.byWebsiteName.keys),
    // Grove is Typebar-only. Shared names identify independently drawn themes,
    // not pixel-identical reference palettes.
    themes: Set(AppTheme.allCases.filter { $0 != .grove }.map(\.rawValue)),
    layouts: Set(KeyboardLayout.allCases.compactMap(OfficialLayoutCommandCatalog.name)),
    fonts: Set(FontFamilyCommandCatalog.fixedKnownFontIDs),
    funboxes: WebsiteFunboxAdmission.knownNames)

  static func defaultDocument() throws -> WebsiteConfigDefaultDocument {
    let theme = AppTheme.serika_dark.resolvedTheme
    let colors = try [theme.background, theme.accent, theme.caret, theme.secondaryText,
      theme.panel, theme.text, theme.error, theme.extraInput, theme.colorfulError,
      theme.colorfulExtraInput].map(hex)
    return try .init(appearance: .init(theme: AppTheme.serika_dark.rawValue,
      lightTheme: AppTheme.serika.rawValue, darkTheme: AppTheme.serika_dark.rawValue,
      fontFamily: "Roboto_Mono", customThemeColors: colors), catalogs: catalogs)
  }

  static func prepare(_ json: String, context: WebsiteConfigRuntimeContext) throws -> WebsiteConfigPreparedImport {
    try WebsiteConfigImportPreparation.prepare(json, defaultDocument: defaultDocument(),
      schema: .init(catalogs: catalogs), context: context)
  }

  static func prepareDraft(_ json: String, pointsPerRem: Double,
    context: WebsiteConfigRuntimeContext) throws -> WebsiteConfigNativeDraft {
    try .init(prepared: prepare(json, context: context), pointsPerRem: pointsPerRem)
  }

  static func editDraft(_ current: WebsiteConfigNativeDraft, key: String, value: WebsiteConfigValue,
    pointsPerRem: Double, context: WebsiteConfigRuntimeContext, testActive: Bool = false,
    nosave: Bool = false) throws -> WebsiteConfigNativeDraft {
    let previous = current.projection.runtime
    let projection = try WebsiteConfigRuntimeProjector.edit(current: previous, key: key, value: value,
      defaults: defaultDocument().values, schema: .init(catalogs: catalogs), context: context,
      testActive: testActive, nosave: nosave)
    var draft = try WebsiteConfigNativeDraft(edit: .init(key: key, previousRuntime: previous,
      projection: projection, previousStore: current.settingsStoreValues), pointsPerRem: pointsPerRem)
    draft.lazyMemory = current.lazyMemory
    draft.funboxMemory = current.funboxMemory
    return draft
  }

  static func prepareWebsiteRestoration(_ json: String?, context: WebsiteConfigRuntimeContext) throws -> WebsiteConfigPreparedRestoration {
    try WebsiteConfigRestoration.prepareWebsiteStorage(json, defaultDocument: defaultDocument(),
      schema: .init(catalogs: catalogs), context: context)
  }

  static func prepareNativeRestoration(_ read: WebsiteConfigNativeStateRead,
    context: WebsiteConfigRuntimeContext) throws -> WebsiteConfigNativeRestoreReadiness {
    try WebsiteConfigRestoration.prepareNativeState(read, defaultDocument: defaultDocument(),
      schema: .init(catalogs: catalogs), context: context)
  }

  private static func hex(_ color: Color) throws -> String {
    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { throw WebsiteConfigSchemaError.invalidDefaults }
    let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
    guard rgb.alphaComponent == 1, channels.allSatisfy({ $0.isFinite && (0...1).contains($0) })
    else { throw WebsiteConfigSchemaError.invalidDefaults }
    return "#" + channels.map { String(format: "%02x", Int(($0 * 255).rounded())) }.joined()
  }
}
