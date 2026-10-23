import Foundation

enum WebsiteConfigNativePagePreferencesError: Error, Equatable {
  case missingField(String), invalidField(String), nonFinalChart, invalidLocalBackground
}

/// Page-level intent only. No image download, local-file lookup, ad SDK,
/// account read or settings write is performed by this model.
struct WebsiteConfigNativePagePreferences {
  enum AdvertisingPreference: String { case off, result, on, sellout }
  enum BackgroundSource: Equatable { case none, localFile, remote(WebsiteConfigValue) }
  struct AccountChart: Equatable {
    let speed: Bool, accuracy: Bool, average10: Bool, average100: Bool
  }
  struct BackgroundFilter: Equatable {
    let blurRem: Double, brightness: Double, saturation: Double, opacity: Double
  }
  static let mappedKeys: Set<String> = ["accountChart", "ads", "customBackground",
    "customBackgroundSize", "customBackgroundFilter"]
  let accountChart: AccountChart
  /// Retained for round-trip intent; never permission to serve native ads.
  let advertisingPreference: AdvertisingPreference
  let backgroundAddress: WebsiteConfigValue
  let backgroundFit: CustomBackgroundFit
  /// Source numbers, including infinity, negative values and signed zero.
  /// Not the clamped native filter or a promise that CSS rendered every value.
  let backgroundFilter: BackgroundFilter

  private static let schema = WebsiteConfigSchema(catalogs: .init(
    languages: [], themes: [], layouts: [], fonts: [], funboxes: []))

  init(runtime: [String: WebsiteConfigValue]) throws {
    func value(_ key: String) throws -> WebsiteConfigValue {
      guard let value = runtime[key] else { throw WebsiteConfigNativePagePreferencesError.missingField(key) }
      guard Self.schema.accepts(value, for: key) else { throw WebsiteConfigNativePagePreferencesError.invalidField(key) }
      return value
    }
    guard case .array(let chart) = try value("accountChart") else {
      throw WebsiteConfigNativePagePreferencesError.invalidField("accountChart")
    }
    accountChart = .init(speed: chart[0] == .string("on"), accuracy: chart[1] == .string("on"),
      average10: chart[2] == .string("on"), average100: chart[3] == .string("on"))
    guard accountChart.speed || accountChart.accuracy else { throw WebsiteConfigNativePagePreferencesError.nonFinalChart }
    guard case .string(let ads) = try value("ads"), let preference = AdvertisingPreference(rawValue: ads) else {
      throw WebsiteConfigNativePagePreferencesError.invalidField("ads")
    }
    advertisingPreference = preference
    backgroundAddress = try value("customBackground")
    guard backgroundAddress == backgroundAddress.trimmingWebsiteString else {
      throw WebsiteConfigNativePagePreferencesError.invalidField("customBackground")
    }
    guard case .string(let fit) = try value("customBackgroundSize"), let nativeFit = CustomBackgroundFit(rawValue: fit) else {
      throw WebsiteConfigNativePagePreferencesError.invalidField("customBackgroundSize")
    }
    backgroundFit = nativeFit
    guard case .array(let filters) = try value("customBackgroundFilter") else {
      throw WebsiteConfigNativePagePreferencesError.invalidField("customBackgroundFilter")
    }
    let numbers = try filters.map { item -> Double in
      guard case .number(let number) = item else { throw WebsiteConfigNativePagePreferencesError.invalidField("customBackgroundFilter") }
      return number
    }
    backgroundFilter = .init(blurRem: numbers[0], brightness: numbers[1], saturation: numbers[2], opacity: numbers[3])
  }

  /// Caller supplies admitted storage state. Empty local content overrides a
  /// remote address too, matching the source's undefined-vs-empty distinction.
  func backgroundSource(localFileAddress: WebsiteConfigValue? = nil) throws -> BackgroundSource {
    if let localFileAddress {
      guard let units = localFileAddress.stringUnits else { throw WebsiteConfigNativePagePreferencesError.invalidLocalBackground }
      return units.isEmpty ? .none : .localFile
    }
    return backgroundAddress == .string("") ? .none : .remote(backgroundAddress)
  }
}
