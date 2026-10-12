import Foundation
import XCTest

final class ReadinessFailureRetentionTests: XCTestCase {
  func testLoggedFailureRetainsEvidenceAndRemovesOnlyItsTemporaryDirectory() throws {
    try check(logged: true)
  }

  func testUnloggedFailureRetainsEarlierEvidenceAndRemovesOnlyItsTemporaryDirectory() throws {
    try check(logged: false)
  }

  private func check(logged: Bool) throws {
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: project.appendingPathComponent("Scripts/check-native-rewrite-readiness.sh"),
      encoding: .utf8)
    func section(_ start: String, _ end: String) throws -> String {
      let lower = try XCTUnwrap(source.range(of: start)).lowerBound
      let upper = try XCTUnwrap(source.range(of: end, range: lower..<source.endIndex)).lowerBound
      return String(source[lower..<upper])
    }
    // Exercise the actual production functions without launching the full gate.
    let cleanup = try section("cleanup() {", "trap cleanup EXIT")
    let checks = try section("run_check() {", "run_check \"checking originality boundaries\"")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let temporary = root.appendingPathComponent("temporary")
    let retained = root.appendingPathComponent("retained")
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: retained, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("earlier-evidence\n".utf8).write(to: temporary.appendingPathComponent("earlier.log"))
    let invocation = logged
      ? "run_logged_check fixture \"$temporary_directory/failure.log\" /bin/zsh -c 'print expected-failure; exit 7'"
      : "run_check fixture /usr/bin/false"
    let script = """
    set -euo pipefail
    temporary_directory="$1"
    readiness_log_directory="$2"
    \(cleanup)
    trap cleanup EXIT
    \(checks)
    \(invocation)
    """
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", script, "--", temporary.path, retained.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    XCTAssertNotEqual(process.terminationStatus, 0)
    let evidence = retained.appendingPathComponent("earlier.log")
    XCTAssertTrue(FileManager.default.fileExists(atPath: evidence.path), "Prior evidence must survive failed checks")
    if FileManager.default.fileExists(atPath: evidence.path) {
      XCTAssertEqual(try String(contentsOf: evidence, encoding: .utf8), "earlier-evidence\n")
    }
    if logged {
      let failure = retained.appendingPathComponent("failure.log")
      XCTAssertTrue(FileManager.default.fileExists(atPath: failure.path))
      if FileManager.default.fileExists(atPath: failure.path) {
        XCTAssertEqual(try String(contentsOf: failure, encoding: .utf8), "expected-failure\n")
      }
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path))
  }
}
