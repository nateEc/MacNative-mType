import Foundation
import UniformTypeIdentifiers

enum BackgroundSelectedFileImport {
  static func accepts(mimeType: String) -> Bool {
    mimeType.range(of: "image/(jpeg|jpg|png|gif|webp)", options: .regularExpression) != nil
  }
  static func mimeType(for url: URL) -> String {
    UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? ""
  }
  @MainActor static func read(_ url: URL, for settings: AppSettings,
    load: (URL) throws -> Data = { try Data(contentsOf: $0) }) throws -> (data: Data, mimeType: String) {
    let mimeType = mimeType(for: url)
    let router = settings.preferenceConfigurationSaves
    if router.background != nil || router.backgroundSettingsState != nil {
      guard accepts(mimeType: mimeType) else { throw LocalBackgroundError.unsupportedMIMEType }
    }
    return (try load(url), mimeType)
  }
  @MainActor static func apply(_ data: Data, mimeType: String, to settings: AppSettings) -> Bool? {
    settings.preferenceConfigurationSaves.applyBackgroundEdit(.selectedFile(data, mimeType))
  }
}
