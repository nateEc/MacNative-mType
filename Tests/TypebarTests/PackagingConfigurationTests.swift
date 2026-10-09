import Foundation
import XCTest

final class PackagingConfigurationTests: XCTestCase {
  func testBuildAndBinaryLookupUseTheSameValidatedConfiguration() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    for requested in [nil, "debug", "release", "invalid"] as [String?] {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let log = directory.appendingPathComponent("calls"), app = directory.appendingPathComponent("QA.app")
      try Data("fixture".utf8).write(to: directory.appendingPathComponent("Typebar"))
      let swift = directory.appendingPathComponent("swift")
      try """
      #!/bin/zsh
      print -r -- "$*" >> "$TYPEBAR_TEST_CALLS"
      if [[ "$*" == *--show-bin-path* ]]; then print -r -- "$TYPEBAR_TEST_BINARY_DIR"; fi
      """.write(to: swift, atomically: true, encoding: .utf8)
      let codesign = directory.appendingPathComponent("codesign")
      try "#!/bin/zsh\nexit 0\n".write(to: codesign, atomically: true, encoding: .utf8)
      for executable in [swift, codesign] {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
      }
      let process = Process(), output = Pipe()
      process.executableURL = URL(fileURLWithPath: "/bin/zsh")
      process.arguments = [root.appendingPathComponent("Scripts/package-macos-app.sh").path]
      var environment = ProcessInfo.processInfo.environment
      environment["PATH"] = directory.path + ":/usr/bin:/bin:/usr/sbin:/sbin"
      environment["TYPEBAR_APP_PATH"] = app.path
      environment["TYPEBAR_TEST_CALLS"] = log.path
      environment["TYPEBAR_TEST_BINARY_DIR"] = directory.path
      environment["TYPEBAR_QA_IN_MEMORY_STORE"] = "0"
      environment.removeValue(forKey: "TYPEBAR_BUNDLE_IDENTIFIER")
      environment.removeValue(forKey: "TYPEBAR_APP_NAME")
      environment.removeValue(forKey: "TYPEBAR_BUILD_CONFIGURATION")
      if let requested { environment["TYPEBAR_BUILD_CONFIGURATION"] = requested }
      process.environment = environment
      process.standardOutput = output; process.standardError = output
      try process.run()
      let diagnostics = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      process.waitUntilExit()
      if requested == "invalid" {
        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.path))
      } else {
        XCTAssertEqual(process.terminationStatus, 0, diagnostics)
        let selected = requested ?? "release"
        XCTAssertEqual(try String(contentsOf: log, encoding: .utf8),
          "build --configuration \(selected)\nbuild --configuration \(selected) --show-bin-path\n")
        XCTAssertEqual(try Data(contentsOf: app.appendingPathComponent("Contents/MacOS/Typebar")), Data("fixture".utf8))
      }
    }
  }
}
