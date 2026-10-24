import Foundation
import Darwin
import TypebarSystem

enum WebsiteConfigFileRegisterError: Error, Equatable {
  case invalidDirectory, unsafeLock, busy, io(Int32)
}

/// Explicit, private local directory only. Coordinates this one record among
/// cooperating writers; not a settings/resource transaction or production cutover.
@MainActor
struct WebsiteConfigFileRegister {
  static let dataFilename = "website-config.native.v1"
  static let lockFilename = ".website-config.lock"
  static let maximumRecordBytes = 12_582_912
  private static let kind = "typebar.website-config-register"
  fileprivate struct Identity: Equatable {
    let device: Int32, inode: UInt64, bornSec: Int, bornNsec: Int
  }
  struct Revision: Equatable, CustomDebugStringConvertible {
    fileprivate let directory: String
    fileprivate let identity: Identity
    fileprivate let bytes: Data?
    var debugDescription: String { "WebsiteConfigFileRegister.Revision(redacted)" }
  }
  struct Snapshot {
    let state: WebsiteConfigNativeStateRead
    let revision: Revision?
  }
  enum Commit: Equatable { case committed(Revision), conflict, unavailable }
  private let directory: URL
  private let localFileLocation: Bool
  init(directory: URL) {
    let host = directory.host?.lowercased() ?? ""
    localFileLocation = directory.isFileURL && (host.isEmpty || host == "localhost")
    self.directory = directory.isFileURL ? directory.standardizedFileURL : directory
  }

  func read() throws -> Snapshot {
    try locked { fd, identity in try snapshot(fd, identity: identity) }
  }
  func commit(_ draft: WebsiteConfigNativeDraft, replacing expected: Revision,
    preservingUnchanged: Bool = false) throws -> Commit {
    let payload = try WebsiteConfigNativeStateCodec.encode(draft.projection.runtime)
    let record = Data(WebsiteConfigJSONWriter.write(.array([.string(Self.kind), .number(1),
      .string(UUID().uuidString), .string(payload.base64EncodedString())])).utf8)
    guard record.count <= Self.maximumRecordBytes else { throw WebsiteConfigNativeStateError.tooLarge }
    return try locked { fd, identity in
      let current = try snapshot(fd, identity: identity)
      guard let revision = current.revision else { return .unavailable }
      guard revision == expected else { return .conflict }
      // Native cold restoration can publish a new window/session without
      // rewriting identical settings and invalidating other live windows.
      // Still confirm the exact directory/record revision under the same lock.
      if preservingUnchanged, case .available(let runtime) = current.state,
        try WebsiteConfigNativeStateCodec.encode(runtime) == payload { return .committed(revision) }
      try replace(record, directoryFD: fd)
      return .committed(.init(directory: directory.path, identity: identity, bytes: record))
    }
  }

