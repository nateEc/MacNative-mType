import Foundation

enum WebsiteConfigExternalContentError: Error, Equatable, LocalizedError {
  case poetryUnavailable
  var errorDescription: String? { "无法拉取诗歌段落。" }
}

/// One initialization attempt. The coordinator owns retries, saving source
/// corrections, and rejecting reads after the window/configuration changes.
@MainActor enum WebsiteConfigExternalContent {
  typealias Fetch = @MainActor (LivePracticeContentSource, TypingLanguage) async -> LivePracticeContent?

  static func prepare(source: LivePracticeContentSource, configuration: TestConfiguration,
    showAllLines: Bool, fetch: Fetch) async throws -> WebsiteConfigSessionBuilder.External {
    try Task.checkCancellation()
    guard LivePracticeContentSource.selected(for: configuration) == source else {
      throw WebsiteConfigSessionBuildError.invalidExternalSource
    }
    func read() async throws -> LivePracticeContent {
      try Task.checkCancellation()
      let content = await fetch(source, configuration.language)
      try Task.checkCancellation()
      guard let content else {
        if source == .poetry { throw WebsiteConfigExternalContentError.poetryUnavailable }
        throw WebsiteConfigSessionBuildError.generationFailed
      }
      guard content.source == source else { throw WebsiteConfigSessionBuildError.invalidExternalSource }
      return content
    }
    let first = try await read()
    var sectionError: Error?
    let filled = await first.fillingInitialPrompt(for: configuration, showAllLines: showAllLines) {
      do { return try await read() }
      catch { sectionError = error; return nil }
    }
    try Task.checkCancellation()
    if let sectionError { throw sectionError }
    guard let filled, !filled.text.isEmpty else { throw WebsiteConfigSessionBuildError.generationFailed }
    let initial = try await filled.preparingPromptDescriptor(for: configuration, showAllLines: showAllLines)
    let continuation = try await filled.preparingContinuationDescriptor(for: configuration, showAllLines: showAllLines)
    try Task.checkCancellation()
    return .init(source: source, initial: initial, continuation: continuation, attribution: filled.attribution)
  }
}
