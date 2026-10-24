import Foundation

enum WebsiteConfigNativeGeneratorsError: Error, Equatable {
  case missingField(String), invalidField(String), invalidWord, invalidWordPosition, inconsistentTextModifiers
}

/// Final website generation intent, separate from legacy native normalization
/// and resource activation. Does not install settings or generate a word pool.
struct WebsiteConfigNativeGenerators {
  static let mappedKeys: Set<String> = ["funbox", "lazyMode", "customPolyglot", "customLayoutfluid"]
  let funboxes: [FunboxCommandTarget]
  let layoutFluidLayouts: [KeyboardLayout]
  let polyglotLanguages: [TypingLanguage]
  let lazyMode: Bool
  var requestsPolyglot: Bool { funboxes.contains(.polyglot) }
  var requestedModifiers: [TestModifier] {
    funboxes.compactMap(\.modifier) + (lazyMode ? [.lazyLatin] : [])
  }

  private static let schema = WebsiteConfigSchema(catalogs: .init(
    languages: Set(WebsiteLanguageIdentity.byWebsiteName.keys), themes: [],
    layouts: Set(KeyboardLayout.allCases.compactMap(OfficialLayoutCommandCatalog.name)),
    fonts: [], funboxes: WebsiteFunboxAdmission.knownNames))

  init(runtime: [String: WebsiteConfigValue]) throws {
    func value(_ key: String) throws -> WebsiteConfigValue {
      guard let value = runtime[key] else { throw WebsiteConfigNativeGeneratorsError.missingField(key) }
      guard Self.schema.accepts(value, for: key) else { throw WebsiteConfigNativeGeneratorsError.invalidField(key) }
      return value
    }
    func names(_ key: String) throws -> [String] {
      guard case .array(let values) = try value(key) else { throw WebsiteConfigNativeGeneratorsError.invalidField(key) }
      return try values.map {
        guard case .string(let name) = $0 else { throw WebsiteConfigNativeGeneratorsError.invalidField(key) }
        return name
      }
    }
    let funboxNames = try names("funbox")
    guard WebsiteFunboxAdmission.areCompatible(funboxNames) else { throw WebsiteConfigNativeGeneratorsError.invalidField("funbox") }
    funboxes = try funboxNames.map {
      guard let target = FunboxCommandCatalog.target(for: "funbox.changeFunbox\($0)"), target != .clear else {
        throw WebsiteConfigNativeGeneratorsError.invalidField("funbox")
      }
      return target
    }
    let layoutNames = try names("customLayoutfluid")
    guard Set(layoutNames).count == layoutNames.count else { throw WebsiteConfigNativeGeneratorsError.invalidField("customLayoutfluid") }
    layoutFluidLayouts = try layoutNames.map {
      guard case .builtIn(let layout) = OfficialLayoutCommandCatalog.target(for: "input.layout.\($0)") else {
        throw WebsiteConfigNativeGeneratorsError.invalidField("customLayoutfluid")
      }
      return layout
    }
    let languageNames = try names("customPolyglot")
    guard Set(languageNames).count == languageNames.count else { throw WebsiteConfigNativeGeneratorsError.invalidField("customPolyglot") }
    polyglotLanguages = try languageNames.map {
      guard let language = WebsiteLanguageIdentity.language(for: $0) else { throw WebsiteConfigNativeGeneratorsError.invalidField("customPolyglot") }
      return language
    }
    guard case .bool(let lazy) = try value("lazyMode") else { throw WebsiteConfigNativeGeneratorsError.invalidField("lazyMode") }
    lazyMode = lazy
  }

  /// Only the alterText stage: lazy-language admission, spelling and numeric
  /// generation precede this stage and are not re-applied by this kernel.
  func alteredWord(_ word: WebsiteConfigValue, wordIndex: Int = 0, wordBound: Int = 1,
    nextRandomCaseBit: () -> Bool = { Bool.random() }) throws -> WebsiteConfigValue {
    guard var units = word.stringUnits else { throw WebsiteConfigNativeGeneratorsError.invalidWord }
    guard wordIndex >= 0, wordBound >= 0 else { throw WebsiteConfigNativeGeneratorsError.invalidWordPosition }
    for case .modifier(let modifier) in funboxes {
      units = WebsiteOrderedTextAlteration.apply(modifier, to: units, wordIndex: wordIndex,
        wordBound: wordBound, nextRandomCaseBit: nextRandomCaseBit)
    }
    return .string(units: units)
  }

  /// Install only this stage on an already admitted engine configuration.
  /// This does not apply mode/rules, source selection or global preferences.
  func applyingTextOrder(to configuration: TestConfiguration) throws -> TestConfiguration {
    let supported = WebsiteOrderedTextAlteration.supportedModifiers
    let order = funboxes.compactMap(\.modifier).filter(supported.contains)
    guard Set(order) == Set(configuration.modifiers.filter(supported.contains)) else {
      throw WebsiteConfigNativeGeneratorsError.inconsistentTextModifiers
    }
    var result = configuration
    result.websiteTextAlterationOrder = order
    return result
  }
}
