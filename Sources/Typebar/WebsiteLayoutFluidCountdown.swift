import Foundation

struct WebsiteLayoutFluidCountdown: Equatable {
  enum Action: Equatable {
    case show, hide, text(String)
    var trace: String {
      switch self { case .show: "show"; case .hide: "hide"; case .text(let value): "text:" + value }
    }
  }
  private(set) var visible = false
  private(set) var text: String?
  mutating func apply(_ actions: [Action]) {
    for action in actions {
      switch action { case .show: visible = true; case .hide: visible = false; case .text(let value): text = value }
    }
  }
  @MainActor static func actions(current: [String: WebsiteConfigValue], event: WebsiteLayoutFluidTransition.Event) -> [Action] {
    guard case .array(let boxes) = current["funbox"], boxes.contains(.string("layoutfluid")),
      case .array(let values) = current["customLayoutfluid"] else { return [] }
    let layouts = values.compactMap { if case .string(let name) = $0 { name } else { nil } }
    guard layouts.count == values.count else { return [] }
    func capitalized(_ name: String) -> String { name.prefix(1).uppercased() + name.dropFirst() }
    if let progress = event.wordProgress {
      guard current["mode"] != .string("time"), progress.completed > 0 else { return [] }
      guard !layouts.isEmpty else { return [.hide] }
      let segment = progress.total / layouts.count
      guard segment > 0 else { return [.hide] }
      let index = progress.completed / segment
      guard index < layouts.count else { return [.hide] }
      let remaining = segment - progress.completed % segment
      var actions: [Action] = []
      if remaining <= 3, index + 1 < layouts.count {
        let name = capitalized(layouts[index + 1].replacingOccurrences(of: "_", with: " "))
        actions = [.show, .text(remaining == 1 ? "\(name) starting next word" : "\(name) in: \(remaining) words")]
      } else { actions = [.hide] }
      if progress.completed % segment == 0, remaining > 3 { actions.append(.hide) }
      return actions
    }
    guard case .time(let second) = event, second >= 0, current["mode"] == .string("time"),
      !layouts.isEmpty, case .number(let duration) = current["time"], duration.isFinite, duration > 0 else { return [] }
    let interval = duration / Double(layouts.count)
    let quotient = floor(Double(second) / interval)
    guard quotient >= 0, quotient < Double(layouts.count) else { return [] }
    let index = Int(quotient)
    let boundaries = (1..<layouts.count).map { floor(interval * Double($0)) }
    var actions: [Action] = []
    for remaining in stride(from: 3, through: 1, by: -1) where boundaries.contains(Double(second) + Double(remaining)) {
      if remaining == 3 { actions.append(.show) }
      if index + 1 < layouts.count { actions.append(.text("\(capitalized(layouts[index + 1])) in: \(remaining)s")) }
      break
    }
    if current["layout"] != .string(layouts[index]) { actions.append(.hide) }
    return actions
  }
}
