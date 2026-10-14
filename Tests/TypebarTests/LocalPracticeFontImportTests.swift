import Foundation
import XCTest
@testable import Typebar

final class LocalPracticeFontImportTests: XCTestCase {
  private let info = LocalPracticeFontInfo(postScriptName: "OwnedFixture", displayName: "Owned Fixture")

  private func withDirectory(_ action: (URL, URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
      .resolvingSymlinksInPath()
      .appendingPathComponent("typebar-font-import-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let previous = directory.appendingPathComponent("local-practice-font-active-old.ttf")
    try Data("previous fixture".utf8).write(to: previous)
    try action(directory, previous)
  }

  func testFailedReplacementRestoresOnlyPreviousFontAndLeavesItsBytesAndEnabledState() throws {
    try withDirectory { directory, previous in
      var registrations: [URL] = [], removals: [URL] = []
      var enables = 0
      XCTAssertThrowsError(try LocalPracticeFontImport.save(Data("new fixture".utf8),
        originalFilename: "new.woff2", directory: directory, readInfo: { _ in self.info },
        register: { url in registrations.append(url); return url.lastPathComponent == previous.lastPathComponent ? self.info : nil },
        unregister: { removals.append($0) }, enable: { enables += 1 })) { error in
          switch error {
          case LocalPracticeFontError.couldNotLoad: break
          default: XCTFail("Expected registration failure, received \(error)")
          }
        }
      XCTAssertEqual(removals.count, 2, "Retire old once, then clean a possibly partially registered new font")
      XCTAssertEqual(removals.first?.lastPathComponent, previous.lastPathComponent)
      XCTAssertEqual(removals.last?.lastPathComponent, registrations.first?.lastPathComponent)
      XCTAssertEqual(registrations.count, 2, "Try new once, then restore the previous font once")
      XCTAssertEqual(registrations.last?.lastPathComponent, previous.lastPathComponent)
      XCTAssertEqual(LocalPracticeFontImport.storedURLs(in: directory).map(\.lastPathComponent), [previous.lastPathComponent])
      XCTAssertEqual(try Data(contentsOf: previous), Data("previous fixture".utf8))
      XCTAssertEqual(enables, 0)
      XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path),
        [previous.lastPathComponent], "Neither candidate nor failed active file may remain")
    }
  }

