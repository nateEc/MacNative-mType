import Darwin
import Foundation

/// Created only for an explicit configuration operation, never by rendering.
/// Existing directories are checked, not repaired or chmoded.
@MainActor enum WebsiteConfigStorageDirectory {
  /// Discovery does not create a directory, lock, default record or repair.
  static func existing(applicationSupport: URL? = nil) throws -> URL? {
    if applicationSupport == nil,
      QAStoreMode.usesInMemoryStore(info: Bundle.main.infoDictionary ?? [:])
        || ProcessInfo.processInfo.environment["TYPEBAR_QA_IN_MEMORY_STORE"] == "1" { return nil }
    let support = applicationSupport ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    guard support.isFileURL, support.path.hasPrefix("/"), support.path != "/", !support.path.utf8.contains(0),
      support.query == nil, support.fragment == nil,
      support.host == nil || support.host == "" || support.host == "localhost" else {
      throw WebsiteConfigFileRegisterError.invalidDirectory
    }
    let parent = support.appendingPathComponent("Typebar", isDirectory: true)
    let directory = parent.appendingPathComponent("WebsiteConfiguration", isDirectory: true)
    for (url, isPrivate) in [(parent, false), (directory, true)] {
      var info = stat()
      if Darwin.lstat(url.path, &info) != 0 {
        if errno == ENOENT { return nil }
        throw WebsiteConfigFileRegisterError.io(errno)
      }
      guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), info.st_uid == geteuid(),
        !isPrivate || info.st_mode & 0o077 == 0 else { throw WebsiteConfigFileRegisterError.invalidDirectory }
    }
    guard try directory.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal == true else {
      throw WebsiteConfigFileRegisterError.invalidDirectory
    }
    var dataInfo = stat()
    if Darwin.lstat(directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename).path, &dataInfo) != 0 {
      if errno == ENOENT {
        var journal = stat()
        if Darwin.lstat(directory.appendingPathComponent(WebsiteConfigFileRegister.archiveJournalFilename).path, &journal) == 0 {
          return directory
        }
        if errno == ENOENT { return nil }
      }
      throw WebsiteConfigFileRegisterError.io(errno)
    }
    // Unknown/special data entries are deliberately returned for explicit
    // record admission failure, never treated as permission to use defaults.
    return directory
  }

  static func prepare(applicationSupport: URL? = nil) throws -> URL {
    if applicationSupport == nil,
      QAStoreMode.usesInMemoryStore(info: Bundle.main.infoDictionary ?? [:])
        || ProcessInfo.processInfo.environment["TYPEBAR_QA_IN_MEMORY_STORE"] == "1" {
      throw WebsiteConfigImportWorkflowError.unavailable
    }
    let support = applicationSupport ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    guard support.isFileURL, support.path.hasPrefix("/"), support.path != "/", !support.path.utf8.contains(0),
      support.query == nil, support.fragment == nil,
      support.host == nil || support.host == "" || support.host == "localhost",
      try support.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal == true else {
      throw WebsiteConfigFileRegisterError.invalidDirectory
    }
    let parent = support.appendingPathComponent("Typebar", isDirectory: true)
    let directory = parent.appendingPathComponent("WebsiteConfiguration", isDirectory: true)
    try ensure(parent, privateDirectory: false)
    try ensure(directory, privateDirectory: true)
    // Reuse the record authority's local/owned/no-follow checks as well.
    _ = try WebsiteConfigFileRegister(directory: directory).read()
    return directory
  }
  private static func ensure(_ url: URL, privateDirectory: Bool) throws {
    if Darwin.mkdir(url.path, 0o700) != 0, errno != EEXIST {
      throw WebsiteConfigFileRegisterError.io(errno)
    }
    var info = stat()
    guard Darwin.lstat(url.path, &info) == 0,
      info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), info.st_uid == geteuid(),
      !privateDirectory || info.st_mode & 0o077 == 0 else {
      throw WebsiteConfigFileRegisterError.invalidDirectory
    }
  }
}
