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
    showAllLines: Bool, checkCurrent: WebsiteConfigSessionBuilder.ExternalReadAdmission = {},
    fetch: Fetch) async throws -> WebsiteConfigSessionBuilder.External {
    func check() throws {
      try Task.checkCancellation()
      try checkCurrent()
      try Task.checkCancellation()
    }
    try check()
    guard LivePracticeContentSource.selected(for: configuration) == source else {
      throw WebsiteConfigSessionBuildError.invalidExternalSource
    }
    func read() async throws -> LivePracticeContent {
      try check()
      let content = await fetch(source, configuration.language)
      try check()
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
    try check()
    if let sectionError { throw sectionError }
    guard let filled, !filled.text.isEmpty else { throw WebsiteConfigSessionBuildError.generationFailed }
    let initial = try await filled.preparingPromptDescriptor(for: configuration, showAllLines: showAllLines)
    try check()
    let continuation = try await filled.preparingContinuationDescriptor(for: configuration, showAllLines: showAllLines)
    try check()
    return .init(source: source, initial: initial, continuation: continuation, attribution: filled.attribution)
  }
}