  private func locked<T>(_ body: (Int32, Identity) throws -> T) throws -> T {
    guard localFileLocation, directory.path.hasPrefix("/"), directory.path != "/",
      !directory.path.utf8.contains(0),
      try directory.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal == true else {
      throw WebsiteConfigFileRegisterError.invalidDirectory
    }
    let fd = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    guard fd >= 0 else { throw WebsiteConfigFileRegisterError.io(errno) }
    defer { Darwin.close(fd) }
    var info = stat()
    guard Darwin.fstat(fd, &info) == 0 else { throw WebsiteConfigFileRegisterError.io(errno) }
    guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), privateOwned(info) else {
      throw WebsiteConfigFileRegisterError.invalidDirectory
    }
    let lock = Darwin.openat(fd, Self.lockFilename, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, mode_t(0o600))
    guard lock >= 0 else { throw WebsiteConfigFileRegisterError.io(errno) }
    defer { Darwin.close(lock) }
    var lockInfo = stat()
    guard Darwin.fstat(lock, &lockInfo) == 0 else { throw WebsiteConfigFileRegisterError.io(errno) }
    guard regularPrivate(lockInfo) else { throw WebsiteConfigFileRegisterError.unsafeLock }
    guard typebar_file_lock(lock, LOCK_EX | LOCK_NB) == 0 else {
      let code = errno
      if code == EWOULDBLOCK { throw WebsiteConfigFileRegisterError.busy }
      throw WebsiteConfigFileRegisterError.io(code)
    }
    defer { _ = typebar_file_lock(lock, LOCK_UN) }
    // Never unlink/recreate the stable lock during normal operations. This
    // recheck also refuses a descriptor whose entry changed before acquisition.
    var entry = stat()
    guard Darwin.fstatat(fd, Self.lockFilename, &entry, AT_SYMLINK_NOFOLLOW) == 0,
      regularPrivate(entry), entry.st_dev == lockInfo.st_dev, entry.st_ino == lockInfo.st_ino else {
      throw WebsiteConfigFileRegisterError.unsafeLock
    }
    return try body(fd, .init(device: info.st_dev, inode: UInt64(info.st_ino),
      bornSec: Int(info.st_birthtimespec.tv_sec), bornNsec: Int(info.st_birthtimespec.tv_nsec)))
  }

  private func privateOwned(_ info: stat) -> Bool {
    info.st_uid == geteuid() && info.st_mode & 0o077 == 0
  }
  private func regularPrivate(_ info: stat) -> Bool {
    info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) && info.st_nlink == 1 && privateOwned(info)
      && info.st_mode & 0o600 == 0o600
  }

  private func snapshot(_ directoryFD: Int32, identity: Identity) throws -> Snapshot {
    var info = stat()
    if Darwin.fstatat(directoryFD, Self.dataFilename, &info, AT_SYMLINK_NOFOLLOW) != 0 {
      guard errno == ENOENT else { throw WebsiteConfigFileRegisterError.io(errno) }
      return .init(state: .missing, revision: .init(directory: directory.path, identity: identity, bytes: nil))
    }
    guard regularPrivate(info), info.st_size >= 0, info.st_size <= Self.maximumRecordBytes else {
      return .init(state: .unavailable, revision: nil)
    }
    let file = Darwin.openat(directoryFD, Self.dataFilename, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
    guard file >= 0 else { throw WebsiteConfigFileRegisterError.io(errno) }
    defer { Darwin.close(file) }
    var opened = stat()
    guard Darwin.fstat(file, &opened) == 0 else { throw WebsiteConfigFileRegisterError.io(errno) }
    guard regularPrivate(opened), info.st_dev == opened.st_dev, info.st_ino == opened.st_ino else {
      return .init(state: .unavailable, revision: nil)
    }
    var bytes = Data(), buffer = [UInt8](repeating: 0, count: 8192)
    while true {
      let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
      if count < 0 {
        if errno == EINTR { continue }
        throw WebsiteConfigFileRegisterError.io(errno)
      }
      if count == 0 { break }
      guard count <= Self.maximumRecordBytes - bytes.count else { return .init(state: .unavailable, revision: nil) }
      bytes.append(contentsOf: buffer.prefix(count))
    }
    guard let state = decode(bytes) else { return .init(state: .unavailable, revision: nil) }
    return .init(state: .available(state), revision: .init(directory: directory.path, identity: identity, bytes: bytes))
  }

  private func decode(_ record: Data) -> [String: WebsiteConfigValue]? {
    guard let json = String(data: record, encoding: .utf8),
      let value = try? WebsiteConfigJSONReader.read(json, maximumBytes: Self.maximumRecordBytes),
      case .array(let parts) = value, parts.count == 4, parts[0] == .string(Self.kind), parts[1] == .number(1),
      case .string(let generation) = parts[2], UUID(uuidString: generation)?.uuidString == generation,
      case .string(let base64) = parts[3], let payload = Data(base64Encoded: base64),
      payload.base64EncodedString() == base64 else { return nil }
    return try? WebsiteConfigNativeStateCodec.decode(payload)
  }

  private func replace(_ record: Data, directoryFD: Int32) throws {
    let name = ".website-config-\(UUID().uuidString).tmp"
    let file = Darwin.openat(directoryFD, name, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
    guard file >= 0 else { throw WebsiteConfigFileRegisterError.io(errno) }
    var moved = false
    defer {
      Darwin.close(file)
      if !moved { _ = Darwin.unlinkat(directoryFD, name, 0) }
    }
    try record.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        let count = Darwin.write(file, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
        if count < 0 {
          if errno == EINTR { continue }
          throw WebsiteConfigFileRegisterError.io(errno)
        }
        guard count > 0 else { throw WebsiteConfigFileRegisterError.io(EIO) }
        offset += count
      }
    }
    guard Darwin.fsync(file) == 0 else { throw WebsiteConfigFileRegisterError.io(errno) }
    guard Darwin.renameat(directoryFD, name, directoryFD, Self.dataFilename) == 0 else {
      throw WebsiteConfigFileRegisterError.io(errno)
    }
    moved = true
    // No fallible post-rename work: success means this one record was replaced,
    // not power-loss durability or that UI/resources committed with it.
  }
}
