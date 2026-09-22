import Foundation

/// Decodes a legacy serialized custom-theme payload without resolving the
/// pasted URL or importing web assets. Its host is transport metadata only;
/// the caller decides whether to persist the returned native theme.
enum LegacyCustomThemeLinkImporter {
  struct ImportedTheme: Equatable {
    let theme: CustomThemeDefinition
    let remoteBackgroundURL: String?
    let backgroundFit: CustomBackgroundFit?
    let backgroundFilter: CustomBackgroundFilter?
    let skippedBackground: Bool
  }

  enum ImportError: Error, Equatable, LocalizedError {
    case invalidLink
    case invalidPayload
    case invalidThemeName

    var errorDescription: String? {
      switch self {
      case .invalidLink: "这不是有效的网页自定义主题链接。"
      case .invalidPayload: "主题链接中的颜色或背景设置无效。"
      case .invalidThemeName: "导入的主题名称需为 1–40 个字符。"
      }
    }
  }

  private static let maximumLinkLength = 32_768
  private static let maximumPayloadLength = 16_384
  static func theme(from rawLink: String, name: String) throws -> ImportedTheme {
    let link = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !link.isEmpty, link.count <= maximumLinkLength,
      let components = URLComponents(string: link),
      components.scheme?.lowercased() == "https",
      components.user == nil, components.password == nil,
      components.port == nil || components.port == 443,
      components.host?.isEmpty == false
    else { throw ImportError.invalidLink }

    let values = (components.queryItems ?? []).filter { $0.name == "customTheme" }
    guard values.count == 1, let encodedPayload = values[0].value,
      !encodedPayload.isEmpty, encodedPayload.count <= maximumPayloadLength
    else { throw ImportError.invalidPayload }

    var base64 = encodedPayload
      .replacingOccurrences(of: " ", with: "+")
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    guard let data = Data(base64Encoded: base64), data.count <= maximumPayloadLength else {
      throw ImportError.invalidPayload
    }

    let payload: Payload
    do {
      payload = try JSONDecoder().decode(Payload.self, from: data)
    } catch {
      throw ImportError.invalidPayload
    }

    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...40).contains(trimmedName.count), payload.colors.count == 10 else {
      throw trimmedName.isEmpty || trimmedName.count > 40
        ? ImportError.invalidThemeName
        : ImportError.invalidPayload
    }
    let colors = try payload.colors.map(color(from:))
    let isDark = relativeLuminance(of: colors[0]) < 0.5
    let theme = CustomThemeDefinition(
      name: trimmedName,
      background: colors[0], panel: colors[4], accent: colors[1], text: colors[5],
      secondaryText: colors[3], error: colors[6], extraInput: colors[7], caret: colors[2],
      fadedText: colors[4], colorfulError: colors[8], colorfulExtraInput: colors[9],
      prefersDark: isDark)

    guard let rawBackgroundURL = payload.backgroundURL,
      let remoteBackgroundURL = CustomBackgroundURLPolicy.normalizedRemoteURL(rawBackgroundURL),
      !remoteBackgroundURL.isEmpty,
      let backgroundFit = payload.backgroundFit.flatMap(CustomBackgroundFit.init(rawValue:)),
      let backgroundFilter = validBackgroundFilter(payload.backgroundFilter)
    else {
      return .init(
        theme: theme, remoteBackgroundURL: nil, backgroundFit: nil,
        backgroundFilter: nil, skippedBackground: payload.backgroundURL != nil)
    }

    return .init(
      theme: theme, remoteBackgroundURL: remoteBackgroundURL, backgroundFit: backgroundFit,
      backgroundFilter: backgroundFilter, skippedBackground: false)
  }

  private struct Payload: Decodable {
    let colors: [String]
    let backgroundURL: String?
    let backgroundFit: String?
    let backgroundFilter: [Double]?

    private enum CodingKeys: String, CodingKey {
      case colors = "c"
      case backgroundURL = "i"
      case backgroundFit = "s"
      case backgroundFilter = "f"
    }

    init(from decoder: Decoder) throws {
      if let container = try? decoder.container(keyedBy: CodingKeys.self) {
        colors = try container.decode([String].self, forKey: .colors)
        backgroundURL = try container.decodeIfPresent(String.self, forKey: .backgroundURL)
        backgroundFit = try container.decodeIfPresent(String.self, forKey: .backgroundFit)
        backgroundFilter = try container.decodeIfPresent([Double].self, forKey: .backgroundFilter)
      } else {
        let container = try decoder.singleValueContainer()
        colors = try container.decode([String].self)
        backgroundURL = nil
        backgroundFit = nil
        backgroundFilter = nil
      }
    }
  }

  private static func color(from value: String) throws -> ThemeColor {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.first == "#" else { throw ImportError.invalidPayload }
    let hex = String(normalized.dropFirst())
    let expanded: String
    switch hex.count {
    case 3:
      expanded = hex.map { "\($0)\($0)" }.joined()
    case 6:
      expanded = hex
    default:
      throw ImportError.invalidPayload
    }
    guard let red = UInt8(expanded.prefix(2), radix: 16),
      let green = UInt8(expanded.dropFirst(2).prefix(2), radix: 16),
      let blue = UInt8(expanded.suffix(2), radix: 16)
    else { throw ImportError.invalidPayload }
    return .init(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
  }

  private static func validBackgroundFilter(_ values: [Double]?) -> CustomBackgroundFilter? {
    guard let values, values.count == 4, values.allSatisfy(\.isFinite) else { return nil }
    return .init(blur: values[0], brightness: values[1], saturation: values[2], opacity: values[3])
  }

  private static func relativeLuminance(of color: ThemeColor) -> Double {
    func linearized(_ component: Double) -> Double {
      component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linearized(color.red)
      + 0.7152 * linearized(color.green)
      + 0.0722 * linearized(color.blue)
  }
}
