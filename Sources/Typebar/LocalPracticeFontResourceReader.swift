import Darwin
import Foundation

enum LocalPracticeFontReadError: Error, Equatable {
  case invalidLimit, invalidSelection, unsupportedFile, resourceLimit, invalidFilename
}

/// Read-only bytes for new resource preparation, not legacy font activation.
@MainActor
final class LocalPracticeFontResourceReader {
  private let directoryURL: URL?
  private let defaults: UserDefaults?
  private let memoryData: Data?

  init(directoryURL: URL, defaults: UserDefaults) {
    self.directoryURL = directoryURL; self.defaults = defaults; memoryData = nil
  }
  private init(data: Data?) {
    directoryURL = nil; defaults = nil
    memoryData = data.map { $0.withUnsafeBytes { Data($0) } }
  }
  static func inMemory(data: Data? = nil) -> LocalPracticeFontResourceReader { .init(data: data) }
  static func configured(defaults: UserDefaults, info: [String: Any] = Bundle.main.infoDictionary ?? [:],
    environment: [String: String] = ProcessInfo.processInfo.environment) -> LocalPracticeFontResourceReader {
    if QAStoreMode.usesInMemoryStore(info: info) || environment["TYPEBAR_QA_IN_MEMORY_STORE"] == "1" { return .inMemory() }
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Typebar", isDirectory: true)
    return .init(directoryURL: directory, defaults: defaults)
  }
  var isInMemory: Bool { directoryURL == nil }
  func read(maximumBytes: Int = 32 * 1024 * 1024) throws -> WebsiteConfigFontResource.Local {
    guard maximumBytes > 0, maximumBytes < Int.max else { throw LocalPracticeFontReadError.invalidLimit }
    guard let directoryURL, let defaults else {
      guard let memoryData else { return .absent }
      guard memoryData.count <= maximumBytes else { throw LocalPracticeFontReadError.resourceLimit }
      return .data(memoryData.withUnsafeBytes { Data($0) })
    }
    if defaults.object(forKey: LocalPracticeFontPreferenceKeys.enabled) != nil,
      !defaults.bool(forKey: LocalPracticeFontPreferenceKeys.enabled) { return .absent }
    let selected: String?
    if let value = defaults.object(forKey: LocalPracticeFontPreferenceKeys.selected) {
      guard let name = value as? String else { throw LocalPracticeFontReadError.invalidSelection }
      if name.isEmpty { return .absent }
      guard LocalPracticeFontImport.isStoredFilename(name) else { throw LocalPracticeFontReadError.invalidSelection }
      selected = name
    } else { selected = nil }
    let host = directoryURL.host?.lowercased()
    guard directoryURL.isFileURL, host == nil || host == "" || host == "localhost",
      directoryURL.user == nil, directoryURL.password == nil, directoryURL.port == nil,
      directoryURL.query == nil, directoryURL.fragment == nil,
      directoryURL.path.hasPrefix("/"), !directoryURL.path.utf8.contains(0)
    else { throw LocalPracticeFontReadError.invalidSelection }
    let directory = Darwin.open(directoryURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
    guard directory >= 0 else {
      if errno == ENOENT, selected == nil { return .absent }
      throw posixError()
    }
    defer { Darwin.close(directory) }
    guard let name = try selected ?? legacyFilename(in: directory) else { return .absent }
    let before = try metadata(name, in: directory)
    try validateFile(before)
    guard before.st_size >= 0, before.st_size <= maximumBytes else { throw LocalPracticeFontReadError.resourceLimit }
    let descriptor = Darwin.openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
    guard descriptor >= 0 else { throw posixError() }
    let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? file.close() }
    var info = stat()
    guard fstat(descriptor, &info) == 0 else { throw posixError() }
    try validateFile(info)
    guard info.st_size >= 0, info.st_size <= maximumBytes else { throw LocalPracticeFontReadError.resourceLimit }
    var data = Data()
    while let chunk = try file.read(upToCount: min(64 * 1024, maximumBytes - data.count + 1)), !chunk.isEmpty {
      guard chunk.count <= maximumBytes - data.count else { throw LocalPracticeFontReadError.resourceLimit }
      data.append(chunk)
    }
    return .data(data)
  }

  private func legacyFilename(in directory: Int32) throws -> String? {
    // Open a separate stream from the same anchored directory. Do not enumerate
    // a path that may have been replaced since the directory descriptor opened.
    let scan = Darwin.openat(directory, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
    guard scan >= 0 else { throw posixError() }
    guard let stream = fdopendir(scan) else {
      let error = posixError(); Darwin.close(scan); throw error
    }
    defer { closedir(stream) }
    var selected: String?
    while true {
      errno = 0
      guard let entry = readdir(stream) else {
        if errno != 0 { throw posixError() }
        return selected
      }
      let count = Int(entry.pointee.d_namlen)
      let raw = withUnsafeBytes(of: entry.pointee.d_name) { Array($0.prefix(count)) }
      guard let name = try Self.storedFilename(fromUTF8: raw) else { continue }
      let info = try metadata(name, in: directory)
      guard info.st_flags & UInt32(UF_HIDDEN) == 0 else { continue }
      if selected == nil || name < selected! { selected = name }
    }
  }
  static func storedFilename(fromUTF8 bytes: [UInt8]) throws -> String? {
    guard let name = String(bytes: bytes, encoding: .utf8) else {
      if bytes.starts(with: LocalPracticeFontImport.storedFilenamePrefix.utf8) { throw LocalPracticeFontReadError.invalidFilename }
      return nil
    }
    return LocalPracticeFontImport.isStoredFilename(name) ? name : nil
  }
  private func metadata(_ name: String, in directory: Int32) throws -> stat {
    var info = stat()
    guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw posixError() }
    return info
  }
  private func validateFile(_ info: stat) throws {
    guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw LocalPracticeFontReadError.unsupportedFile }
    guard info.st_flags & UInt32(UF_HIDDEN) == 0 else { throw LocalPracticeFontReadError.invalidSelection }
  }
  private func posixError() -> NSError {
    NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
  }
}
