import Foundation

/// Window/document-local value memory. Neither the website JSON nor the
/// native disk record owns it; draft publications/checkpoints own its lifetime.
struct WebsiteConfigFunboxMemory: Equatable {
  struct Entry: Equatable { let key: String; let value: WebsiteConfigValue }
  private(set) var entries: [Entry] = []
  private mutating func save(_ key: String, from runtime: [String: WebsiteConfigValue]) {
    guard !entries.contains(where: { $0.key == key }), let value = runtime[key] else { return }
    entries.append(.init(key: key, value: value))
  }
  @MainActor static func proposal(for target: FunboxCommandTarget, in draft: WebsiteConfigNativeDraft) -> [String]? {
    guard case .array(let values)? = draft.projection.runtime["funbox"] else { return nil }
    let names = values.compactMap { if case .string(let name) = $0 { name } else { nil } }
    if target == .clear { return [] }
    guard let name = FunboxCommandCatalog.officialNames.first(where: {
      FunboxCommandCatalog.target(for: "funbox.changeFunbox" + $0) == target
    }) else { return nil }
    if names.contains(name) { return names.filter { $0 != name } }
    guard WebsiteFunboxAdmission.areCompatible(names + [name]) else { return nil }
    return (names + [name]).sorted()
  }
  @MainActor static func remembering(_ original: WebsiteConfigNativeDraft) -> WebsiteConfigNativeDraft {
    var result = original
    for funbox in original.generators.funboxes {
      let keys: [String]
      switch funbox {
      case .modifier(.accountingStream), .modifier(.ipv4Stream), .modifier(.ipv6Stream): keys = ["numbers"]
      case .modifier(.simonSays), .modifier(.listening): keys = ["keymapMode"]
      case .modifier(.arrowStream), .modifier(.readAheadEasy), .modifier(.readAhead), .modifier(.readAheadHard), .modifier(.noSpaces):
        keys = ["highlightMode"]
      case .modifier(.mirrorKeyboard): keys = ["keymapMode", "layout"]
      case .modifier(.layoutFluid): keys = ["keymapMode", "layout", "keymapLayout"]
      case .modifier(.memory): keys = ["mode", "showAllLines"] + (original.projection.runtime["keymapMode"] == .string("next") ? ["keymapMode"] : [])
      case .modifier(.hexadecimalStream): keys = ["punctuation"]
      default: keys = []
      }
      for key in keys { result.funboxMemory.save(key, from: original.projection.runtime) }
    }
    return result
  }

  /// Source setFunbox: restore through current active constraints, consume the
  /// memory even on a normal refusal, then run the saving selection setter.
  @MainActor static func selecting(_ value: WebsiteConfigValue, from original: WebsiteConfigNativeDraft,
    pointsPerRem: Double, context: WebsiteConfigRuntimeContext, testActive: Bool) throws -> (draft: WebsiteConfigNativeDraft, saved: Bool) {
    var current = original, events: [WebsiteConfigApplicationEvent] = []
    for entry in original.funboxMemory.entries {
      do {
        let edited = try WebsiteConfigNativeProfile.editDraft(current, key: entry.key, value: entry.value,
          pointsPerRem: pointsPerRem, context: context, testActive: testActive, nosave: true)
        events += edited.projection.events; current = edited
      } catch WebsiteConfigNativeDraftError.rejectedEdit { continue }
    }
    let projection = try WebsiteConfigRuntimeProjector.edit(current: current.projection.runtime, key: "funbox", value: value,
      defaults: WebsiteConfigNativeProfile.defaultDocument().values, schema: .init(catalogs: WebsiteConfigNativeProfile.catalogs),
      context: context, testActive: testActive)
    var combined = projection; combined.events = events + projection.events
    var result = try WebsiteConfigNativeDraft(funboxSelection: .init(key: "funbox", previousRuntime: original.projection.runtime,
      projection: combined), pointsPerRem: pointsPerRem)
    result.lazyMemory = original.lazyMemory
    result.funboxMemory = .init()
    return (result, projection.rejectedKeys.isEmpty)
  }
}
