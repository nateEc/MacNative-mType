import AppKit
import Observation
import SwiftUI

struct WebsiteBackgroundSettingsState: Equatable {
  struct Token: Equatable { let owner: UUID; let image: UUID }
  let token: Token?
  let url: String
  let fit: CustomBackgroundFit
  let values: [Double]
  let imageLoaded: Bool
  let canEdit: Bool
  @MainActor init(owner: UUID, draft: WebsiteConfigNativeDraft?, snapshot: WebsiteConfigBackgroundDisplay.Snapshot?, canEdit: Bool) {
    token = snapshot.map { .init(owner: owner, image: $0.identity) }
    let store = draft?.settingsStoreValues ?? [:]
    url = String(decoding: store["customBackground"]?.stringUnits ?? [], as: UTF16.self)
    fit = draft?.pagePreferences.backgroundFit ?? .cover
    if case .array(let items) = store["customBackgroundFilter"] {
      values = items.compactMap { if case .number(let value) = $0 { value } else { nil } }
    } else { values = [0, 1, 1, 1] }
    if case .ready? = snapshot?.resource.state { imageLoaded = true } else { imageLoaded = false }
    self.canEdit = canEdit && values.count == 4
  }
}
enum BackgroundSettingsTarget: Equatable { case native, website(WebsiteBackgroundSettingsState.Token) }

extension PracticePageSessionStore {
  var backgroundSettingsState: WebsiteBackgroundSettingsState? {
    guard ownsConfigurationSelection else { return nil }
    return .init(owner: owner, draft: state.savedApplication?.draft ?? state.presentation?.publication.draft,
      snapshot: state.savedApplication?.background.snapshot ?? state.presentation?.backgroundSnapshot,
      canEdit: state.savedApplication == nil && state.configurationDeparture == nil && state.sharedReceipt == nil && restartController?.isPreparing != true)
  }
}

/// The four DOM-range equivalents are kept separately from saved values.
@MainActor @Observable final class BackgroundSettingsPreferences {
  let settings: AppSettings
  private(set) var refs: [Double] = [0, 1, 1, 1]
  private(set) var labels: [Double] = [0, 1, 1, 1]
  @ObservationIgnored private var lastTarget: BackgroundSettingsTarget?
  @ObservationIgnored private var lastValues: [Double] = []
  var source: WebsiteBackgroundSettingsState? { settings.preferenceConfigurationSaves.backgroundSettingsState }
  var target: BackgroundSettingsTarget? {
    if let source { return source.token.map(BackgroundSettingsTarget.website) }
    return .native
  }
  var url: String { source?.url ?? settings.customBackgroundURL }
  var fit: CustomBackgroundFit { source?.fit ?? settings.customBackgroundFit }
  var canEdit: Bool { source?.canEdit ?? true }
  var filtersVisible: Bool { source?.imageLoaded ?? (settings.hasLocalBackground || !settings.customBackgroundURL.isEmpty) }
  init(settings: AppSettings) { self.settings = settings; synchronize() }
  func range(_ index: Int) -> ClosedRange<Double> {
    let maxima: [Double] = source == nil ? [20, 2, 3, 1] : [5, 2, 2, 1]
    return 0...maxima[index]
  }
  func step(_ index: Int) -> Double { source == nil ? (index == 0 ? 0.5 : 0.05) : 0.1 }
  static func sanitized(_ value: Double, range: ClosedRange<Double>, step: Double) -> Double {
    let finite = value.isFinite ? value : (range.lowerBound + range.upperBound) / 2
    let clamped = min(range.upperBound, max(range.lowerBound, finite))
    let base = Decimal(string: String(range.lowerBound))!, stride = Decimal(string: String(step))!
    var units = (Decimal(string: String(clamped))! - base) / stride, rounded = Decimal()
    NSDecimalRound(&rounded, &units, 0, .plain)
    return min(range.upperBound, NSDecimalNumber(decimal: base + rounded * stride).doubleValue)
  }
  func synchronize() {
    let f = settings.customBackgroundFilter
    let values = source?.values ?? [f.blur, f.brightness, f.saturation, f.opacity]
    guard values.count == 4 else { return }
    for index in 0..<4 where target != lastTarget || lastValues.count != 4 || values[index] != lastValues[index] {
      refs[index] = Self.sanitized(values[index], range: range(index), step: step(index)); labels[index] = values[index]
    }
    lastTarget = target; lastValues = values
  }
  func input(component: Int, value: Double, target requested: BackgroundSettingsTarget? = nil) -> Bool {
    guard (0..<4).contains(component), canEdit else { return false }
    synchronize()
    guard let current = target, requested == nil || requested == current else { return false }
    let value = Self.sanitized(value, range: range(component), step: step(component))
    refs[component] = value; labels[component] = value
    if case .website(let token) = current {
      guard filtersVisible else { return false }
      return settings.preferenceConfigurationSaves.applyBackgroundEdit(.previewFilter(token, refs)) == true
    }
    var filter = settings.customBackgroundFilter
    switch component { case 0: filter.blur = value; case 1: filter.brightness = value; case 2: filter.saturation = value; case 3: filter.opacity = value; default: return false }
    settings.customBackgroundFilter = filter
    return true
  }
  func commit(component: Int, value: Double, target requested: BackgroundSettingsTarget? = nil) -> Bool {
    guard (0..<4).contains(component), canEdit, let current = target, requested == nil || requested == current else { return false }
    if case .native = current { return true }
    guard case .website(let token) = current, filtersVisible else { return false }
    let value = Self.sanitized(value, range: range(component), step: step(component))
    return settings.preferenceConfigurationSaves.applyBackgroundEdit(.settingsFilter(token, component, value)) == true
  }
}
