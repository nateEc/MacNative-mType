import Foundation

/// A browser-document-like window lifetime, independent of configuration
/// persistence. Account/server generations cannot inherit another latch.
@MainActor final class WebsiteConfigLazyModeNotices {
  private var generation: UUID?
  private var showed = false

  func record(_ transition: WebsiteConfigLazyModeLifecycle.NoticeTransition,
    notices: LocalNoticeCenter, generation: UUID, whileCurrent current: () -> Bool) {
    guard notices.deliveryGeneration == generation, current() else { return }
    if self.generation != generation { self.generation = generation; showed = false }
    switch transition {
    case .restored: showed = false
    case .disabled(let polyglot):
      guard !showed else { return }
      let message = polyglot ? "所选多语语言均不支持简化输入，已暂时关闭。" : "当前语言不支持简化输入，已暂时关闭。"
      let receipt = notices.postGuarded(message, level: .notice,
        options: .init(important: true, title: "简化输入", details: .object([
          "category": .string("lazy_mode_unsupported"), "scope": .string(polyglot ? "polyglot" : "language")
        ])), generation: generation, whileCurrent: current)
      // Posting may synchronously cancel this request or change account.
      if receipt != nil { showed = true }
    }
  }
}
