import Foundation

/// A pasteable, offline Typebar theme link. It contains only colors and, when
/// explicitly requested, a remote image URL and its display settings.
enum NativeCustomThemeShare {
  enum ShareError: Error, LocalizedError {
    case invalidTheme
    case invalidBackground
    case invalidLink
    case invalidPayload
    case unsupportedVersion

    var errorDescription: String? {
      switch self {
      case .invalidTheme: "主题名称或颜色无效，无法分享。"
      case .invalidBackground: "背景图片必须是安全的 HTTPS 图片链接。"
      case .invalidLink: "这不是有效的 Typebar 主题链接。"
      case .invalidPayload: "Typebar 主题链接的内容无效。"
      case .unsupportedVersion: "这个 Typebar 主题链接来自不支持的版本。"
      }
    }
  }

  private struct Payload: Codable {
    let version: Int
    let theme: CustomThemeDefinition
    let background: Background?
  }

  private struct Background: Codable {
    let url: String
    let fit: CustomBackgroundFit
    let filter: CustomBackgroundFilter
  }

  private static let maximumLinkLength = 32_768
  private static let maximumPayloadLength = 16_384

  static func link(
    for theme: CustomThemeDefinition,
    backgroundURL: String? = nil,
    backgroundFit: CustomBackgroundFit? = nil,
    backgroundFilter: CustomBackgroundFilter? = nil
  ) throws -> String {
    guard valid(theme) else { throw ShareError.invalidTheme }
    let background: Background?
    if let backgroundURL {
      guard let backgroundFit, let backgroundFilter,
        let safeURL = secureImageURL(backgroundURL)
      else { throw ShareError.invalidBackground }
      background = .init(url: safeURL, fit: backgroundFit, filter: backgroundFilter.normalized)
    } else {
      background = nil
    }
    let portableTheme = copy(theme)
    let data = try JSONEncoder().encode(Payload(version: 1, theme: portableTheme, background: background))
    guard data.count <= maximumPayloadLength else { throw ShareError.invalidPayload }
    let token = data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    var components = URLComponents()
    components.scheme = "typebar"
    components.host = "theme"
    components.queryItems = [.init(name: "data", value: token)]
    guard let link = components.string, link.count <= maximumLinkLength else {
      throw ShareError.invalidPayload
    }
    return link
  }

  static func theme(from rawLink: String) throws -> LegacyCustomThemeLinkImporter.ImportedTheme {
    let link = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !link.isEmpty, link.count <= maximumLinkLength,
      let components = URLComponents(string: link),
      components.scheme?.lowercased() == "typebar", components.host?.lowercased() == "theme",
      components.path.isEmpty, components.fragment == nil,
      components.user == nil, components.password == nil, components.port == nil,
      let items = components.queryItems, items.count == 1, items[0].name == "data",
      let token = items[0].value, !token.isEmpty, token.count <= maximumPayloadLength
    else { throw ShareError.invalidLink }

    var base64 = token.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    guard let data = Data(base64Encoded: base64), data.count <= maximumPayloadLength,
      let payload = try? JSONDecoder().decode(Payload.self, from: data)
    else { throw ShareError.invalidPayload }
    guard payload.version == 1 else { throw ShareError.unsupportedVersion }
    guard valid(payload.theme) else { throw ShareError.invalidTheme }

    let background: Background?
    let skippedBackground: Bool
    if let candidate = payload.background {
      if let safeURL = secureImageURL(candidate.url), valid(candidate.filter) {
        background = .init(url: safeURL, fit: candidate.fit, filter: candidate.filter)
        skippedBackground = false
      } else {
        background = nil
        skippedBackground = true
      }
    } else {
      background = nil
      skippedBackground = false
    }
    return .init(
      theme: copy(payload.theme), remoteBackgroundURL: background?.url,
      backgroundFit: background?.fit, backgroundFilter: background?.filter,
      skippedBackground: skippedBackground)
  }

  private static func secureImageURL(_ rawValue: String) -> String? {
    guard let url = CustomBackgroundURLPolicy.normalizedRemoteURL(rawValue),
      url.isEmpty || URLComponents(string: url)?.scheme?.lowercased() == "https"
    else { return nil }
    return url
  }

  private static func valid(_ theme: CustomThemeDefinition) -> Bool {
    let name = theme.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard name == theme.name, (1...40).contains(name.count) else { return false }
    return [
      theme.background, theme.panel, theme.accent, theme.text, theme.secondaryText,
      theme.error, theme.extraInput, theme.caret, theme.fadedText,
      theme.colorfulError, theme.colorfulExtraInput
    ].allSatisfy { color in
      [color.red, color.green, color.blue, color.opacity].allSatisfy {
        $0.isFinite && (0...1).contains($0)
      }
    }
  }

  private static func valid(_ filter: CustomBackgroundFilter) -> Bool {
    [filter.blur, filter.brightness, filter.saturation, filter.opacity].allSatisfy(\.isFinite)
  }

  private static func copy(_ theme: CustomThemeDefinition) -> CustomThemeDefinition {
    .init(
      name: theme.name, background: theme.background, panel: theme.panel,
      accent: theme.accent, text: theme.text, secondaryText: theme.secondaryText,
      error: theme.error, extraInput: theme.extraInput, caret: theme.caret,
      fadedText: theme.fadedText, colorfulError: theme.colorfulError,
      colorfulExtraInput: theme.colorfulExtraInput, prefersDark: theme.prefersDark)
  }
}
