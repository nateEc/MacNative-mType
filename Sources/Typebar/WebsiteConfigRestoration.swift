import Foundation

struct WebsiteConfigPreparedRestoration {
  enum Origin { case websiteStorage, nativeState }
  struct WebsiteStoragePlan {
    enum ReadDisposition { case missing, valid, migrated, fallback }
    let disposition: ReadDisposition
    let writes: [String]
    let after: String?
    /// Source queues these corrections for debounced sync. This value is not
    /// a publication permission, timer, request, or account credential.
    let pendingSync: [String: WebsiteConfigValue]
  }
  let origin: Origin
  let loaded: [String: WebsiteConfigValue]
  let projection: WebsiteConfigRuntimeProjection
  let websiteStorage: WebsiteStoragePlan?
}

enum WebsiteConfigRestorationError: Error { case invalidStorageOrder, invalidNativeState }
enum WebsiteConfigNativeRestoreReadiness {
  case missing, unavailable, prepared(WebsiteConfigPreparedRestoration)
}

/// Cold-load preparation only. Writes and events are plans, not dispatched I/O.
enum WebsiteConfigRestoration {
  static let maximumStorageBytes = 8_388_608
  /// Observable full-schema serialization order, distinct from default order.
  /// These are field identifiers, not copied schema code or theme resources.
  static let storageOrderedKeys = [
    "punctuation", "numbers", "words", "time", "mode", "quoteLength", "language", "burstHeatmap",
    "difficulty", "quickRestart", "repeatQuotes", "resultSaving", "blindMode", "alwaysShowWordsHistory",
    "singleListCommandLine", "minWpm", "minWpmCustomSpeed", "minAcc", "minAccCustom", "minBurst",
    "minBurstCustomSpeed", "britishEnglish", "funbox", "customLayoutfluid", "customPolyglot",
    "freedomMode", "strictSpace", "oppositeShiftMode", "stopOnError", "deleteOnError", "confidenceMode",
    "quickEnd", "indicateTypos", "compositionDisplay", "hideExtraLetters", "lazyMode", "layout",
    "codeUnindentOnBackspace", "soundVolume", "playSoundOnClick", "playSoundOnError", "playTimeWarning",
    "smoothCaret", "caretStyle", "paceCaret", "paceCaretCustomSpeed", "paceCaretStyle", "repeatedPace",
    "timerStyle", "liveSpeedStyle", "liveAccStyle", "liveBurstStyle", "timerColor", "timerOpacity",
    "highlightMode", "typedEffect", "tapeMode", "tapeMargin", "smoothLineScroll", "showAllLines",
    "alwaysShowDecimalPlaces", "typingSpeedUnit", "startGraphsAtZero", "maxLineWidth", "fontSize",
    "fontFamily", "keymapMode", "keymapLayout", "keymapStyle", "keymapLegendStyle", "keymapKeys",
    "keymapSize", "flipTestColors", "colorfulMode", "customBackground", "customBackgroundSize",
    "customBackgroundFilter", "autoSwitchTheme", "themeLight", "themeDark", "randomTheme", "favThemes",
    "theme", "customTheme", "customThemeColors", "showKeyTips", "showOutOfFocusWarning", "capsLockWarning",
    "showAverage", "showPb", "accountChart", "monkey", "monkeyPowerLevel", "ads"]

  static func prepareWebsiteStorage(_ json: String?, defaultDocument: WebsiteConfigDefaultDocument,
    schema: WebsiteConfigSchema, context: WebsiteConfigRuntimeContext) throws -> WebsiteConfigPreparedRestoration {
    guard storageOrderedKeys.count == schema.keys.count, Set(storageOrderedKeys) == schema.keys else {
      throw WebsiteConfigRestorationError.invalidStorageOrder
    }
    let defaults = defaultDocument.values
    var loaded = defaults, cacheOrder = defaultDocument.orderedKeys
    var disposition = WebsiteConfigPreparedRestoration.WebsiteStoragePlan.ReadDisposition.missing
    var writes: [String] = []
    if let json {
      var parsed: WebsiteConfigValue?
      do { parsed = try WebsiteConfigJSONReader.read(json, maximumBytes: maximumStorageBytes) }
      catch WebsiteConfigJSONReadError.invalidJSON {
        disposition = .fallback
        writes.append(storageJSON(defaults, order: cacheOrder))
      }
      // Resource refusals propagate. Never propose repairing merely oversized
      // or over-deep data as if it were syntactically corrupt browser storage.
      if let parsed {
        if let fields = parsed.importFields, parsed.objectMembers?.count == fields.count,
          let complete = schema.validatingComplete(fields) {
          loaded = complete; cacheOrder = storageOrderedKeys; disposition = .valid
        } else {
          do {
            loaded = try parsed.importFields.map { try schema.migrating($0, defaults: defaults) } ?? defaults
            cacheOrder = storageOrderedKeys; disposition = .migrated
          } catch {
            loaded = defaults; disposition = .fallback
          }
          writes.append(storageJSON(loaded, order: cacheOrder))
        }
      }
    }
    let projection = try applyLoaded(loaded, defaultDocument: defaultDocument, schema: schema, context: context)
    let final = storageJSON(projection.runtime, order: storageOrderedKeys)
    // Source compares JSON strings against its parsed cache, not raw disk text.
    if final != storageJSON(loaded, order: cacheOrder) { writes.append(final) }
    return .init(origin: .websiteStorage, loaded: loaded, projection: projection,
      websiteStorage: .init(disposition: disposition, writes: writes, after: writes.last ?? json,
        pendingSync: Dictionary(uniqueKeysWithValues: projection.rejectedKeys.compactMap { key in
          projection.runtime[key].map { (key, $0) }
        })))
  }

  static func prepareNativeState(_ read: WebsiteConfigNativeStateRead,
    defaultDocument: WebsiteConfigDefaultDocument, schema: WebsiteConfigSchema,
    context: WebsiteConfigRuntimeContext) throws -> WebsiteConfigNativeRestoreReadiness {
    switch read {
    case .missing: return .missing
    case .unavailable: return .unavailable
    case .available(let loaded):
      guard Set(loaded.keys) == schema.keys, schema.validatingComplete(loaded) != nil else {
        throw WebsiteConfigRestorationError.invalidNativeState
      }
      return .prepared(.init(origin: .nativeState, loaded: loaded,
        projection: try applyLoaded(loaded, defaultDocument: defaultDocument, schema: schema, context: context),
        websiteStorage: nil))
    }
  }

  private static func applyLoaded(_ loaded: [String: WebsiteConfigValue],
    defaultDocument: WebsiteConfigDefaultDocument, schema: WebsiteConfigSchema,
    context: WebsiteConfigRuntimeContext) throws -> WebsiteConfigRuntimeProjection {
    let defaults = defaultDocument.values
    return try WebsiteConfigRuntimeProjector.project(requested: schema.migrating(loaded, defaults: defaults),
      defaults: defaults, orderedKeys: defaultDocument.orderedKeys, schema: schema, context: context)
  }

  private static func storageJSON(_ values: [String: WebsiteConfigValue], order: [String]) -> String {
    "{" + order.compactMap { key in values[key].map {
      WebsiteConfigJSONWriter.write(.string(key)) + ":" + WebsiteConfigJSONWriter.write($0)
    }}.joined(separator: ",") + "}"
  }
}
