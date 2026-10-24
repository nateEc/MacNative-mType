import Darwin
import Foundation

/// Created only for an explicit configuration operation, never by rendering.
/// Existing directories are checked, not repaired or chmoded.
@MainActor enum WebsiteConfigStorageDirectory {
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
