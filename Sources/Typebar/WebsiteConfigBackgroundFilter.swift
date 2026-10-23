/// Per-image inline filter declaration, separate from retained raw intent.
/// This is not a raster renderer or a validator for the other CSS properties.
/// Filter Effects 1 §6 forbids negative parameters; CSSOM setProperty ignores
/// an invalid whole declaration, whereas the empty string removes the property.
struct WebsiteConfigBackgroundFilter {
  enum Stage: Equatable {
    case blur(rem: Double)
    case brightness(multiplier: Double)
    case saturate(multiplier: Double)
    case opacity(multiplier: Double)
  }
  enum Update: Equatable { case replaced, ignoredInvalidDeclaration }
  private(set) var stages: [Stage] = []

  mutating func apply(_ filter: WebsiteConfigNativePagePreferences.BackgroundFilter) -> Update {
    let values = [filter.blurRem, filter.brightness, filter.saturation, filter.opacity]
    // The source interpolates bare JS numbers, not calc(infinity). Do not
    // silently turn negative/nonfinite raw values into a different valid chain.
    guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
      return .ignoredInvalidDeclaration
    }
    var next: [Stage] = []
    if filter.blurRem != 0 { next.append(.blur(rem: filter.blurRem)) }
    if filter.brightness != 1 { next.append(.brightness(multiplier: filter.brightness)) }
    if filter.saturation != 1 { next.append(.saturate(multiplier: filter.saturation)) }
    if filter.opacity != 1 { next.append(.opacity(multiplier: min(filter.opacity, 1))) }
    stages = next
    return .replaced
  }
}
