import Foundation

/// Source callbacks operate on the current configuration, rather than deriving
/// both input and visual layout unconditionally from elapsed progress.
@MainActor enum WebsiteLayoutFluidTransition {
  enum Event {
    case time(Int), words(completed: Int, total: Int), wordNavigation(WebsiteWordNavigationEvent)
    var navigation: WebsiteWordNavigationEvent? { if case .wordNavigation(let value) = self { return value }; return nil }
    var wordProgress: (completed: Int, total: Int)? {
      switch self {
      case .words(let completed, let total): (completed, total)
      case .wordNavigation(let value): (value.completed, value.total)
      case .time: nil
      }
    }
  }
  struct Step { let key: String; let value: WebsiteConfigValue; let accepted: Bool; let nosave: Bool }
  struct Plan { let steps: [Step]; let failedOverride: Bool }
  static func plan(current: [String: WebsiteConfigValue], event: Event,
    context: WebsiteConfigRuntimeContext, active: Bool) throws -> Plan {
    guard case .array(let boxes) = current["funbox"], boxes.contains(.string("layoutfluid")),
      case .array(let layouts) = current["customLayoutfluid"], !layouts.isEmpty else {
      return .init(steps: [], failedOverride: false)
    }
    let index: Int, nosave: Bool
    if let progress = event.wordProgress {
      let (completed, total) = progress
      guard current["mode"] != .string("time"), completed > 0, total > 0 else { return .init(steps: [], failedOverride: false) }
      let segment = total / layouts.count
      guard segment > 0, completed % segment == 0, completed / segment < layouts.count else { return .init(steps: [], failedOverride: false) }
      index = completed / segment; nosave = false
    } else if case .time(let second) = event {
      guard current["mode"] == .string("time"), second >= 0, case .number(let duration) = current["time"], duration > 0 else {
        return .init(steps: [], failedOverride: false)
      }
      let quotient = floor(Double(second) / (duration / Double(layouts.count)))
      guard quotient.isFinite, quotient >= 0, quotient < Double(layouts.count) else { return .init(steps: [], failedOverride: false) }
      index = Int(quotient); nosave = true
      guard current["layout"] != layouts[index] else { return .init(steps: [], failedOverride: false) }
    } else { return .init(steps: [], failedOverride: false) }
    var runtime = current, steps: [Step] = []
    do {
      for key in ["layout", "keymapLayout"] {
        let result = try WebsiteConfigRuntimeProjector.edit(current: runtime, key: key, value: layouts[index],
          defaults: WebsiteConfigNativeProfile.defaultDocument().values,
          schema: .init(catalogs: WebsiteConfigNativeProfile.catalogs), context: context, testActive: active, nosave: nosave,
          observeAssignment: { steps.append(.init(key: $0, value: $1, accepted: $2, nosave: nosave)) })
        runtime = result.runtime
      }
      return .init(steps: steps, failedOverride: false)
    } catch WebsiteConfigProjectionError.failedOverride { return .init(steps: steps, failedOverride: true) }
  }
  static func admits(_ draft: WebsiteConfigNativeDraft, from previous: WebsiteConfigNativeDraft) -> Bool {
    guard previous.generators.requestedModifiers.contains(.layoutFluid), case .edited(let edit) = draft.origin,
      ["layout", "keymapLayout", "keymapMode"].contains(edit.key), draft.projection.rejectedKeys.isEmpty,
      draft.projection.events.count == 1, let event = draft.projection.events.first, event.key == edit.key, event.nosave != nil,
      draft.projection.runtime.count == previous.projection.runtime.count else { return false }
    if edit.key == "keymapMode" {
      guard draft.projection.runtime[edit.key] == .string("static") else { return false }
    } else {
      guard case .array(let layouts) = previous.projection.runtime["customLayoutfluid"],
        let value = draft.projection.runtime[edit.key], layouts.contains(value) else { return false }
    }
    return previous.projection.runtime.allSatisfy { key, value in key == edit.key || draft.projection.runtime[key] == value }
  }
}
