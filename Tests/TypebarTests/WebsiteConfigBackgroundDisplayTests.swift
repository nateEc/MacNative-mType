import AppKit
import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigBackgroundDisplayTests: XCTestCase {
  private enum Failure: Error { case local }
  @MainActor private final class Gate {
    var continuation: CheckedContinuation<WebsiteConfigBackgroundResource.Local, Error>?
    func read() async throws -> WebsiteConfigBackgroundResource.Local {
      try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(_ local: WebsiteConfigBackgroundResource.Local?) {
      let pending = continuation; continuation = nil
      if let local { pending?.resume(returning: local) } else { pending?.resume(throwing: Failure.local) }
    }
  }
  @MainActor private final class Admission { var valid = true }
  @MainActor private final class Reads {
    var count = 0
    var pending: [Int: CheckedContinuation<WebsiteConfigBackgroundResource.Local, Error>] = [:]
    func read() async throws -> WebsiteConfigBackgroundResource.Local {
      let id = count; count += 1
      return try await withCheckedThrowingContinuation { pending[id] = $0 }
    }
    func finish(_ id: Int, _ value: WebsiteConfigBackgroundResource.Local?) {
      let continuation = pending.removeValue(forKey: id)
      if let value { continuation?.resume(returning: value) } else { continuation?.resume(throwing: Failure.local) }
    }
  }
  func testDeletionStartsBothBackgroundReadsBeforeEitherCompletes() async throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"fontFamily":"Courier"}"#, pointsPerRem: 16, context: .init())
    let display = WebsiteConfigBackgroundDisplay(owner: UUID(), preferences: draft.pagePreferences, pointsPerRem: 16, previous: nil)
    let reads = Reads()
    display.start(readLocal: reads.read, fetchRemote: { _, _ in XCTFail("Empty address fetched remote"); throw Failure.local },
      invocations: [.event, .command], whileCurrent: { true })
    let end = Date().addingTimeInterval(1)
    while reads.count < 2 && Date() < end { try await Task.sleep(for: .milliseconds(2)) }
    XCTAssertEqual(reads.count, 2)
    for id in Array(reads.pending.keys) { reads.finish(id, .absent) }
    await display.waitForCompletion()
  }
  func testCancellingBeforeApplicationsStartRetiresWithoutReadingAndCanRearm() async throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"fontFamily":"Courier"}"#, pointsPerRem: 16, context: .init())
    let display = WebsiteConfigBackgroundDisplay(owner: UUID(), preferences: draft.pagePreferences, pointsPerRem: 16, previous: nil)
    var reads = 0
    display.start(readLocal: { reads += 1; return .absent }, fetchRemote: { _, _ in throw Failure.local },
      invocations: [.event, .command], whileCurrent: { true })
    display.cancel(); await display.waitForCompletion()
    XCTAssertEqual(reads, 0); XCTAssertEqual(display.phase, .retired)
    display.start(readLocal: { reads += 1; return .empty }, fetchRemote: { _, _ in throw Failure.local }, whileCurrent: { true })
    await display.waitForCompletion(); XCTAssertEqual(reads, 1); XCTAssertEqual(display.phase, .settled)
  }

  func testCancellingBothReadsSuppressesLatePixelsAndFailureCallbacks() async throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"fontFamily":"Courier"}"#, pointsPerRem: 16, context: .init())
    let display = WebsiteConfigBackgroundDisplay(owner: UUID(), preferences: draft.pagePreferences, pointsPerRem: 16, previous: nil)
    let reads = Reads(), original = display.snapshot.identity
    var failures = 0
    display.start(readLocal: reads.read, fetchRemote: { _, _ in throw Failure.local }, invocations: [.event, .command],
      onReadFailure: { _, _ in failures += 1 }, whileCurrent: { true })
    let end = Date().addingTimeInterval(2)
    while reads.count < 2 && Date() < end { try await Task.sleep(for: .milliseconds(2)) }
    XCTAssertEqual(reads.count, 2); display.cancel()
    reads.finish(0, .data(try OwnedBackgroundImageFixture.make())); reads.finish(1, nil)
    await display.waitForCompletion(); XCTAssertEqual(display.snapshot.identity, original); XCTAssertEqual(failures, 0)
    XCTAssertEqual(display.phase, .retired)
  }

  func testRetiredOverlappingReadCannotWriteAfterARearmedApplication() async throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"fontFamily":"Courier"}"#, pointsPerRem: 16, context: .init())
    let display = WebsiteConfigBackgroundDisplay(owner: UUID(), preferences: draft.pagePreferences, pointsPerRem: 16, previous: nil)
    let reads = Reads(), admission = Admission()
    display.start(readLocal: reads.read, fetchRemote: { _, _ in throw Failure.local }, invocations: [.event, .command], whileCurrent: { admission.valid })
    let end = Date().addingTimeInterval(2)
    while reads.count < 2 && Date() < end { try await Task.sleep(for: .milliseconds(2)) }
    admission.valid = false; reads.finish(0, .absent)
    for _ in 0..<100 where display.phase != .retired { try await Task.sleep(for: .milliseconds(2)) }
    XCTAssertEqual(display.phase, .retired); admission.valid = true
    display.start(readLocal: { .empty }, fetchRemote: { _, _ in throw Failure.local }, whileCurrent: { admission.valid })
    await display.waitForCompletion(); let current = display.snapshot.identity
    reads.finish(1, .data(try OwnedBackgroundImageFixture.make()))
    try await Task.sleep(for: .milliseconds(20))
    XCTAssertEqual(display.snapshot.identity, current); XCTAssertEqual(display.phase, .settled)
    guard case .none = display.snapshot.resource.state else { return XCTFail("Old run restored pixels") }
  }

  func testLateDownloadCannotReplaceTheImageChosenByAnotherLocalRead() async throws {
    @MainActor final class Remote {
      var pending: CheckedContinuation<WebsiteConfigBackgroundResource.Remote, Never>?
      func read(_ address: WebsiteConfigValue, _ budget: Int) async -> WebsiteConfigBackgroundResource.Remote {
        await withCheckedContinuation { pending = $0 }
      }
    }
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"fontFamily":"Courier","customBackground":"https://example.invalid/old.png"}"#, pointsPerRem: 16, context: .init())
    let display = WebsiteConfigBackgroundDisplay(owner: UUID(), preferences: draft.pagePreferences, pointsPerRem: 16, previous: nil)
    let reads = Reads(), remote = Remote()
    display.start(readLocal: reads.read, fetchRemote: remote.read, invocations: [.event, .command], whileCurrent: { true })
    let end = Date().addingTimeInterval(2)
    while reads.count < 2 && Date() < end { try await Task.sleep(for: .milliseconds(2)) }
    reads.finish(0, .absent)
    while remote.pending == nil && Date() < end { try await Task.sleep(for: .milliseconds(2)) }
    XCTAssertNotNil(remote.pending); let previous = display.snapshot.identity
    reads.finish(1, .empty)
    while display.snapshot.identity == previous && Date() < end { try await Task.sleep(for: .milliseconds(2)) }
    let current = display.snapshot.identity
    remote.pending?.resume(returning: .received(address: draft.pagePreferences.backgroundAddress, data: try OwnedBackgroundImageFixture.make()))
    remote.pending = nil; await display.waitForCompletion()
    XCTAssertEqual(display.snapshot.identity, current)
    guard case .none = display.snapshot.resource.state else { return XCTFail("Late remote image replaced a newer selection") }
  }

  func testRetiredReadCanBeExplicitlyPreparedAgainWithoutAcceptingItsLatePixels() async throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"fontFamily":"Courier"}"#, pointsPerRem: 16, context: .init())
    let display = WebsiteConfigBackgroundDisplay(owner: UUID(), preferences: draft.pagePreferences, pointsPerRem: 16, previous: nil)
    let gate = Gate(), admission = Admission(), original = display.snapshot.identity
    display.start(readLocal: gate.read, fetchRemote: { _, _ in XCTFail("No remote read"); throw Failure.local }, whileCurrent: { admission.valid })
    let end = Date().addingTimeInterval(2)
    while gate.continuation == nil && Date() < end { try await Task.sleep(for: .milliseconds(2)) }
    XCTAssertNotNil(gate.continuation)
    admission.valid = false; gate.finish(.data(try OwnedBackgroundImageFixture.make())); await display.waitForCompletion()
    XCTAssertEqual(display.phase, .retired); XCTAssertEqual(display.snapshot.identity, original)
    admission.valid = true
    display.start(readLocal: { .empty }, fetchRemote: { _, _ in XCTFail("No remote read"); throw Failure.local }, whileCurrent: { admission.valid })
    await display.waitForCompletion()
    XCTAssertEqual(display.phase, .settled); XCTAssertNotEqual(display.snapshot.identity, original)
    guard case .none = display.snapshot.resource.state else { return XCTFail("Explicit retry must not reuse retired bytes") }
  }
  func testIndependentBackgroundPhasesAgainstCompletePinnedSelectionAndCallbacks() async throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned reference") }
    struct Frame: Decodable { let selected: String?; let hidden: Bool; let filterVisible: Bool; let borders: Int; let notices: Int }
    struct Sample: Decodable {
      let localKind: String, address: String, fit: String, result: String
      let updates: Bool, fulfilled: Bool, frames: [Frame]
    }
    struct Output: Decodable { let fixtures: [Sample] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-background-lifecycle.mjs").path, reference]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures.count, 96); XCTAssertEqual(output.fixtures.reduce(0) { $0 + $1.frames.count }, 288)
    let samples = output.fixtures.filter { !$0.updates }; XCTAssertEqual(samples.count, 48)
    let bytes = try OwnedBackgroundImageFixture.make()
    let previousDraft = try WebsiteConfigNativeProfile.prepareDraft(#"{"fontFamily":"Courier"}"#, pointsPerRem: 16, context: .init())
    let previousResource = try WebsiteConfigBackgroundResource.prepare(loadedData: bytes, source: .local)
    for sample in samples {
      let owner = UUID(), oldID = UUID(), gate = Gate()
      let draft = try WebsiteConfigNativeProfile.prepareDraft("""
        {"fontFamily":"Courier","customBackground":"\(sample.address)","customBackgroundSize":"\(sample.fit)","customBackgroundFilter":[0.25,2,3,0.5]}
        """, pointsPerRem: 16, context: .init())
      let display = WebsiteConfigBackgroundDisplay(owner: owner, preferences: draft.pagePreferences, pointsPerRem: 16,
        previous: .init(owner: owner, identity: oldID, resource: previousResource, preferences: previousDraft.pagePreferences, pointsPerRem: 16))
      display.start(readLocal: gate.read, fetchRemote: { address, _ in
        sample.result == "load" ? .received(address: address, data: bytes) : .failed(address: address)
      }, whileCurrent: { true })
      let end = Date().addingTimeInterval(2)
      while gate.continuation == nil && Date() < end { try await Task.sleep(for: .milliseconds(2)) }
      XCTAssertNotNil(gate.continuation); XCTAssertEqual(display.phase, .readingLocal)
      XCTAssertEqual(display.snapshot.identity, oldID)
      XCTAssertEqual(sample.frames.first?.selected, "owned:old")
      switch sample.localKind {
      case "reject": gate.finish(nil)
      case "empty": gate.finish(.empty)
      case "file": gate.finish(.data(sample.result == "load" ? bytes : Data("owned invalid image".utf8)))
      default: gate.finish(.absent)
      }
      await display.waitForCompletion()
      let expected = try XCTUnwrap(sample.frames.last)
      let visible: Bool
      switch display.snapshot.resource.state { case .ready(let image): visible = true; XCTAssertEqual(image.encodedData, bytes); default: visible = false }
      XCTAssertEqual(visible, expected.selected != nil && !expected.hidden)
      if sample.fulfilled {
        XCTAssertEqual(display.phase, .settled); XCTAssertNotEqual(display.snapshot.identity, oldID)
        XCTAssertEqual(display.snapshot.preferences.backgroundFit.rawValue, sample.fit)
        XCTAssertEqual(display.snapshot.preferences.backgroundFilter.brightness, 2)
      } else {
        XCTAssertEqual(display.phase, .localReadFailed); XCTAssertEqual(display.snapshot.identity, oldID)
      }
      switch expected.selected {
      case nil: XCTAssertNil(display.snapshot.resource.source)
      case "owned:local", "owned:old": XCTAssertEqual(display.snapshot.resource.source, .local)
      default: XCTAssertEqual(display.snapshot.resource.source, .remote(.string(sample.address)))
      }
      // This is an actual AppKit image handoff. Pixel/filter geometry retains
      // its separate existing tests; no browser filter-section UI is claimed.
      let view = WebsiteConfigPublishedBackgroundView(); defer { view.stop() }
      view.setFrameSize(.init(width: 16, height: 16))
      view.configure(snapshot: display.snapshot, onFailure: { _ in })
      view.layoutSubtreeIfNeeded()
      XCTAssertEqual(view.surface.renderedImage != nil, visible)
    }
  }
}
