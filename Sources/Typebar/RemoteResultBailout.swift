import Foundation

/// Anonymous completion limits, never the custom text being practiced.
struct RemoteResultCustomLimit: Codable, Equatable, Sendable {
  let mode: String
  let value: Int

  init(configuration: TestConfiguration) {
    switch configuration.customTextCompletion {
    case .finish: mode = "none"; value = 0
    case .time: mode = "time"; value = configuration.duration.map(Int.init) ?? 0
    case .words: mode = "word"; value = configuration.wordLimit ?? 0
    case .sections: mode = "section"; value = configuration.customTextSectionLimit ?? 0
    }
  }

  var isValid: Bool {
    ["none", "time", "word", "section"].contains(mode)
      && (0...OfficialTestLimitInput.maximumValue).contains(value)
      && (mode != "none" || value == 0)
  }
}

enum RemoteResultBailoutPolicy {
  /// Capability absence is not the same as a temporary transport failure.
  /// Completed legacy submissions retain their existing optional lookup.
  @MainActor static func capabilities(for outcome: TestOutcome, requiresElapsedTime: Bool = false,
    requiresIncompletePractice: Bool = false, requiresMode2: Bool = false, requiresAccountTags: Bool = false,
    load: () async throws -> RemoteServiceCapabilities) async throws -> RemoteServiceCapabilities? {
    do { return try await load() }
    catch {
      if outcome == .bailedOut || requiresElapsedTime || requiresIncompletePractice || requiresMode2 || requiresAccountTags,
        error is CancellationError || ResultPublicationRetryPolicy.shouldQueue(error) { throw error }
      return nil
    }
  }

  static func isValidHistory(mode: String, bailedOut: Bool?, duration: Int?, words: Int?,
    custom: RemoteResultCustomLimit?, measured: Double) -> Bool {
    guard bailedOut == true else { return custom == nil }
    guard measured.isFinite, (1...3_600).contains(measured) else { return false }
    let safe = 0...OfficialTestLimitInput.maximumValue
    switch mode {
    case "time":
      return custom == nil && words == nil && measured >= 15
        && duration.map { safe.contains($0) && ($0 == 0 || $0 >= 15) } == true
    case "words":
      return custom == nil && duration == nil && measured >= 15
        && words.map { safe.contains($0) && ($0 == 0 || $0 >= 10) } == true
    case "zen": return custom == nil && measured >= 15
    case "quote": return custom == nil
    case "custom":
      guard let custom, custom.isValid, measured >= 15 else { return false }
      switch custom.mode {
      case "word", "section": return custom.value >= 10
      case "time": return custom.value >= 15
      default: return true
      }
    default: return false
    }
  }
}
