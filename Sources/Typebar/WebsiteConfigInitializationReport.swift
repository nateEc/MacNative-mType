import Foundation

/// A producer's informational generation failure, including a silent empty
/// message. It still consumes initialization budget and retains its cause.
struct WebsiteWordGenerationError: Error, LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

struct WebsiteConfigInitializationExhaustedError: Error, LocalizedError {
  let underlying: Error
  let message: String
  var errorDescription: String? { message }
}

/// One initialization's diagnostics. No persistence, telemetry or OS alerts.
/// The existing local history owns presentation and its account/server scope.
@MainActor final class WebsiteConfigInitializationReport {
  struct Failure: Equatable {
    let attempt: Int
    let level: LocalNoticeLevel
    let message: String
    let reason: String?
    let category: String
  }
  private(set) var failures: [Failure] = []
  private(set) var exhausted = false
  private weak var notices: LocalNoticeCenter?
  private let noticeGeneration: UUID?
  private let lazyModeNotices: WebsiteConfigLazyModeNotices
  init(notices: LocalNoticeCenter? = nil, lazyModeNotices: WebsiteConfigLazyModeNotices? = nil) {
    self.notices = notices; noticeGeneration = notices?.deliveryGeneration
    self.lazyModeNotices = lazyModeNotices ?? .init()
  }
  func recordLazyMode(_ transition: WebsiteConfigLazyModeLifecycle.NoticeTransition, whileCurrent current: () -> Bool) {
    guard let notices, let noticeGeneration else { return }
    lazyModeNotices.record(transition, notices: notices, generation: noticeGeneration, whileCurrent: current)
  }
  func recordFunboxJoiningScriptClear(whileCurrent current: () -> Bool) {
    guard let notices, let noticeGeneration else { return }
    notices.postGuarded("当前语言的连写文字不支持所选趣味模式，已暂时清空整组选择。", level: .notice,
      options: .init(title: "趣味模式", details: .object(["category": .string("funbox_joining_script")])),
      generation: noticeGeneration, whileCurrent: current)
  }
  func record(_ failure: Failure, whileCurrent current: () -> Bool) {
    guard current(), failure.attempt == failures.count + 1, failure.attempt <= 3 else { return }
    failures.append(failure)
    if failure.level == .notice && failure.message.isEmpty { return }
    guard current(), let notices, let noticeGeneration else { return }
    var details: [String: LocalNoticeJSON] = ["attempt": .number(Double(failure.attempt)),
      "maximumAttempts": .number(3), "category": .string(failure.category)]
    if let reason = failure.reason { details["reason"] = .string(reason) }
    notices.postGuarded(failure.message, level: failure.level,
      options: .init(important: true, title: "准备练习 · \(failure.attempt)/3", details: .object(details)),
      generation: noticeGeneration, whileCurrent: current)
  }
  func finish() { exhausted = failures.last?.attempt == 3 }
  var finalMessage: String? {
    guard exhausted, let last = failures.last else { return nil }
    let reason = last.message.isEmpty ? "未能生成可用正文。" : last.message
    return "初始化已尝试三次，仍未完成。最后原因：\(reason)"
  }
  static func quote(attempt: Int, reason: WebsiteQuoteSampler.Reason, selectedQuoteID: String? = nil) -> Failure {
    let message: String, category: String
    switch reason {
    case .noLanguageQuotes:
      message = "该语言没有可用引语，改用词数练习。"; category = "quote_catalog_empty"
    case .selectedQuoteUnavailable:
      let id = selectedQuoteID.map { String($0.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(64)) }
      message = id.map { "指定引语（\($0)）不可用，改用全部长度。" } ?? "指定引语不可用，改用全部长度。"
      category = "selected_quote_unavailable"
    case .favoriteQuoteUnavailable:
      message = "收藏中没有可用引语，改用全部长度。"; category = "favorite_quote_unavailable"
    case .noSelectedLengthQuotes:
      message = "所选长度没有可用引语，改用全部长度。"; category = "quote_length_unavailable"
    }
    return .init(attempt: attempt, level: .notice, message: message, reason: nil, category: category)
  }
  static func generation(attempt: Int, error: Error,
    quote: WebsiteConfigSessionBuilder.QuoteInitialization?) -> Failure {
    let message: String
    switch error {
    case let failure as WebsiteWordGenerationError:
      let detail = String(failure.message.prefix(1000))
      let visible = detail.split(whereSeparator: \.isWhitespace).joined(separator: " ")
      let message = failure.message.isEmpty ? "" : visible.isEmpty ? "正文暂不可用。"
        : visible.count > 80 ? String(visible.prefix(79)) + "…" : visible
      return .init(attempt: attempt, level: .notice, message: message,
        reason: detail.isEmpty ? nil : detail, category: "word_generation")
    case WebsiteConfigSessionBuildError.generationFailed:
      if let value = quote?.quote, value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        message = "所选引语正文为空，无法开始练习。"
      } else if quote != nil, quote?.quote == nil {
        message = "当前引语尚未准备好，无法重复。"
      } else { message = "无法生成可用的练习正文。" }
    case WebsiteConfigSessionBuildError.customTextUnavailable:
      message = "自定义文本不可用，请检查或重新选择文本。"
    case WebsiteConfigSessionBuildError.invalidExternalSource:
      message = "内容来源返回了空正文，或与所选来源不一致的内容。"
    default:
      // Only an explicitly supplied human description, never Error reflection,
      // response bodies, arbitrary userInfo, stack traces or account objects.
      let raw = (error as? LocalizedError)?.errorDescription
        ?? ((error as NSError).userInfo[NSLocalizedDescriptionKey] as? String)
      let reason = raw.map { String($0.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(1000)) }
        .flatMap { $0.isEmpty ? nil : $0 }
      let visible = reason.map { $0.count > 80 ? String($0.prefix(79)) + "…" : $0 }
      return .init(attempt: attempt, level: .error,
        message: visible.map { "生成正文失败：" + $0 } ?? "生成正文失败，请检查内容来源。",
        reason: reason, category: "generation_error")
    }
    return .init(attempt: attempt, level: .notice, message: message, reason: nil, category: "generation_unavailable")
  }
}
