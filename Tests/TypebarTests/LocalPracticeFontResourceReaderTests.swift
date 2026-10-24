import AppKit
import CoreText
import Darwin
import Foundation
import XCTest
@testable import Typebar

@MainActor
final class LocalPracticeFontResourceReaderTests: XCTestCase {
  @MainActor private final class Fixture {
    let suite = "typebar-font-read.\(UUID())"
    let defaults: UserDefaults
    let directory: URL
    let reader: LocalPracticeFontResourceReader
    init() throws {
      defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-font-read-\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
      reader = .init(directoryURL: directory, defaults: defaults)
    }
    func file(_ name: String = "local-practice-font-active-a.ttf", data: Data = Data([1, 2, 3])) throws -> URL {
      let url = directory.appendingPathComponent(name); try data.write(to: url); return url
    }
    func close() { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
  }
  private func bytes(_ value: WebsiteConfigFontResource.Local) -> Data? {
    if case .data(let data) = value { return data }; return nil
  }

  func testLegacyChoiceAndSelectedGenerationReadWithoutChangingMetadata() throws {
    let f = try Fixture(); defer { f.close() }
    _ = try f.file("local-practice-font-active-z.ttf", data: Data([9]))
    _ = try f.file()
    _ = try f.file("unrelated.ttf", data: Data([8]))
    XCTAssertEqual(bytes(try f.reader.read()), Data([1, 2, 3]))
    XCTAssertNil(f.defaults.object(forKey: LocalPracticeFontPreferenceKeys.selected))
    f.defaults.set("local-practice-font-active-z.ttf", forKey: LocalPracticeFontPreferenceKeys.selected)
    let before = f.defaults.dictionaryRepresentation()
    XCTAssertEqual(bytes(try f.reader.read()), Data([9]))
    XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: f.defaults.dictionaryRepresentation()))
  }

  func testDisabledAndExplicitNoSelectionDoNotTouchUnavailableDirectory() throws {
    let f = try Fixture(); defer { f.close() }
    let file = try f.file()
    f.defaults.set(false, forKey: LocalPracticeFontPreferenceKeys.enabled)
    XCTAssertNil(bytes(try f.reader.read()))
    XCTAssertEqual(try Data(contentsOf: file), Data([1, 2, 3]))
    f.defaults.removeObject(forKey: LocalPracticeFontPreferenceKeys.enabled)
    f.defaults.set("", forKey: LocalPracticeFontPreferenceKeys.selected)
    let invalidRoot = LocalPracticeFontResourceReader(directoryURL: file, defaults: f.defaults)
    XCTAssertNil(bytes(try invalidRoot.read()))
  }

  func testCorruptOrMissingSelectionNeverBorrowsAnotherRetainedFont() throws {
    let f = try Fixture(); defer { f.close() }
    _ = try f.file()
    for value: Any in [17, ["bad"], "../outside.ttf", "local-practice-font-active-../../outside.ttf",
      "local-practice-font-active-a.ttf\0other.ttf", "local-practice-font-active-missing.ttf"] {
      f.defaults.set(value, forKey: LocalPracticeFontPreferenceKeys.selected)
      XCTAssertThrowsError(try f.reader.read(), "Bad explicit selection was treated as absent: \(value)")
    }
  }

  func testAbsentAndPresentEmptyAreDifferentAndBudgetsApplyBeforeReading() throws {
    let f = try Fixture(); defer { f.close() }
    XCTAssertNil(bytes(try f.reader.read()))
    _ = try f.file(data: Data())
    XCTAssertEqual(bytes(try f.reader.read()), Data())
    for limit in [0, -1, Int.max] {
      XCTAssertThrowsError(try f.reader.read(maximumBytes: limit)) {
        XCTAssertEqual($0 as? LocalPracticeFontReadError, .invalidLimit)
      }
    }
    _ = try f.file(data: Data([1, 2, 3]))
    XCTAssertEqual(bytes(try f.reader.read(maximumBytes: 3)), Data([1, 2, 3]))
    XCTAssertThrowsError(try f.reader.read(maximumBytes: 2)) {
      XCTAssertEqual($0 as? LocalPracticeFontReadError, .resourceLimit)
    }
  }

  func testMemoryOwnsItsBytesAndDifferentReadersDoNotBorrowEachOther() throws {
    let storage = NSMutableData(data: Data([1, 2, 3]))
    let first = LocalPracticeFontResourceReader.inMemory(data: Data(referencing: storage))
    let second = LocalPracticeFontResourceReader.inMemory(data: Data([8]))
    storage.length = 0
    XCTAssertEqual(bytes(try first.read()), Data([1, 2, 3]))
    XCTAssertEqual(bytes(try second.read()), Data([8]))
    XCTAssertNil(bytes(try LocalPracticeFontResourceReader.inMemory().read()))
    XCTAssertThrowsError(try first.read(maximumBytes: 2))
  }

  func testMissingDirectoryIsAbsentOnlyWithoutAnExplicitSelection() throws {
    let f = try Fixture(); defer { f.close() }
    let reader = LocalPracticeFontResourceReader(directoryURL: f.directory.appendingPathComponent("missing"), defaults: f.defaults)
    XCTAssertNil(bytes(try reader.read()))
    f.defaults.set("local-practice-font-active-a.ttf", forKey: LocalPracticeFontPreferenceKeys.selected)
    XCTAssertThrowsError(try reader.read())
    let file = try f.file("not-a-directory", data: Data([7]))
    XCTAssertThrowsError(try LocalPracticeFontResourceReader(directoryURL: file, defaults: f.defaults).read())
  }

  func testLinksDirectoriesAndFIFOAreNotFontDataAndNeverFallBack() throws {
    let f = try Fixture(); defer { f.close() }
    let good = try f.file("unrelated.ttf")
    let link = f.directory.appendingPathComponent("local-practice-font-active-link.ttf")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: good)
    let folder = f.directory.appendingPathComponent("local-practice-font-active-folder.ttf")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    let pipe = f.directory.appendingPathComponent("local-practice-font-active-pipe.ttf")
    XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
    let keeper = open(pipe.path, O_RDWR | O_NONBLOCK | O_CLOEXEC)
    XCTAssertGreaterThanOrEqual(keeper, 0); defer { if keeper >= 0 { Darwin.close(keeper) } }
    for url in [link, folder, pipe] {
      f.defaults.set(url.lastPathComponent, forKey: LocalPracticeFontPreferenceKeys.selected)
      XCTAssertThrowsError(try f.reader.read())
    }
    let alias = f.directory.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: f.directory)
    f.defaults.removeObject(forKey: LocalPracticeFontPreferenceKeys.selected)
    XCTAssertThrowsError(try LocalPracticeFontResourceReader(directoryURL: alias, defaults: f.defaults).read())
  }

  func testQASelectionNeverUsesTheConfiguredDiskAndReaderDoesNotRegisterFonts() throws {
    let f = try Fixture(); defer { f.close() }
    XCTAssertTrue(LocalPracticeFontResourceReader.configured(defaults: f.defaults,
      info: [QAStoreMode.inMemoryInfoKey: true], environment: [:]).isInMemory)
    XCTAssertTrue(LocalPracticeFontResourceReader.configured(defaults: f.defaults,
      info: [:], environment: ["TYPEBAR_QA_IN_MEMORY_STORE": "1"]).isInMemory)
    let name = "TypebarReadOnly" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let data = OwnedTestFontFixture.make(postScriptName: name)
    _ = try f.file(data: data)
    XCTAssertEqual(bytes(try f.reader.read()), data)
    XCTAssertFalse((CTFontManagerCopyAvailablePostScriptNames() as? [String])?.contains(name) == true)
    let settings = AppSettings(defaults: f.defaults, feedbackSound: .init(loadSound: { _ in nil }, beep: {}),
      localBackgroundStore: .inMemory(), localPracticeFontResources: f.reader)
    XCTAssertEqual(bytes(try settings.readLocalPracticeFontResource()), data)
  }

  func testHiddenFilesAndNonFileRootsAreNotBorrowed() throws {
    let f = try Fixture(); defer { f.close() }
    let hidden = try f.file()
    let good = try f.file("local-practice-font-active-z.ttf", data: Data([9]))
    XCTAssertEqual(chflags(hidden.path, UInt32(UF_HIDDEN)), 0)
    defer { _ = chflags(hidden.path, 0) }
    XCTAssertEqual(bytes(try f.reader.read()), Data([9]))
    f.defaults.set(hidden.lastPathComponent, forKey: LocalPracticeFontPreferenceKeys.selected)
    XCTAssertThrowsError(try f.reader.read())
    f.defaults.set(good.lastPathComponent, forKey: LocalPracticeFontPreferenceKeys.selected)
    let remote = try XCTUnwrap(URL(string: "https://example.invalid" + f.directory.path))
    XCTAssertThrowsError(try LocalPracticeFontResourceReader(directoryURL: remote, defaults: f.defaults).read())
    let foreignHost = try XCTUnwrap(URL(string: "file://example.invalid" + f.directory.path))
    var withQuery = try XCTUnwrap(URLComponents(url: f.directory, resolvingAgainstBaseURL: false))
    withQuery.query = "ignored"
    var withFragment = try XCTUnwrap(URLComponents(url: f.directory, resolvingAgainstBaseURL: false))
    withFragment.fragment = "ignored"
    for url in [foreignHost, try XCTUnwrap(withQuery.url), try XCTUnwrap(withFragment.url)] {
      XCTAssertThrowsError(try LocalPracticeFontResourceReader(directoryURL: url, defaults: f.defaults).read()) {
        XCTAssertEqual($0 as? LocalPracticeFontReadError, .invalidSelection)
      }
    }
    var localhost = try XCTUnwrap(URLComponents(url: f.directory, resolvingAgainstBaseURL: false))
    localhost.host = "localhost"
    XCTAssertEqual(bytes(try LocalPracticeFontResourceReader(directoryURL: XCTUnwrap(localhost.url), defaults: f.defaults).read()), Data([9]))
  }

  func testEntryDecoderRejectsOwnedMalformedBytesAndIgnoresUnrelatedEntries() throws {
    // This host rejects creation of malformed UTF-8 filenames with EILSEQ.
    // Exercise the exact directory-entry decoder, not a claimed filesystem fixture.
    let raw = Array(LocalPracticeFontImport.storedFilenamePrefix.utf8) + [UInt8(255)] + Array(".ttf".utf8)
    XCTAssertThrowsError(try LocalPracticeFontResourceReader.storedFilename(fromUTF8: raw)) {
      XCTAssertEqual($0 as? LocalPracticeFontReadError, .invalidFilename)
    }
    XCTAssertNil(try LocalPracticeFontResourceReader.storedFilename(fromUTF8: [255]))
    let valid = "local-practice-font-active-a.ttf"
    XCTAssertEqual(try LocalPracticeFontResourceReader.storedFilename(fromUTF8: Array(valid.utf8)), valid)
  }

  func testTwoModelInstancesReadTheirOwnResourcesWithoutPersistingThem() throws {
    let f = try Fixture(); defer { f.close() }
    let a = AppSettings(defaults: f.defaults, feedbackSound: .init(loadSound: { _ in nil }, beep: {}),
      localBackgroundStore: .inMemory(), localPracticeFontResources: .inMemory(data: Data([1])))
    let b = AppSettings(defaults: f.defaults, feedbackSound: .init(loadSound: { _ in nil }, beep: {}),
      localBackgroundStore: .inMemory(), localPracticeFontResources: .inMemory(data: Data([9])))
    let before = f.defaults.dictionaryRepresentation()
    XCTAssertEqual(bytes(try a.readLocalPracticeFontResource()), Data([1]))
    XCTAssertEqual(bytes(try b.readLocalPracticeFontResource()), Data([9]))
    XCTAssertEqual(a.snapshot, b.snapshot)
    XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: f.defaults.dictionaryRepresentation()))
  }
}
