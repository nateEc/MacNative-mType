import Foundation

enum PracticeRestartInstruction {
  static func text(hasStarted: Bool, key: QuickRestartKey, requiresProtection: Bool) -> String {
    let activity = hasStarted ? "正在练习" : "按任意键开始"
    if requiresProtection {
      let bailout = "双击 Shift+Enter 中止并显示结果"
      switch key {
      case .escape: return "\(activity)，Shift+Esc 可重新开始；\(bailout)"
      case .tab: return "\(activity)，Shift+Tab 可重新开始；\(bailout)"
      case .enter: return "\(activity)，⌘R 可重开；\(bailout)"
      case .off: return "\(activity)，可用 ⌘R 重开；\(bailout)"
      }
    }
    switch key {
    case .off: return "\(activity)，可使用 ⌘R 重新开始"
    case .escape: return "\(activity)，Esc 可重新开始"
    case .tab: return "\(activity)，Tab 可重新开始"
    case .enter: return "\(activity)，Enter 可重新开始"
    }
  }
}
