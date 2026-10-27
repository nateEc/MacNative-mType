import Foundation

@MainActor enum ConfigurationNoticeFeedback {
  static func conflict(_ message: String, notices: LocalNoticeCenter, locked: Bool = false) {
    notices.post(message, options: .init(important: locked, durationMilliseconds: locked ? 3_000 : 5_000))
  }
}

enum TestConfigurationApplyOutcome: Equatable {
  case applied, requiresSetup, rejected
}

enum TestConfigurationNoticeField: Int, CaseIterable {
  case mode, parameter, customText, punctuation, numbers, language, difficulty, modifiers
}

struct TestConfigurationShareActionResult: Equatable {
  let outcome: TestConfigurationApplyOutcome
  let status: String?
  var keepPanel = false
  var shouldDismiss: Bool { outcome != .rejected && !keepPanel }
}

@MainActor enum TestConfigurationShareActions {
  static func applyAsync(_ link: String, current: SavedTestPreset,
    customTextFallback: LegacyTestSettingsLinkImporter.CustomTextFallback? = nil,
    challenges: [TypebarChallenge], notices: LocalNoticeCenter,
    applyWebsiteSettings: (@MainActor (String) async throws -> WebsiteSharedLinkApplication)?,
    applyPreset: (SavedTestPreset) -> SavedTestPreset?,
    loadChallenge: (TypebarChallenge) -> TestConfigurationApplyOutcome
  ) async -> TestConfigurationShareActionResult {
    do {
      try Task.checkCancellation()
      let url = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines))
      let isNative = url?.scheme?.lowercased() == "typebar"
      // Preserve the legacy web challenge branch, including its rejection
      // behavior, before considering a testSettings payload on the same URL.
      if !isNative, url?.queryItems?.contains(where: { $0.name == "challenge" }) == true {
        return apply(link, current: current, customTextFallback: customTextFallback,
          challenges: challenges, notices: notices, applyPreset: applyPreset, loadChallenge: loadChallenge)
      }
      if let applyWebsiteSettings, let json = try WebsiteSharedLinkImport.json(from: link) {
        let result = try await applyWebsiteSettings(json)
        try Task.checkCancellation()
        switch result {
        case .applied(let message):
          notices.post(message, level: .success)
          return .init(outcome: .applied, status: message)
        case .retained(let message):
          notices.post(message)
          return .init(outcome: .requiresSetup, status: message, keepPanel: true)
        }
      }
      if applyWebsiteSettings != nil, !isNative {
        throw LegacyTestSettingsLinkImporter.ImportError.invalidLink
      }
      return apply(link, current: current, customTextFallback: customTextFallback,
        challenges: challenges, notices: notices, applyPreset: applyPreset, loadChallenge: loadChallenge)
    } catch is WebsiteNativeSharedCompatibilityRequired {
      guard !Task.isCancelled else { return .init(outcome: .rejected, status: "准备已取消。") }
      return apply(link, current: current, customTextFallback: customTextFallback,
        challenges: challenges, notices: notices, applyPreset: applyPreset, loadChallenge: loadChallenge)
    } catch is CancellationError {
      return .init(outcome: .rejected, status: "准备已取消；已接收的设置会保留，可继续准备。")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? "无法导入该测试链接。"
      notices.post(message)
      return .init(outcome: .rejected, status: message)
    }
  }

  static func copy(_ link: String, notices: LocalNoticeCenter, write: (String) -> Bool) -> String {
    LocalNoticeClipboard.copyText(link, center: notices, success: "测试链接已复制。", write: write)
  }

  static func apply(_ link: String, current: SavedTestPreset,
    customTextFallback: LegacyTestSettingsLinkImporter.CustomTextFallback? = nil,
    challenges: [TypebarChallenge], notices: LocalNoticeCenter,
    applyPreset: (SavedTestPreset) -> SavedTestPreset?,
    loadChallenge: (TypebarChallenge) -> TestConfigurationApplyOutcome
  ) -> TestConfigurationShareActionResult {
    func rejected(_ message: String, important: Bool = false) -> TestConfigurationShareActionResult {
      notices.post(message, options: .init(important: important))
      return .init(outcome: .rejected, status: message)
    }
    let rejection = "配置未应用。请先完成锁定测试，或检查配置版本及挑战所需的字体／脚本文本。"
    do {
      let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
      let preset: SavedTestPreset, fields: [TestConfigurationNoticeField]
      let components = URLComponents(string: trimmed)
      let isNativeLink = components?.scheme?.lowercased() == "typebar"
      let isEightSlotLink = isNativeLink && components?.queryItems?.contains(where: { $0.name == "testSettings" }) == true
      if isNativeLink && !isEightSlotLink {
        preset = try TestConfigurationShare.preset(from: trimmed)
        fields = TestConfigurationNoticeField.allCases.filter {
          $0 != .customText || preset.customText != nil
        }
      } else {
        if !isNativeLink, let challenge = try LegacyChallengeLinkImporter.challenge(from: trimmed, challenges: challenges) {
          guard !PracticeThresholdSource.isPresent(in: current) else {
            return rejected(TestConfigurationShareError.thresholdSourceChallengeNotReady.errorDescription
              ?? "未应用挑战链接。")
          }
          let outcome = loadChallenge(challenge)
          switch outcome {
          case .rejected: return rejected(rejection, important: true)
          case .requiresSetup:
            notices.post("挑战已选择，请继续完成必需的设置。")
          case .applied: notices.post("挑战已应用：" + challenge.title, level: .success)
          }
          return .init(outcome: outcome, status: nil)
        }
        let imported = try LegacyTestSettingsLinkImporter.importedPreset(
          from: trimmed, current: current, customTextFallback: customTextFallback)
        preset = imported.preset; fields = imported.noticeFields
      }
      let prepared = try ShareThresholdAdmission.preparing(preset, current: current)
      guard let applied = applyPreset(prepared) else { return rejected(rejection, important: true) }
      if !fields.isEmpty {
        notices.post(summary(applied, fields: fields, includesThresholds: isNativeLink && !isEightSlotLink), level: .success,
          options: .init(durationMilliseconds: 10_000))
      }
      return .init(outcome: .applied, status: nil)
    } catch {
      // Known offline decoders expose fixed, localized messages, never the link/payload.
      return rejected((error as? LocalizedError)?.errorDescription ?? "无法导入该测试链接。")
    }
  }

  static func summary(_ preset: SavedTestPreset, fields: [TestConfigurationNoticeField],
    includesThresholds: Bool = false) -> String {
    let config = preset.configuration
    var lines = fields.map { field -> String in
      switch field {
      case .mode: return "模式：" + config.mode.rawValue
      case .parameter:
        if let duration = config.duration, duration.isFinite {
          return "时长：\(duration.formatted(.number.precision(.fractionLength(0)))) 秒"
        }
        if let words = config.wordLimit { return "词数：\(words)" }
        if let sections = config.customTextSectionLimit { return "段数：\(sections)" }
        return "范围：本机所选提示"
      case .customText: return "自定义文本：已应用（不在通知中保存正文）"
      case .punctuation: return "标点：" + (config.contentOptions.includePunctuation ? "开启" : "关闭")
      case .numbers: return "数字：" + (config.contentOptions.includeNumbers ? "开启" : "关闭")
      case .language: return "语言：" + config.language.displayName
      case .difficulty: return "难度：" + config.difficulty.rawValue
      case .modifiers:
        return "趣味模式：" + (config.modifiers.isEmpty ? "关闭" : config.modifiers.map(\.displayName).joined(separator: "、"))
      }
    }
    if includesThresholds, let raw = config.rules.thresholdSource?.configuration {
      func value(_ number: Double, unit: String) -> String {
        number.formatted(.number.precision(.fractionLength(0...2))) + unit
      }
      func threshold(_ enabled: Bool, remembered: String) -> String {
        enabled ? "开启（\(remembered)）" : "关闭（记忆 \(remembered)）"
      }
      lines.append("最低整体速度：" + threshold(raw.minimumWpmMode == .custom,
        remembered: value(raw.minimumWpmCustomValue, unit: " WPM")))
      lines.append("最低准确率：" + threshold(raw.minimumAccuracyMode == .custom,
        remembered: value(raw.minimumAccuracyCustomValue, unit: "%")))
      lines.append("最低单词速度：" + (raw.minimumWordBurstMode == .off ? "关闭（记忆 " :
        (raw.minimumWordBurstMode == .fixed ? "固定（" : "弹性（"))
        + value(raw.minimumWordBurstCustomValue, unit: " WPM") + "）")
    }
    return "已从链接应用测试配置：\n\n" + lines.joined(separator: "\n")
  }
}
