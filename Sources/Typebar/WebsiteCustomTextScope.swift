import Foundation

extension WebsiteCustomTextSettings {
  /// Raw source settings remain authoritative. Native strings are derived
  /// only for generation; joining them never becomes a new editor source.
  func applying(to previous: WebsiteConfigSessionBuilder.Scope) -> WebsiteConfigSessionBuilder.Scope {
    var scope = previous
    let pieces = text.map { String(decoding: $0.stringUnits ?? [], as: UTF16.self) }
    scope.websiteCustomText = self
    scope.preparedCustomSections = pieces
    scope.customText = pieces.joined(separator: " | ")
    scope.customTextIsPrepared = true; scope.finiteTextSource = nil
    scope.customCompletion = limitMode == "word" ? .words : limitMode == "time" ? .time : .sections
    scope.customOrdering = mode == "repeat" ? .inOrder : mode == "shuffle" ? .shuffled : .random
    scope.customPipeDelimiter = pipeDelimiter
    scope.customDurationOverride = limitMode == "time" ? limitValue : nil
    // A Swift String cannot own unpaired UTF-16. Retain/re-share that source,
    // but never silently practice against a replacement character instead.
    scope.customTextRecoveryBlocked = zip(text, pieces).contains { $0.0.stringUnits != Array($0.1.utf16) }
    return scope
  }

  func applyingLimit(to previous: TestConfiguration) throws -> TestConfiguration {
    var config = previous
    guard config.mode == .custom else { return config }
    func count() throws -> Int {
      if limitValue == .infinity { return 0 }
      let rounded = limitValue.rounded(.up)
      guard rounded >= 0, rounded <= Double(OfficialTestLimitInput.maximumValue) else {
        throw WebsiteConfigSessionBuildError.unrepresentableConfiguration
      }
      return Int(rounded)
    }
    switch limitMode {
    case "word": config.wordLimit = try count()
    case "section": config.customTextSectionLimit = try count()
    case "time":
      guard limitValue == .infinity || (limitValue >= 0 && limitValue <= Double(OfficialTestLimitInput.maximumValue)) else {
        throw WebsiteConfigSessionBuildError.unrepresentableConfiguration
      }
      config.duration = limitValue == .infinity ? 0 : limitValue
    default: throw WebsiteConfigSessionBuildError.unrepresentableConfiguration
    }
    return config
  }
}
