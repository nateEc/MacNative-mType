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
    guard value.count <= 2_048, !value.contains("`"), !value.contains("\""), !value.contains("'")
    else { return nil }
    guard let components = URLComponents(string: value),
      let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
      components.host?.isEmpty == false,
      let url = components.url
    else { return nil }
    guard supportedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
    return value
  }
}

@MainActor
final class TypebarLocalBackgroundStore {
  private static let filename = "local-practice-background"
  private let directoryURL: URL?
  private var memoryData: Data?

  init(directoryURL: URL) { self.directoryURL = directoryURL }
  private init() { directoryURL = nil }

  static func inMemory() -> TypebarLocalBackgroundStore { .init() }

  static func configured(
    info: [String: Any] = Bundle.main.infoDictionary ?? [:],
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> TypebarLocalBackgroundStore {
    if QAStoreMode.usesInMemoryStore(info: info) || environment["TYPEBAR_QA_IN_MEMORY_STORE"] == "1"
    {
      return .inMemory()
    }
    let directory = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Typebar", isDirectory: true)
    return .init(directoryURL: directory)
  }

  var isInMemory: Bool { directoryURL == nil }

  var hasImage: Bool {
    guard let fileURL else { return memoryData != nil }
    return FileManager.default.fileExists(atPath: fileURL.path)
  }

  func image() -> NSImage? {
    if let fileURL { return NSImage(contentsOf: fileURL) }
    return memoryData.flatMap(NSImage.init(data:))
  }

  func save(_ data: Data) throws {
    guard NSImage(data: data) != nil else { throw LocalBackgroundError.unsupportedImage }
    guard let directoryURL, let fileURL else {
      memoryData = data
      return
    }
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try data.write(to: fileURL, options: .atomic)
  }

  func remove() throws {
    guard let fileURL else {
      memoryData = nil
      return
    }
    guard hasImage else { return }
    // This filename owns one image, never an unexpected directory tree.
    let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
    guard values.isDirectory != true else { throw LocalBackgroundError.unexpectedDirectory }
    try FileManager.default.removeItem(at: fileURL)
  }

  private var fileURL: URL? {
    directoryURL?.appendingPathComponent(Self.filename, isDirectory: false)
  }
}

enum LocalBackgroundError: LocalizedError {
  case unsupportedImage
  case unexpectedDirectory

  var errorDescription: String? {
    switch self {
    case .unsupportedImage: "请选择 macOS 可以读取的图片文件。"
    case .unexpectedDirectory: "本地背景路径不是图片文件；已保留该目录，请检查后重试。"
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
  let localBackgroundStore: TypebarLocalBackgroundStore

  var body: some View {
    ZStack {
      PracticeBackdrop(style: fallbackStyle, theme: theme, reduceMotion: reduceMotion)
      if let localImage = localBackgroundStore.image() {
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
      applyFilters(
        image.resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity))
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
