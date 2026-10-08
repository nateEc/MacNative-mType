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
  var shouldDismiss: Bool { outcome != .rejected }
}

@MainActor enum TestConfigurationShareActions {
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
    let rejection = "配置未应用。请先完成锁定测试，或检查该挑战的字体／脚本文本要求。"
    do {
      let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
      let preset: SavedTestPreset, fields: [TestConfigurationNoticeField]
      if URLComponents(string: trimmed)?.scheme?.lowercased() == "typebar" {
        preset = try TestConfigurationShare.preset(from: trimmed)
        fields = TestConfigurationNoticeField.allCases.filter {
          $0 != .customText || preset.customText != nil
        }
      } else {
        if let challenge = try LegacyChallengeLinkImporter.challenge(from: trimmed, challenges: challenges) {
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
      guard let applied = applyPreset(preset) else { return rejected(rejection, important: true) }
      if !fields.isEmpty {
        notices.post(summary(applied, fields: fields), level: .success,
          options: .init(durationMilliseconds: 10_000))
      }
      return .init(outcome: .applied, status: nil)
    } catch {
      // Known offline decoders expose fixed, localized messages, never the link/payload.
      return rejected((error as? LocalizedError)?.errorDescription ?? "无法导入该测试链接。")
    }
  }

  static func summary(_ preset: SavedTestPreset, fields: [TestConfigurationNoticeField]) -> String {
    let config = preset.configuration
    let lines = fields.map { field -> String in
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
    return "已从链接应用测试配置：\n\n" + lines.joined(separator: "\n")
  }
}
