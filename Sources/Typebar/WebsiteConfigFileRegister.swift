import Foundation
import CryptoKit
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
  static let archiveJournalFilename = ".website-archive-restore.v1"
  private static let maximumJournalBytes = 67_108_864
  static let maximumRecordBytes = 12_582_912
  private static let kind = "typebar.website-config-register"
  static let recordVersion = 2
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
    var lazyMemory = WebsiteConfigLazyModeMemory()
  }
  enum Commit: Equatable { case committed(Revision), conflict, unavailable }
  struct ArchivePreparation {
    fileprivate let expected: Revision
    fileprivate let beforeCustom: Data?
    fileprivate let target: Data
    fileprivate let afterCustom: Data?
    fileprivate let beforeFallback: Data?
    fileprivate let afterFallback: Data?
    var isUnchanged: Bool { expected.bytes == target && beforeCustom == afterCustom && beforeFallback == afterFallback }
  }
  enum ArchiveStage: CaseIterable { case journalWritten, customWritten, profileWritten }
  private struct ArchiveJournal: Codable {
    let kind: String
    let version: Int
    let beforeProfile: Data?
    let afterProfile: Data
    let beforeCustom: Data?
    let afterCustom: Data?
    let beforeFallback: Data?
    let afterFallback: Data?
  }
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

  func prepareArchiveRestore(_ archive: WebsiteProfileArchive,
    customStore: WebsiteCustomTextStateStore) throws -> ArchivePreparation {
    let current = try read()
    guard let revision = current.revision, current.state != .unavailable else { throw WebsiteProfileArchiveError.unavailable }
    let custom = try customStore.recordForArchive()
    let fallback = try customStore.fallbackRecordForArchive()
    let target: Data
    if case .available(let saved) = current.state, WebsiteProfileArchive.sameRuntime(saved, archive.runtime), current.lazyMemory == archive.lazyMemory,
      custom == archive.customTextData, let existing = revision.bytes { target = existing }
    else { target = try encodedRecord(runtime: archive.runtime, memory: archive.lazyMemory) }
    return .init(expected: revision, beforeCustom: custom, target: target, afterCustom: archive.customTextData,
      beforeFallback: fallback, afterFallback: archive.fallbackCustomTextData)
  }

  func validateArchiveRestore(_ plan: ArchivePreparation, customStore: WebsiteCustomTextStateStore) throws {
    let current = try read()
    guard current.revision == plan.expected, try customStore.recordForArchive() == plan.beforeCustom,
      try customStore.fallbackRecordForArchive() == plan.beforeFallback
    else { throw WebsiteProfileArchiveError.conflict }
  }

  @discardableResult
  func restoreArchive(_ plan: ArchivePreparation, customStore: WebsiteCustomTextStateStore,
    checkpoint: (ArchiveStage) throws -> Void = { _ in }) throws -> Revision {
    try locked { fd, identity in
      guard try archiveBytes(Self.archiveJournalFilename, maximum: Self.maximumJournalBytes, directoryFD: fd) == nil
      else { throw WebsiteProfileArchiveError.pendingRecovery }
      let current = try snapshot(fd, identity: identity)
      guard current.revision == plan.expected, try customStore.recordForArchive() == plan.beforeCustom,
        try customStore.fallbackRecordForArchive() == plan.beforeFallback
      else { throw WebsiteProfileArchiveError.conflict }
      let journal = ArchiveJournal(kind: "typebar.website-profile-restore", version: 1,
        beforeProfile: plan.expected.bytes, afterProfile: plan.target,
        beforeCustom: plan.beforeCustom, afterCustom: plan.afterCustom,
        beforeFallback: plan.beforeFallback, afterFallback: plan.afterFallback)
      let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
      let bytes = try encoder.encode(journal)
      guard bytes.count <= Self.maximumJournalBytes else { throw WebsiteProfileArchiveError.invalidPayload }
      try replace(bytes, directoryFD: fd, filename: Self.archiveJournalFilename)
      try checkpoint(.journalWritten)
      try finishArchiveRestore(journal, customStore: customStore, directoryFD: fd, checkpoint: checkpoint)
      return .init(directory: directory.path, identity: identity, bytes: plan.target)
    }
  }

  /// Recovery is explicit and idempotent. Unknown journals and foreign writes
  /// remain untouched; ordinary readers refuse the profile until this finishes.
  @discardableResult
  func recoverArchiveRestore(customStore: WebsiteCustomTextStateStore,
    expectedProfile: WebsiteProfileArchive? = nil,
    checkpoint: (ArchiveStage) throws -> Void = { _ in }) throws -> Bool {
    try locked { fd, _ in
      guard let bytes = try archiveBytes(Self.archiveJournalFilename, maximum: Self.maximumJournalBytes, directoryFD: fd)
      else { return false }
      let journal = try PropertyListDecoder().decode(ArchiveJournal.self, from: bytes)
      if let expectedProfile {
        guard let target = decode(journal.afterProfile), WebsiteProfileArchive.sameRuntime(target.runtime, expectedProfile.runtime),
          target.memory == expectedProfile.lazyMemory, journal.afterCustom == expectedProfile.customTextData,
          journal.afterFallback == expectedProfile.fallbackCustomTextData
        else { throw WebsiteProfileArchiveError.pendingRecovery }
      }
      try finishArchiveRestore(journal, customStore: customStore, directoryFD: fd, checkpoint: checkpoint)
      return true
    }
  }

  private func finishArchiveRestore(_ journal: ArchiveJournal, customStore: WebsiteCustomTextStateStore,
    directoryFD fd: Int32, checkpoint: (ArchiveStage) throws -> Void) throws {
    guard journal.kind == "typebar.website-profile-restore", journal.version == 1,
      journal.beforeProfile == nil || decode(journal.beforeProfile!) != nil,
      decode(journal.afterProfile) != nil,
      journal.beforeCustom == nil || WebsiteCustomTextStateStore.decodeDocument(journal.beforeCustom!) != nil,
      journal.afterCustom == nil || WebsiteCustomTextStateStore.decodeDocument(journal.afterCustom!) != nil,
      WebsiteCustomTextStateStore.acceptsFallbackArchiveDocument(journal.beforeFallback),
      WebsiteCustomTextStateStore.acceptsFallbackArchiveDocument(journal.afterFallback)
    else { throw WebsiteProfileArchiveError.invalidPayload }
    let current = try archiveBytes(Self.dataFilename, maximum: Self.maximumRecordBytes, directoryFD: fd)
    let barrier = Self.archiveBarrier(for: journal.afterProfile)
    guard current == journal.beforeProfile || current == journal.afterProfile || current == barrier
    else { throw WebsiteProfileArchiveError.conflict }
    let web = try customStore.recordForArchive(), fallback = try customStore.fallbackRecordForArchive()
    guard web == journal.beforeCustom || web == journal.afterCustom,
      fallback == journal.beforeFallback || fallback == journal.afterFallback else { throw WebsiteProfileArchiveError.conflict }
    // Older register readers do not know the separate journal. Put an unknown
    // envelope in the main record before any text changes, so after a crash
    // they cannot combine the old profile with restored independent text.
    var profileIsTarget = current == journal.afterProfile
    if !profileIsTarget || web != journal.afterCustom || fallback != journal.afterFallback {
      if current != barrier { try replace(barrier, directoryFD: fd) }
      profileIsTarget = false
    }
    guard customStore.restoreArchiveDocument(journal.afterCustom, replacing: journal.beforeCustom)
    else { throw WebsiteProfileArchiveError.conflict }
    guard customStore.restoreFallbackArchiveDocument(journal.afterFallback, replacing: journal.beforeFallback)
    else { throw WebsiteProfileArchiveError.conflict }
    try checkpoint(.customWritten)
    if !profileIsTarget { try replace(journal.afterProfile, directoryFD: fd) }
    try checkpoint(.profileWritten)
    guard Darwin.unlinkat(fd, Self.archiveJournalFilename, 0) == 0 else { throw WebsiteConfigFileRegisterError.io(errno) }
  }

  private static func archiveBarrier(for target: Data) -> Data {
    let digest = SHA256.hash(data: target).map { String(format: "%02x", $0) }.joined()
    return Data(WebsiteConfigJSONWriter.write(.array([.string("typebar.website-profile-restore-pending"),
      .number(1), .string(digest)])).utf8)
  }

  private func encodedRecord(runtime: [String: WebsiteConfigValue], memory: WebsiteConfigLazyModeMemory) throws -> Data {
    let payload = try WebsiteConfigNativeStateCodec.encode(runtime)
    let record = Data(WebsiteConfigJSONWriter.write(.array([.string(Self.kind), .number(Double(Self.recordVersion)),
      .string(UUID().uuidString), .string(payload.base64EncodedString()), memory.recordValue])).utf8)
    guard record.count <= Self.maximumRecordBytes else { throw WebsiteConfigNativeStateError.tooLarge }
    return record
  }

  private func archiveBytes(_ filename: String, maximum: Int, directoryFD: Int32) throws -> Data? {
    var info = stat()
    if Darwin.fstatat(directoryFD, filename, &info, AT_SYMLINK_NOFOLLOW) != 0 {
      if errno == ENOENT { return nil }
      throw WebsiteConfigFileRegisterError.io(errno)
    }
    guard regularPrivate(info), info.st_size >= 0, info.st_size <= maximum else { throw WebsiteProfileArchiveError.unavailable }
    let file = Darwin.openat(directoryFD, filename, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
    guard file >= 0 else { throw WebsiteConfigFileRegisterError.io(errno) }
    defer { Darwin.close(file) }
    var opened = stat()
    guard Darwin.fstat(file, &opened) == 0, regularPrivate(opened),
      info.st_dev == opened.st_dev, info.st_ino == opened.st_ino else { throw WebsiteProfileArchiveError.unavailable }
    var bytes = Data(), buffer = [UInt8](repeating: 0, count: 8192)
    while true {
      let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
      if count < 0 {
        if errno == EINTR { continue }
        throw WebsiteConfigFileRegisterError.io(errno)
      }
      if count == 0 { return bytes }
      guard count <= maximum - bytes.count else { throw WebsiteProfileArchiveError.unavailable }
      bytes.append(contentsOf: buffer.prefix(count))
    }
  }
  func commit(_ draft: WebsiteConfigNativeDraft, replacing expected: Revision,
    preservingUnchanged: Bool = false) throws -> Commit {
    try commit(runtime: draft.projection.runtime, lazyMemory: draft.lazyMemory,
      replacing: expected, preservingUnchanged: preservingUnchanged)
  }

  /// A source saving setter captures the complete admitted runtime at that
  /// point, before later nosave edits. Do not re-import it through setters or
  /// require resource/UI preflight merely to retain its valid raw values.
  func commit(runtime: [String: WebsiteConfigValue], lazyMemory: WebsiteConfigLazyModeMemory,
    replacing expected: Revision, preservingUnchanged: Bool = false) throws -> Commit {
    let payload = try WebsiteConfigNativeStateCodec.encode(runtime)
    let record = Data(WebsiteConfigJSONWriter.write(.array([.string(Self.kind), .number(Double(Self.recordVersion)),
      .string(UUID().uuidString), .string(payload.base64EncodedString()), lazyMemory.recordValue])).utf8)
    guard record.count <= Self.maximumRecordBytes else { throw WebsiteConfigNativeStateError.tooLarge }
    return try locked { fd, identity in
      let current = try snapshot(fd, identity: identity)
      guard let revision = current.revision else { return .unavailable }
      guard revision == expected else { return .conflict }
      // Native cold restoration can publish a new window/session without
      // rewriting identical settings and invalidating other live windows.
      // Still confirm the exact directory/record revision under the same lock.
      if preservingUnchanged, case .available(let runtime) = current.state,
        current.lazyMemory == lazyMemory,
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
    var pending = stat()
    if Darwin.fstatat(directoryFD, Self.archiveJournalFilename, &pending, AT_SYMLINK_NOFOLLOW) == 0 {
      return .init(state: .unavailable, revision: nil)
    }
    guard errno == ENOENT else { throw WebsiteConfigFileRegisterError.io(errno) }
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
    return .init(state: .available(state.runtime), revision: .init(directory: directory.path, identity: identity, bytes: bytes),
      lazyMemory: state.memory)
  }

  private func decode(_ record: Data) -> (runtime: [String: WebsiteConfigValue], memory: WebsiteConfigLazyModeMemory)? {
    guard let json = String(data: record, encoding: .utf8),
      let value = try? WebsiteConfigJSONReader.read(json, maximumBytes: Self.maximumRecordBytes),
      case .array(let parts) = value, parts.count >= 4, parts[0] == .string(Self.kind),
      case .string(let generation) = parts[2], UUID(uuidString: generation)?.uuidString == generation,
      case .string(let base64) = parts[3], let payload = Data(base64Encoded: base64),
      payload.base64EncodedString() == base64 else { return nil }
    let memory: WebsiteConfigLazyModeMemory
    if parts[1] == .number(1), parts.count == 4 { memory = .init() }
    else if parts[1] == .number(Double(Self.recordVersion)), parts.count == 5,
      let value = WebsiteConfigLazyModeMemory(recordValue: parts[4]) { memory = value }
    else { return nil }
    guard let runtime = try? WebsiteConfigNativeStateCodec.decode(payload) else { return nil }
    return (runtime, memory)
  }

  private func replace(_ record: Data, directoryFD: Int32, filename: String = Self.dataFilename) throws {
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
    guard Darwin.renameat(directoryFD, name, directoryFD, filename) == 0 else {
      throw WebsiteConfigFileRegisterError.io(errno)
    }
    moved = true
    // No fallible post-rename work: success means this one record was replaced,
    // not power-loss durability or that UI/resources committed with it.
  }
}
