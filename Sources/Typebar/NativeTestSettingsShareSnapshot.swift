import Foundation

/// Read-only selection capture. Whole-profile ownership and saved state stay
/// with the page; opening the share panel never adopts a website profile.
extension WebsiteTestSettingsShare {
  @MainActor
  static func pageSnapshot(_ page: PracticePageSessionState, native: () -> Snapshot) -> Snapshot? {
    if let receipt = page.sharedReceipt {
      return .init(runtime: receipt.outcome.state.settingsStore, customText: customText(in: receipt.scope),
        hasUnmappedQuote: receipt.outcome.state.settingsStore["mode"] == .string("quote"))
    }
    guard let draft = WebsiteConfigExport.draft(in: page), let practice = page.practice else {
      guard page.savedApplication == nil, page.configurationDeparture == nil else { return nil }
      return native()
    }
    let hasQuote = page.currentQuoteInitialization.map { $0.quote != nil } ?? (practice.quote != nil)
    return .init(runtime: WebsiteConfigExport.values(draft, surface: .settings),
      customText: customText(in: practice.scope), hasUnmappedQuote: hasQuote)
  }

  static func nativeSnapshot(configuration: TestConfiguration, scope: WebsiteConfigSessionBuilder.Scope) -> Snapshot {
    var values: [String: WebsiteConfigValue] = [
      "mode": .string(configuration.mode.rawValue),
      "time": .number(Double(scope.parameterMemory.duration)),
      "words": .number(Double(scope.parameterMemory.wordLimit)),
      "punctuation": .bool(configuration.contentOptions.includePunctuation),
      "numbers": .bool(configuration.contentOptions.includeNumbers),
      "difficulty": .string(configuration.difficulty.rawValue),
    ]
    var unavailable = Set<Field>()
    if configuration.mode == .time {
      if let time = configuration.duration, exactSharedInteger(time) { values["time"] = .number(time) }
      else { unavailable.insert(.parameter) }
    }
    if configuration.mode == .words {
      if let words = configuration.wordLimit, words >= 0, Int(exactly: Double(words)) == words,
        exactSharedInteger(Double(words)) {
        values["words"] = .number(Double(words))
      } else { unavailable.insert(.parameter) }
    }
    if let language = WebsiteLanguageIdentity.name(for: configuration.wordPoolBaseLanguage) {
      values["language"] = .string(language)
    } else { unavailable.insert(.language) }

    // Lazy mode is a separate Config field, outside the eight-slot format.
    var modifiers = configuration.modifiers.filter { $0 != .lazyLatin }
    if let order = configuration.websiteTextAlterationOrder {
      let supported = WebsiteOrderedTextAlteration.supportedModifiers
      let expected = modifiers.filter(supported.contains)
      if Set(order) == Set(expected), order.count == expected.count {
        var sequence = order.makeIterator()
        modifiers = modifiers.map { supported.contains($0) ? sequence.next()! : $0 }
      } else { unavailable.insert(.funbox) }
    }
    var names: [String] = []
    for modifier in modifiers {
      if let name = FunboxCommandCatalog.officialNames.first(where: {
        FunboxCommandCatalog.target(for: "funbox.changeFunbox" + $0) == .modifier(modifier)
      }) { names.append(name) }
      else { unavailable.insert(.funbox) }
    }
    if configuration.language == .mixedLanguages { names.append("polyglot") }
    if WebsiteFunboxAdmission.areCompatible(names), !unavailable.contains(.funbox) {
      values["funbox"] = .array(names.map(WebsiteConfigValue.string))
    } else { unavailable.insert(.funbox) }
    // Website caches belong to the profile/receipt branch of pageSnapshot.
    var nativeScope = scope
    nativeScope.websiteCustomText = nil
    return .init(runtime: values, customText: customText(in: nativeScope),
      hasUnmappedQuote: configuration.mode == .quote, unavailableFields: unavailable)
  }

  private static func exactSharedInteger(_ value: Double) -> Bool {
    // The receiving URL handler uses parseInt, including on exponent notation.
    value.isFinite && value >= 0
      && WebsiteThresholdCommandInput.integerPrefix(WebsiteNumberText.decimal(value)) == value
  }
}
