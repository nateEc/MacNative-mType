import XCTest
import Darwin
import TypebarSystem
@testable import Typebar

final class WebsiteConfigFileRegisterTests: XCTestCase {
  private enum Failure: Error { case expectedCommit, timeout }
  @MainActor
  private func draft(_ time: Int = 30) throws -> WebsiteConfigNativeDraft {
    try WebsiteConfigNativeProfile.prepareDraft("{\"time\":\(time)}", pointsPerRem: 16, context: .init())
  }
  @MainActor
  private func committed(_ register: WebsiteConfigFileRegister, _ draft: WebsiteConfigNativeDraft,
    _ revision: WebsiteConfigFileRegister.Revision) throws -> WebsiteConfigFileRegister.Revision {
    guard case .committed(let next) = try register.commit(draft, replacing: revision) else {
      XCTFail("Expected conditional commit"); throw Failure.expectedCommit
    }
    return next
  }

  @MainActor
  private func withDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-config-register-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
  }

  @MainActor
  func testStaleRevisionNeverOverwritesTheCommittedConfiguration() throws {
    try withDirectory { directory in
      let a = WebsiteConfigFileRegister(directory: directory), b = WebsiteConfigFileRegister(directory: directory)
      let initial = try a.read()
      XCTAssertEqual(initial.state, .missing)
      let stale = try XCTUnwrap(initial.revision)
      let first = try WebsiteConfigNativeProfile.prepareDraft(#"{"time":41}"#, pointsPerRem: 16, context: .init())
      guard case .committed(let revision) = try a.commit(first, replacing: stale) else { return XCTFail("First commit rejected") }
      XCTAssertNotEqual(revision, stale)
      XCTAssertEqual(try b.read().state, .available(first.projection.runtime))
      let later = try WebsiteConfigNativeProfile.prepareDraft(#"{"time":42}"#, pointsPerRem: 16, context: .init())
      XCTAssertEqual(try b.commit(later, replacing: stale), .conflict)
      XCTAssertEqual(try a.read().state, .available(first.projection.runtime))
    }
  }

  @MainActor
  func testABASameValueAndForeignDirectoryTicketsAreRejected() throws {
    try withDirectory { directory in
      let register = WebsiteConfigFileRegister(directory: directory), a = try draft(31), b = try draft(32)
      let start = try XCTUnwrap(register.read().revision)
      let first = try committed(register, a, start)
      let middle = try committed(register, b, first)
      let again = try committed(register, a, middle)
      XCTAssertNotEqual(again, first)
      XCTAssertEqual(try register.read().state, .available(a.projection.runtime))
      XCTAssertEqual(try register.commit(b, replacing: first), .conflict)
      let same = try committed(register, a, again)
      XCTAssertNotEqual(same, again)
      XCTAssertEqual(try register.commit(b, replacing: again), .conflict)
      try withDirectory { other in
        let foreign = WebsiteConfigFileRegister(directory: other)
        XCTAssertEqual(try foreign.commit(b, replacing: same), .conflict)
        XCTAssertEqual(try foreign.read().state, .missing)
      }
    }
  }

  @MainActor
  func testMissingTicketIsBoundToDirectoryIdentityNotOnlyPath() throws {
    try withDirectory { directory in
      let register = WebsiteConfigFileRegister(directory: directory)
      let original = try XCTUnwrap(register.read().revision)
      let retired = directory.appendingPathExtension("retired")
      try FileManager.default.moveItem(at: directory, to: retired)
      defer { try? FileManager.default.removeItem(at: retired) }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      XCTAssertEqual(try register.commit(draft(), replacing: original), .conflict)
      XCTAssertEqual(try register.read().state, .missing)
    }
  }

  @MainActor
  func testOpaqueFutureAndLinkedRecordsStayUntouched() throws {
    try withDirectory { directory in
      let register = WebsiteConfigFileRegister(directory: directory), candidate = try draft()
      let initial = try XCTUnwrap(register.read().revision)
      let revision = try committed(register, candidate, initial)
      let file = directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
      let valid = try Data(contentsOf: file)
      guard case .array(let parts) = try WebsiteConfigJSONReader.read(String(decoding: valid, as: UTF8.self)) else { return XCTFail("Missing register frame") }
      var future = parts; future[1] = .number(Double(WebsiteConfigFileRegister.recordVersion + 1))
      var badPayload = parts; badPayload[3] = .string(Data("owned foreign format".utf8).base64EncodedString())
      let opaque = [Data(), Data("{".utf8), Data(WebsiteConfigJSONWriter.write(.array(future)).utf8),
        Data(WebsiteConfigJSONWriter.write(.array(badPayload)).utf8), Data(repeating: 32, count: WebsiteConfigFileRegister.maximumRecordBytes + 1)]
      for bytes in opaque {
        try bytes.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let read = try register.read()
        XCTAssertEqual(read.state, .unavailable); XCTAssertNil(read.revision)
        XCTAssertEqual(try register.commit(candidate, replacing: revision), .unavailable)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
      }
      try FileManager.default.removeItem(at: file)
      let foreign = directory.appendingPathComponent("owned-foreign")
      try valid.write(to: foreign)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: foreign.path)
      try FileManager.default.createSymbolicLink(at: file, withDestinationURL: foreign)
      XCTAssertEqual(try register.read().state, .unavailable)
      XCTAssertEqual(try register.commit(candidate, replacing: revision), .unavailable)
      XCTAssertEqual(try Data(contentsOf: foreign), valid)
      try FileManager.default.removeItem(at: file)
      try FileManager.default.linkItem(at: foreign, to: file)
      XCTAssertEqual(try register.read().state, .unavailable)
      XCTAssertEqual(try register.commit(candidate, replacing: revision), .unavailable)
      XCTAssertEqual(try Data(contentsOf: foreign), valid)
      try FileManager.default.removeItem(at: file)
      XCTAssertEqual(Darwin.mkfifo(file.path, mode_t(0o600)), 0)
      XCTAssertEqual(try register.read().state, .unavailable)
    }
  }

  @MainActor
  func testLockBusyAndRealPermissionFailurePreserveRecord() throws {
    try withDirectory { directory in
      let register = WebsiteConfigFileRegister(directory: directory)
      let initial = try XCTUnwrap(register.read().revision)
      let revision = try committed(register, draft(35), initial)
      let file = directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
      let before = try Data(contentsOf: file)
      let lock = Darwin.open(directory.appendingPathComponent(WebsiteConfigFileRegister.lockFilename).path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
      XCTAssertGreaterThanOrEqual(lock, 0)
      defer { Darwin.close(lock) }
      XCTAssertEqual(typebar_file_lock(lock, LOCK_EX | LOCK_NB), 0)
      XCTAssertThrowsError(try register.read()) { XCTAssertEqual($0 as? WebsiteConfigFileRegisterError, .busy) }
      XCTAssertThrowsError(try register.commit(draft(36), replacing: revision)) { XCTAssertEqual($0 as? WebsiteConfigFileRegisterError, .busy) }
      XCTAssertEqual(typebar_file_lock(lock, LOCK_UN), 0)
      XCTAssertEqual(try Data(contentsOf: file), before)
      guard geteuid() != 0 else { throw XCTSkip("Permission denial requires a non-root user") }
      try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
      defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
      XCTAssertThrowsError(try register.commit(draft(36), replacing: revision))
      XCTAssertEqual(try Data(contentsOf: file), before)
      XCTAssertEqual(try register.read().revision, revision)
      XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".tmp") }.isEmpty)
    }
  }

  @MainActor
  func testCommittedLosslessStateFeedsRestorationWithoutLegacyRewrite() throws {
    try withDirectory { directory in
      let register = WebsiteConfigFileRegister(directory: directory)
      let legacy = directory.appendingPathComponent("owned-legacy-data")
      let opaque = Data("Owned opaque legacy state".utf8)
      try opaque.write(to: legacy)
      let candidate = try WebsiteConfigNativeProfile.prepareDraft(#"{"customBackground":"https://example.com/\ud800.png","customBackgroundFilter":[-0,1e400,1,1],"autoSwitchTheme":true,"customTheme":true,"funbox":["rot13","rot13"],"quoteLength":[0,0,1]}"#,
        pointsPerRem: 16, context: .init())
      _ = try committed(register, candidate, XCTUnwrap(register.read().revision))
      let read = try register.read()
      XCTAssertEqual(read.state, .available(candidate.projection.runtime))
      guard case .prepared(let restored) = try WebsiteConfigNativeProfile.prepareNativeRestoration(read.state, context: .init()) else { return XCTFail("Missing restore") }
      let draft = try WebsiteConfigNativeDraft(restoration: restored, pointsPerRem: 16)
      XCTAssertNil(draft.prepared)
      XCTAssertEqual(draft.pagePreferences.backgroundAddress.stringUnits, candidate.pagePreferences.backgroundAddress.stringUnits)
      XCTAssertEqual(draft.pagePreferences.backgroundFilter.blurRem.sign, .minus)
      XCTAssertEqual(draft.pagePreferences.backgroundFilter.brightness, .infinity)
      XCTAssertEqual(draft.generators.requestedModifiers, [.rot13, .rot13])
      XCTAssertEqual(draft.quoteSelection.groups, [0, 0, 1])
      XCTAssertTrue(draft.themes.followsSystem); XCTAssertTrue(draft.themes.customEnabled)
      XCTAssertEqual(try Data(contentsOf: legacy), opaque)
    }
  }

  @MainActor
  func testUnsafeDirectoriesAndLockLinksAreRejected() throws {
    try withDirectory { directory in
      XCTAssertThrowsError(try WebsiteConfigFileRegister(directory: URL(string: "https://example.com/private")!).read())
      XCTAssertThrowsError(try WebsiteConfigFileRegister(directory: URL(string: "file://example.com\(directory.path)")!).read())
      let alias = directory.appendingPathComponent("alias")
      try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
      XCTAssertThrowsError(try WebsiteConfigFileRegister(directory: alias).read())
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
      defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
      XCTAssertThrowsError(try WebsiteConfigFileRegister(directory: directory).read())
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
      let register = WebsiteConfigFileRegister(directory: directory)
      _ = try register.read()
      let lock = directory.appendingPathComponent(WebsiteConfigFileRegister.lockFilename)
      let target = directory.appendingPathComponent("owned-lock-target")
      let bytes = Data("Owned lock target".utf8)
      try bytes.write(to: target)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
      // There are no active clients while the test installs unsafe entries.
      try FileManager.default.removeItem(at: lock)
      try FileManager.default.createSymbolicLink(at: lock, withDestinationURL: target)
      XCTAssertThrowsError(try register.read())
      XCTAssertEqual(try Data(contentsOf: target), bytes)
      try FileManager.default.removeItem(at: lock)
      try FileManager.default.linkItem(at: target, to: lock)
      XCTAssertThrowsError(try register.read())
      XCTAssertEqual(try Data(contentsOf: target), bytes)
    }
  }

  @MainActor
  func testTwoIndependentProcessesFromOneRevisionHaveOnlyOneWinner() throws {
    let env = ProcessInfo.processInfo.environment
    let directoryKey = "TYPEBAR_REGISTER_CHILD_DIRECTORY", idKey = "TYPEBAR_REGISTER_CHILD_ID"
    if let raw = env[directoryKey], let id = env[idKey] {
      let directory = URL(fileURLWithPath: raw, isDirectory: true)
      guard directory.lastPathComponent.hasPrefix("typebar-config-register-"), ["0", "1"].contains(id) else { return XCTFail("Not an isolated child") }
      let register = WebsiteConfigFileRegister(directory: directory)
      func eventually<T>(_ action: () throws -> T) throws -> T {
        let deadline = Date().addingTimeInterval(10)
        while true {
          do { return try action() }
          catch WebsiteConfigFileRegisterError.busy {
            guard Date() < deadline else { throw Failure.timeout }
            Thread.sleep(forTimeInterval: 0.005)
          }
        }
      }
      let revision = try XCTUnwrap(eventually { try register.read() }.revision)
      let candidate = try draft(id == "0" ? 41 : 42)
      try Data().write(to: directory.appendingPathComponent("qa-ready-\(id)"))
      let deadline = Date().addingTimeInterval(15)
      while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("qa-go").path) {
        guard Date() < deadline else { throw Failure.timeout }; Thread.sleep(forTimeInterval: 0.005)
      }
      let result = try eventually { try register.commit(candidate, replacing: revision) }
      let label: String
      switch result { case .committed: label = "committed"; case .conflict: label = "conflict"; case .unavailable: label = "unavailable" }
      try Data(label.utf8).write(to: directory.appendingPathComponent("qa-result-\(id)"))
      return
    }
    try withDirectory { directory in
      let register = WebsiteConfigFileRegister(directory: directory)
      _ = try committed(register, draft(), XCTUnwrap(register.read().revision))
      var children: [(Process, Pipe)] = []
      defer {
        for (process, _) in children where process.isRunning {
          process.terminate(); process.waitUntilExit()
        }
      }
      for id in ["0", "1"] {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xctest", "-XCTest", "TypebarTests.WebsiteConfigFileRegisterTests/testTwoIndependentProcessesFromOneRevisionHaveOnlyOneWinner", Bundle(for: Self.self).bundleURL.path]
        let allowed = ["PATH", "TMPDIR", "DEVELOPER_DIR", "SDKROOT", "DYLD_FRAMEWORK_PATH", "DYLD_LIBRARY_PATH"]
        process.environment = env.filter { allowed.contains($0.key) }
        process.environment?[directoryKey] = directory.path; process.environment?[idKey] = id
        process.environment?["TYPEBAR_QA_IN_MEMORY_STORE"] = "1"
        process.standardOutput = pipe; process.standardError = pipe
        try process.run(); children.append((process, pipe))
      }
      let readyDeadline = Date().addingTimeInterval(15)
      while !["0", "1"].allSatisfy({ FileManager.default.fileExists(atPath: directory.appendingPathComponent("qa-ready-\($0)").path) }) {
        guard Date() < readyDeadline else { throw Failure.timeout }; Thread.sleep(forTimeInterval: 0.005)
      }
      try Data().write(to: directory.appendingPathComponent("qa-go"))
      for (process, pipe) in children {
        let deadline = Date().addingTimeInterval(20)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.005) }
        if process.isRunning { process.terminate(); XCTFail("Register child timed out") }
        process.waitUntilExit()
        let diagnostics = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
          .split(separator: "\n").filter { $0.contains("error:") || $0.contains("failed") }.joined(separator: "\n")
        XCTAssertEqual(process.terminationStatus, 0, diagnostics)
      }
      let results = try ["0", "1"].map { try String(contentsOf: directory.appendingPathComponent("qa-result-\($0)"), encoding: .utf8) }
      XCTAssertEqual(results.sorted(), ["committed", "conflict"])
      guard case .available(let state) = try register.read().state else { return XCTFail("Committed state missing") }
      XCTAssertTrue([WebsiteConfigValue.number(41), .number(42)].contains(state["time"]!))
    }
  }
}
