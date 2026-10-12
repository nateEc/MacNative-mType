import AppKit
import CoreText
import Foundation
import UniformTypeIdentifiers

struct LocalPracticeFontInfo: Equatable {
  let postScriptName: String
  let displayName: String
}

enum LocalPracticeFontFilePolicy {
  private static let supportedExtensions = Set(["otf", "ttf", "woff", "woff2"])

  static let supportedContentTypes: [UTType] = [
    .font,
    UTType(filenameExtension: "woff", conformingTo: .data),
    UTType(filenameExtension: "woff2", conformingTo: .data),
  ].compactMap { $0 }

  static func supports(filename: String) -> Bool {
    supportedExtensions.contains(URL(fileURLWithPath: filename).pathExtension.lowercased())
  }
}

/// Stores one user-selected font file privately on this Mac. It is never part
/// of settings snapshots or account traffic.
enum TypebarLocalPracticeFontStore {
  private static let directoryName = "Typebar"
  private static let enabledDefaultsKey = "typebar.local-practice-font-enabled"

  static var hasStoredFont: Bool { storedFontURL != nil }

  static var isActive: Bool { hasStoredFont && isEnabled }

  static var activeInfo: LocalPracticeFontInfo? {
    guard isActive, let url = storedFontURL else { return nil }
    return registerAndRead(url: url)
  }

  static func activeFont(size: CGFloat) -> NSFont? {
    guard isActive, let url = storedFontURL, registerAndRead(url: url) != nil else { return nil }
    return LocalPracticeFontRegistration.font(at: url, size: size)
  }

  static func save(_ data: Data, originalFilename: String) throws -> LocalPracticeFontInfo {
    try LocalPracticeFontImport.save(data, originalFilename: originalFilename,
      directory: directoryURL, readInfo: fontInfo(at:), register: registerAndRead(url:),
      unregister: unregister, enable: { setEnabled(true) })
  }

  /// Re-enables a font file that was deliberately retained after switching
  /// back to a system or named font.
  @discardableResult
  static func activate() -> Bool {
    guard let url = storedFontURL, registerAndRead(url: url) != nil else { return false }
    setEnabled(true)
    return true
  }

  /// Keeps the local file private and intact while allowing an explicit font
  /// choice to take effect.
  static func deactivate() {
    guard hasStoredFont else { return }
    setEnabled(false)
  }

  static func remove() throws {
    for url in storedFontURLs {
      unregister(url)
      try FileManager.default.removeItem(at: url)
    }
    UserDefaults.standard.removeObject(forKey: enabledDefaultsKey)
  }

  private static var storedFontURL: URL? { storedFontURLs.first }

  private static var storedFontURLs: [URL] {
    LocalPracticeFontImport.storedURLs(in: directoryURL)
  }

  private static var isEnabled: Bool {
    if UserDefaults.standard.object(forKey: enabledDefaultsKey) == nil { return true }
    return UserDefaults.standard.bool(forKey: enabledDefaultsKey)
  }

  private static func setEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: enabledDefaultsKey)
  }

  private static func registerAndRead(url: URL) -> LocalPracticeFontInfo? {
    LocalPracticeFontRegistration.read(url: url)
  }

  private static func unregister(_ url: URL) {
    var registrationError: Unmanaged<CFError>?
    _ = CTFontManagerUnregisterFontsForURL(url as CFURL, .process, &registrationError)
  }

  private static func fontInfo(at url: URL) -> LocalPracticeFontInfo? {
    LocalPracticeFontRegistration.fontInfo(at: url)
  }

  private static var directoryURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(directoryName, isDirectory: true)
  }
}

enum LocalPracticeFontRegistration {
  static func font(at url: URL, size: CGFloat) -> NSFont? {
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
      let descriptor = descriptors.first else { return nil }
    let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
    guard let source = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL,
      source.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() else { return nil }
    return font as NSFont
  }

  static func read(url: URL) -> LocalPracticeFontInfo? {
    read(url: url, register: { CTFontManagerRegisterFontsForURL($0 as CFURL, .process, nil) },
      isRegistered: { CTFontManagerGetScopeForURL($0 as CFURL) == .process },
      readInfo: fontInfo(at:), isAvailable: { NSFont(name: $0, size: 1) != nil },
      isSelectedSource: { name, url in
        let font = CTFontCreateWithName(name as CFString, 1, nil)
        guard let selectedURL = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL else { return false }
        return selectedURL.resolvingSymlinksInPath() == url.resolvingSymlinksInPath()
      })
  }

