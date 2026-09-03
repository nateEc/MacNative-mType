import AppKit
import Foundation
import SwiftUI

enum CustomBackgroundFit: String, CaseIterable, Codable, Equatable, Identifiable {
  case cover
  case contain
  case max

  var id: Self { self }

  var displayName: String {
    switch self {
    case .cover: "覆盖"
    case .contain: "完整显示"
    case .max: "填满"
    }
  }
}

struct CustomBackgroundFilter: Codable, Equatable {
  var blur: Double
  var brightness: Double
  var saturation: Double
  var opacity: Double

  init(blur: Double = 0, brightness: Double = 1, saturation: Double = 1, opacity: Double = 1) {
    self.blur = blur.clamped(to: 0...50)
    self.brightness = brightness.clamped(to: 0...2)
    self.saturation = saturation.clamped(to: 0...3)
    self.opacity = opacity.clamped(to: 0...1)
  }

  var normalized: Self {
    .init(blur: blur, brightness: brightness, saturation: saturation, opacity: opacity)
  }
}

enum CustomBackgroundURLPolicy {
  private static let supportedExtensions = Set(["png", "gif", "jpeg", "jpg", "webp"])

  /// Returns a safe, normalized remote image URL, an empty value for removal,
  /// or nil when the value is not an HTTP(S) image URL.
  static func normalizedRemoteURL(_ rawValue: String) -> String? {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return "" }
    guard value.count <= 2_048, !value.contains("`"), !value.contains("\""), !value.contains("'") else { return nil }
    guard let components = URLComponents(string: value),
      let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
      components.host?.isEmpty == false,
      let url = components.url
    else { return nil }
    guard supportedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
    return value
  }
}

enum TypebarLocalBackgroundStore {
  private static let directoryName = "Typebar"
  private static let filename = "local-practice-background"

  static var hasImage: Bool {
    FileManager.default.fileExists(atPath: fileURL.path)
  }

  static func image() -> NSImage? {
    NSImage(contentsOf: fileURL)
  }

  static func save(_ data: Data) throws {
    guard NSImage(data: data) != nil else { throw LocalBackgroundError.unsupportedImage }
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try data.write(to: fileURL, options: .atomic)
  }

  static func remove() throws {
    guard hasImage else { return }
    try FileManager.default.removeItem(at: fileURL)
  }

  private static var directoryURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(directoryName, isDirectory: true)
  }

  private static var fileURL: URL {
    directoryURL.appendingPathComponent(filename, isDirectory: false)
  }
}

enum LocalBackgroundError: LocalizedError {
  case unsupportedImage

  var errorDescription: String? {
    switch self {
    case .unsupportedImage: "请选择 macOS 可以读取的图片文件。"
    }
  }
}

struct CustomPracticeBackground: View {
  let fallbackStyle: PracticeBackdropStyle
  let theme: ResolvedTheme
  let reduceMotion: Bool
  let remoteURL: String
  let fit: CustomBackgroundFit
  let filter: CustomBackgroundFilter
  let localImageRevision: Int

  var body: some View {
    ZStack {
      PracticeBackdrop(style: fallbackStyle, theme: theme, reduceMotion: reduceMotion)
      if let localImage = TypebarLocalBackgroundStore.image() {
        filtered(Image(nsImage: localImage))
      } else if let url = URL(string: remoteURL), !remoteURL.isEmpty {
        AsyncImage(url: url) { phase in
          if case .success(let image) = phase { filtered(image) }
        }
      }
    }
    // Read the revision so a newly imported or removed local image invalidates
    // this view without serializing the user's image into settings archives.
    .id(localImageRevision)
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  @ViewBuilder private func filtered(_ image: Image) -> some View {
    switch fit {
    case .cover:
      applyFilters(image.resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity))
    case .contain:
      applyFilters(image.resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity))
    case .max:
      applyFilters(image.resizable().frame(maxWidth: .infinity, maxHeight: .infinity))
    }
  }

  private func applyFilters<Content: View>(_ content: Content) -> some View {
    content
      .blur(radius: filter.blur)
      .brightness(filter.brightness - 1)
      .saturation(filter.saturation)
      .opacity(filter.opacity)
      .scaleEffect(1 + filter.blur / 100)
      .clipped()
  }
}
