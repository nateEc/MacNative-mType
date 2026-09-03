import AppKit
import CoreText
import Foundation
import UniformTypeIdentifiers

struct LocalPracticeFontInfo: Equatable {
  let postScriptName: String
  let displayName: String
}

enum LocalPracticeFontFilePolicy {
  private static let supportedExtensions = Set(["otf", "ttf"])

  static let supportedContentTypes: [UTType] = [.font]

  static func supports(filename: String) -> Bool {
    supportedExtensions.contains(URL(fileURLWithPath: filename).pathExtension.lowercased())
  }
}

/// Stores one user-selected font file privately on this Mac. It is never part
/// of settings snapshots or account traffic.
enum TypebarLocalPracticeFontStore {
  private static let directoryName = "Typebar"
  private static let filenamePrefix = "local-practice-font"

  static var activeInfo: LocalPracticeFontInfo? {
    guard let url = storedFontURL else { return nil }
    return registerAndRead(url: url)
  }

  static func save(_ data: Data, originalFilename: String) throws -> LocalPracticeFontInfo {
    guard LocalPracticeFontFilePolicy.supports(filename: originalFilename) else {
      throw LocalPracticeFontError.unsupportedFormat
    }
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let fileExtension = URL(fileURLWithPath: originalFilename).pathExtension.lowercased()
    let candidateURL = directoryURL.appendingPathComponent(
      ".\(filenamePrefix)-candidate-\(UUID().uuidString).\(fileExtension)", isDirectory: false)
    try data.write(to: candidateURL, options: .atomic)
    defer { try? FileManager.default.removeItem(at: candidateURL) }

    guard fontInfo(at: candidateURL) != nil else { throw LocalPracticeFontError.invalidFont }

    let destinationURL = directoryURL.appendingPathComponent(
      "\(filenamePrefix)-active-\(UUID().uuidString).\(fileExtension)", isDirectory: false)
    try data.write(to: destinationURL, options: .atomic)

    let previousURLs = storedFontURLs
    previousURLs.forEach(unregister)
    guard let info = registerAndRead(url: destinationURL) else {
      previousURLs.forEach { _ = registerAndRead(url: $0) }
      try? FileManager.default.removeItem(at: destinationURL)
      throw LocalPracticeFontError.couldNotLoad
    }
    removeOtherStoredFonts(except: destinationURL)
    return info
  }

  static func remove() throws {
    for url in storedFontURLs {
      unregister(url)
      try FileManager.default.removeItem(at: url)
    }
  }

  private static var storedFontURL: URL? {
    storedFontURLs.first
  }

  private static var storedFontURLs: [URL] {
    (try? FileManager.default.contentsOfDirectory(
      at: directoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))?
      .filter {
        $0.lastPathComponent.hasPrefix("\(filenamePrefix)-active-")
          && LocalPracticeFontFilePolicy.supports(filename: $0.lastPathComponent)
      }
      .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
  }

  private static func removeOtherStoredFonts(except retainedURL: URL) {
    for url in storedFontURLs where url != retainedURL {
      try? FileManager.default.removeItem(at: url)
    }
  }

  private static func registerAndRead(url: URL) -> LocalPracticeFontInfo? {
    var registrationError: Unmanaged<CFError>?
    _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError)
    guard let info = fontInfo(at: url), NSFont(name: info.postScriptName, size: 1) != nil else {
      return nil
    }
    return info
  }

  private static func unregister(_ url: URL) {
    var registrationError: Unmanaged<CFError>?
    _ = CTFontManagerUnregisterFontsForURL(url as CFURL, .process, &registrationError)
  }

  private static func fontInfo(at url: URL) -> LocalPracticeFontInfo? {
    guard
      let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
      let descriptor = descriptors.first,
      let postScriptName = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
    else { return nil }
    let displayName =
      (CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute) as? String) ?? postScriptName
    return .init(postScriptName: postScriptName, displayName: displayName)
  }

  private static var directoryURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(directoryName, isDirectory: true)
  }
}

enum LocalPracticeFontError: LocalizedError {
  case unsupportedFormat
  case invalidFont
  case couldNotLoad

  var errorDescription: String? {
    switch self {
    case .unsupportedFormat:
      "请选择 TTF 或 OTF 字体文件。"
    case .invalidFont:
      "所选文件不是 macOS 可以读取的字体。"
    case .couldNotLoad:
      "字体文件已保存，但当前 macOS 无法加载它。"
    }
  }
}