  func testUnregistrationFailureKeepsPreviousFontAndNeverPublishesReplacement() throws {
    try withDirectory { directory, previous in
      let failure = NSError(domain: "CoreTextUnregisterFailure", code: 9)
      var registered = false, enabled = false
      XCTAssertThrowsError(try LocalPracticeFontImport.save(Data("new fixture".utf8),
        originalFilename: "new.ttf", directory: directory, readInfo: { _ in self.info },
        register: { url in
          XCTAssertEqual(url.lastPathComponent, previous.lastPathComponent,
            "A failed unload may only restore the old file")
          registered = true
          return self.info
        }, unregister: { url in
          XCTAssertEqual(url.lastPathComponent, previous.lastPathComponent)
          throw failure
        }, enable: { enabled = true })) { error in
          XCTAssertEqual(error as NSError, failure)
        }
      XCTAssertTrue(registered, "The failed unload might have partially changed native registration")
      XCTAssertFalse(enabled)
      XCTAssertEqual(LocalPracticeFontImport.storedURLs(in: directory).map(\.lastPathComponent),
        [previous.lastPathComponent])
      XCTAssertEqual(try Data(contentsOf: previous), Data("previous fixture".utf8))
      XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path),
        [previous.lastPathComponent])
    }
  }

  func testSecondOldFontUnregistrationFailureRestoresAttemptedFontsAndKeepsAllFiles() throws {
    try withDirectory { directory, previous in
      let second = directory.appendingPathComponent("local-practice-font-active-z.ttf")
      try Data("second fixture".utf8).write(to: second)
      let failure = NSError(domain: "CoreTextUnregisterFailure", code: 10)
      var unloaded: [String] = [], restored: [String] = []
      XCTAssertThrowsError(try LocalPracticeFontImport.save(Data("new fixture".utf8),
        originalFilename: "new.ttf", directory: directory, readInfo: { _ in self.info },
        register: { url in restored.append(url.lastPathComponent); return self.info },
        unregister: { url in
          unloaded.append(url.lastPathComponent)
          if url.lastPathComponent == second.lastPathComponent { throw failure }
        }, enable: { XCTFail("Failed replacement must not enable a new font") })) { error in
          XCTAssertEqual(error as NSError, failure)
        }
      XCTAssertEqual(unloaded, [previous.lastPathComponent, second.lastPathComponent])
      XCTAssertEqual(restored, unloaded)
      XCTAssertEqual(LocalPracticeFontImport.storedURLs(in: directory).map(\.lastPathComponent), unloaded)
      XCTAssertEqual(try Data(contentsOf: previous), Data("previous fixture".utf8))
      XCTAssertEqual(try Data(contentsOf: second), Data("second fixture".utf8))
    }
  }

  func testFailedNewFontCleanupKeepsFileIfNativeUnregistrationFails() throws {
    try withDirectory { directory, previous in
      let failure = NSError(domain: "CoreTextUnregisterFailure", code: 11)
      var failedNewURL: URL?, restoredOld = false
      XCTAssertThrowsError(try LocalPracticeFontImport.save(Data("new fixture".utf8),
        originalFilename: "new.ttf", directory: directory, readInfo: { _ in self.info },
        register: { url in
          if url.lastPathComponent == previous.lastPathComponent { restoredOld = true; return self.info }
          failedNewURL = url
          return nil // Native registration may have succeeded before source validation failed.
        }, unregister: { url in
          if url.lastPathComponent != previous.lastPathComponent { throw failure }
        }, enable: { XCTFail("Failed replacement must not change the enabled setting") })) { error in
          guard case LocalPracticeFontError.couldNotLoad = error else {
            return XCTFail("Expected loading failure, received \(error)")
          }
        }
      let retained = try XCTUnwrap(failedNewURL)
      XCTAssertTrue(restoredOld)
      XCTAssertEqual(try Data(contentsOf: retained), Data("new fixture".utf8),
        "A possibly registered file must remain at its original URL")
      XCTAssertEqual(try Data(contentsOf: previous), Data("previous fixture".utf8))
    }
  }

  func testSuccessfulReplacementRemovesOldFileOnlyAfterNewRegistrationAndEnablesOnce() throws {
    try withDirectory { directory, previous in
      var registrations: [URL] = [], removals: [URL] = []
      var enables = 0
      let bytes = Data("new fixture".utf8)
      let result = try LocalPracticeFontImport.save(bytes, originalFilename: "new.otf",
        directory: directory, readInfo: { _ in self.info }, register: { url in
          XCTAssertTrue(FileManager.default.fileExists(atPath: previous.path))
          registrations.append(url)
          return self.info
        }, unregister: { removals.append($0) }, enable: { enables += 1 })
      XCTAssertEqual(result, info)
      XCTAssertEqual(removals.map(\.lastPathComponent), [previous.lastPathComponent])
      XCTAssertEqual(registrations.count, 1)
      let active = try XCTUnwrap(registrations.first)
      XCTAssertEqual(LocalPracticeFontImport.storedURLs(in: directory).map(\.lastPathComponent), [active.lastPathComponent])
      XCTAssertEqual(try Data(contentsOf: active), bytes)
      XCTAssertFalse(FileManager.default.fileExists(atPath: previous.path))
      XCTAssertEqual(enables, 1)
      XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [active.lastPathComponent])
    }
  }

  func testInvalidCandidateNeverUnregistersOrChangesPreviousFont() throws {
    try withDirectory { directory, previous in
      XCTAssertThrowsError(try LocalPracticeFontImport.save(Data("invalid".utf8),
        originalFilename: "new.ttf", directory: directory, readInfo: { _ in nil },
        register: { _ in XCTFail("Invalid data must not register"); return nil },
        unregister: { _ in XCTFail("Invalid data must not unregister") },
        enable: { XCTFail("Invalid data must not enable") }))
      XCTAssertEqual(LocalPracticeFontImport.storedURLs(in: directory).map(\.lastPathComponent), [previous.lastPathComponent])
      XCTAssertEqual(try Data(contentsOf: previous), Data("previous fixture".utf8))
      XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [previous.lastPathComponent])
    }
  }

  func testDirectoryAliasDoesNotCauseSuccessfulReplacementToDeleteItsOwnFile() throws {
    try withDirectory { directory, previous in
      let alias = directory.appendingPathComponent("alias", isDirectory: true)
      try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: directory.path)
      XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: alias.resolvingSymlinksInPath().path)
        .contains(previous.lastPathComponent), "The alias fixture must resolve to the directory holding the old font")
      let bytes = Data("new fixture".utf8)
      _ = try LocalPracticeFontImport.save(bytes, originalFilename: "new.ttf", directory: alias,
        readInfo: { _ in self.info }, register: { _ in self.info },
        unregister: { _ in }, enable: {})
      let active = try XCTUnwrap(LocalPracticeFontImport.storedURLs(in: directory).first)
      XCTAssertEqual(try Data(contentsOf: active), bytes)
      XCTAssertEqual(LocalPracticeFontImport.storedURLs(in: directory).count, 1)
    }
  }

  func testUnsupportedFormatDoesNotReadRegisterOrChangeStoredFiles() throws {
    try withDirectory { directory, previous in
      XCTAssertThrowsError(try LocalPracticeFontImport.save(Data(), originalFilename: "new.ttc",
        directory: directory, readInfo: { _ in XCTFail("Unsupported format must not be read"); return nil },
        register: { _ in XCTFail("Unsupported format must not register"); return nil },
        unregister: { _ in XCTFail("Unsupported format must not unregister") },
        enable: { XCTFail("Unsupported format must not enable") })) { error in
          switch error {
          case LocalPracticeFontError.unsupportedFormat: break
          default: XCTFail("Expected unsupported format, received \(error)")
          }
        }
      XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [previous.lastPathComponent])
      XCTAssertEqual(try Data(contentsOf: previous), Data("previous fixture".utf8))
    }
  }

  func testSameNameAvailableButRegistrationFailsPreservesPreviousFile() throws {
    try withDirectory { directory, previous in
      var enables = 0
      XCTAssertThrowsError(try LocalPracticeFontImport.save(Data("new fixture".utf8),
        originalFilename: "new.ttf", directory: directory, readInfo: { _ in self.info },
        register: { url in
          LocalPracticeFontRegistration.read(url: url,
            register: { $0.lastPathComponent == previous.lastPathComponent },
            isRegistered: { _ in false }, readInfo: { _ in self.info },
            isSelectedSource: { _, _ in true })
        }, unregister: { _ in }, enable: { enables += 1 }))
      XCTAssertEqual(try Data(contentsOf: previous), Data("previous fixture".utf8))
      XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [previous.lastPathComponent])
      XCTAssertEqual(enables, 0)
    }
  }
}