  static func fontInfo(at url: URL) -> LocalPracticeFontInfo? {
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
      let descriptor = descriptors.first,
      let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
    else { return nil }
    return .init(postScriptName: name,
      displayName: (CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute) as? String) ?? name)
  }

  static func read(url: URL, register: (URL) -> Bool, isRegistered: (URL) -> Bool,
    readInfo: (URL) -> LocalPracticeFontInfo?, isAvailable: (String) -> Bool,
    isSelectedSource: (String, URL) -> Bool) -> LocalPracticeFontInfo? {
    // CTFontManager.h defines success by the registration result and exposes
    // URL-specific scope for idempotent reads. Name lookup alone is insufficient.
    guard register(url) || isRegistered(url) else { return nil }
    guard let info = readInfo(url), isAvailable(info.postScriptName),
      isSelectedSource(info.postScriptName, url) else { return nil }
    return info
  }
}

/// File transaction with explicit native boundaries for isolated recovery tests.
enum LocalPracticeFontImport {
  private static let filenamePrefix = "local-practice-font"

  static func save(_ data: Data, originalFilename: String, directory: URL,
    readInfo: (URL) -> LocalPracticeFontInfo?, register: (URL) -> LocalPracticeFontInfo?,
    unregister: (URL) -> Void, enable: () -> Void) throws -> LocalPracticeFontInfo {
    guard LocalPracticeFontFilePolicy.supports(filename: originalFilename) else {
      throw LocalPracticeFontError.unsupportedFormat
    }
    let directory = directory.resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let fileExtension = URL(fileURLWithPath: originalFilename).pathExtension.lowercased()
    let candidateURL = directory.appendingPathComponent(
      ".\(filenamePrefix)-candidate-\(UUID().uuidString).\(fileExtension)", isDirectory: false)
    try data.write(to: candidateURL, options: .atomic)
    defer { try? FileManager.default.removeItem(at: candidateURL) }

    guard readInfo(candidateURL) != nil else { throw LocalPracticeFontError.invalidFont }

    // Snapshot before publishing the new file. Only this prior generation may
    // be unregistered, restored on failure, or removed after success. Do not
    // rediscover files and compare URL spellings across symlink aliases.
    let previousURLs = storedURLs(in: directory)
    let destinationURL = directory.appendingPathComponent(
      "\(filenamePrefix)-active-\(UUID().uuidString).\(fileExtension)", isDirectory: false)
    try data.write(to: destinationURL, options: .atomic)

    previousURLs.forEach(unregister)
    guard let info = register(destinationURL) else {
      // Registration may succeed before descriptor/availability checks fail.
      // Retire this owned generation while its file still exists, before
      // restoring the previous fonts (which may share its PostScript name).
      unregister(destinationURL)
      previousURLs.forEach { _ = register($0) }
      try? FileManager.default.removeItem(at: destinationURL)
      throw LocalPracticeFontError.couldNotLoad
    }
    for url in previousURLs {
      try? FileManager.default.removeItem(at: url)
    }
    enable()
    return info
  }

  static func storedURLs(in directory: URL) -> [URL] {
    (try? FileManager.default.contentsOfDirectory(
      at: directory.resolvingSymlinksInPath(), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))?
      .filter {
        $0.lastPathComponent.hasPrefix("\(filenamePrefix)-active-")
          && LocalPracticeFontFilePolicy.supports(filename: $0.lastPathComponent)
      }
      .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
  }
}

enum LocalPracticeFontError: LocalizedError {
  case unsupportedFormat
  case invalidFont
  case couldNotLoad

  var errorDescription: String? {
    switch self {
    case .unsupportedFormat:
      "请选择 TTF、OTF、WOFF 或 WOFF2 字体文件。"
    case .invalidFont:
      "所选文件不是 macOS 可以读取的字体。"
    case .couldNotLoad:
      "字体文件已保存，但当前 macOS 无法加载它。"
    }
  }
}
