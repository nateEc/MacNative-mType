import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Typebar

@MainActor
final class WebsiteConfigAsyncResourceTests: XCTestCase {
  private enum Failure: Error { case read, notCommitted, gateNotEntered }
  @MainActor private final class Fixture {
    let directory: URL
    let owner = UUID()
    let router = PreferenceConfigurationSaveRouter()
    let register: WebsiteConfigFileRegister
    var environment = WebsiteConfigCommitCoordinator.Environment(revision: UUID(), context: .init(), pointsPerRem: 16)
    lazy var coordinator = WebsiteConfigCommitCoordinator(router: router, register: register, environment: { [unowned self] in self.environment })
    init() throws {
      directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-async-resources-\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      register = WebsiteConfigFileRegister(directory: directory)
      router.register(owner: owner, save: { XCTFail("Resource admission must not broadcast legacy saves") })
    }
    func close() { try? FileManager.default.removeItem(at: directory) }
  }
  @MainActor private final class Gate {
    var continuation: CheckedContinuation<WebsiteConfigFontResource.Local, Never>?
    func read() async -> WebsiteConfigFontResource.Local {
      await withCheckedContinuation { continuation = $0 }
    }
    func finish() { let pending = continuation; continuation = nil; pending?.resume(returning: .absent) }
    func entered() async throws {
      for _ in 0..<1000 where continuation == nil { await Task.yield() }
      guard continuation != nil else { throw Failure.gateNotEntered }
    }
  }
  private func failure<T>(_ operation: () async throws -> T) async -> Error? {
    do { _ = try await operation(); XCTFail("Expected resource admission failure"); return nil }
    catch { return error }
  }
  private func stale(_ error: Error?, file: StaticString = #filePath, line: UInt = #line) {
    guard let error = error as? WebsiteConfigCommitCoordinatorError, case .stale = error else {
      return XCTFail("Expected stale resource admission, got \(String(describing: error))", file: file, line: line)
    }
  }
  private func success(_ outcome: WebsiteConfigCommitCoordinator.Outcome) throws -> WebsiteConfigCommitCoordinator.Publication {
    guard case .committed(let publication) = outcome else { throw Failure.notCommitted }
    return publication
  }

  func testAsyncReadsPreserveRawAddressAndPublishBothResourcesOnlyAtCommit() async throws {
    let f = try Fixture(); defer { f.close() }
    let ticket = try f.coordinator.prepare(#"{"time":37,"customBackground":"https://example.invalid/\ud800.png"}"#)
    let address = ticket.draft.pagePreferences.backgroundAddress
    let data = OwnedTestFontFixture.make(postScriptName: "TypebarAsync" + UUID().uuidString.replacingOccurrences(of: "-", with: ""))
    var order: [String] = []
    let ready = try await f.coordinator.prepareResources(for: ticket, readLocalFont: {
      order.append("font"); await Task.yield(); return .data(data)
    }, readLocalBackground: {
      order.append("background"); XCTAssertNil(f.coordinator.publication(for: f.owner))
      XCTAssertEqual(try f.register.read().state, .missing); await Task.yield(); return .absent
    }, fetchRemoteBackground: { actual, budget in
      order.append("remote"); XCTAssertEqual(actual, address); XCTAssertEqual(budget, 64 * 1024 * 1024)
      await Task.yield(); return .failed(address: actual)
    })
    XCTAssertEqual(order, ["font", "background", "remote"])
    XCTAssertEqual(ready.font.ownedLocalData, data)
    XCTAssertEqual(ready.background.source, .remote(address))
    guard case .failed(.transport) = ready.background.state else { return XCTFail("Lost explicit transport failure") }
    XCTAssertEqual(try f.register.read().state, .missing)
    let publication = try success(f.coordinator.commit(ready))
    XCTAssertNotNil(publication.font); XCTAssertNotNil(publication.background)
    XCTAssertEqual(try f.register.read().state, .available(publication.draft.projection.runtime))
  }

  func testAsyncAttemptRetiresPreviousResourcesBeforeItsFirstRead() async throws {
    let f = try Fixture(); defer { f.close() }
    let ticket = try f.coordinator.prepare("{}")
    let old = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.prepareResources(for: ticket, readLocalFont: {
      guard case .stale = try f.coordinator.commit(old) else { XCTFail("Old resource committed after new async admission"); return .absent }
      XCTAssertFalse(f.coordinator.cancel(old)); await Task.yield(); return .absent
    }, readLocalBackground: { .absent })
    XCTAssertEqual(try f.register.read().state, .missing)
    _ = try success(f.coordinator.commit(ready))
  }

  func testNewSyncAdmissionRetiresSuspendedAsyncBeforeNextRead() async throws {
    let f = try Fixture(); defer { f.close() }
    let ticket = try f.coordinator.prepare("{}")
    var replacement: WebsiteConfigCommitCoordinator.ResourcesPrepared?
    var backgroundReads = 0
    let error = await failure {
      try await f.coordinator.prepareResources(for: ticket, readLocalFont: {
        replacement = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
        await Task.yield(); return .absent
      }, readLocalBackground: { backgroundReads += 1; return .absent })
    }
    stale(error); XCTAssertEqual(backgroundReads, 0)
    _ = try success(f.coordinator.commit(XCTUnwrap(replacement)))
  }

  func testOwnerEnvironmentAndNewConfigurationRetireBeforeNextRead() async throws {
    for change in 0..<4 {
      let f = try Fixture(); defer { f.close() }
      let ticket = try f.coordinator.prepare(#"{"customBackground":"https://example.invalid/a.png"}"#)
      var reads = 0
      let error = await failure {
        try await f.coordinator.prepareResources(for: ticket, readLocalFont: {
          switch change {
          case 0:
            let other = UUID(); f.router.register(owner: other, save: {})
            f.router.activate(owner: other); f.router.activate(owner: f.owner)
          case 1:
            f.environment = .init(revision: UUID(), context: .init(), pointsPerRem: 16)
          case 2: _ = try f.coordinator.prepare(#"{"time":41}"#)
          default: XCTAssertThrowsError(try f.coordinator.prepare("{"))
          }
          await Task.yield(); return .absent
        }, readLocalBackground: { reads += 1; return .absent },
          fetchRemoteBackground: { address, _ in reads += 1; return .failed(address: address) })
      }
      stale(error); XCTAssertEqual(reads, 0, "Retired read continued into the next resource: \(change)")
      XCTAssertNil(f.coordinator.publication(for: f.owner)); XCTAssertEqual(try f.register.read().state, .missing)
    }
  }

  func testCancelledTaskCannotContinueWhenProducerIgnoresCancellation() async throws {
    let f = try Fixture(), gate = Gate(); defer { gate.finish(); f.close() }
    let ticket = try f.coordinator.prepare("{}")
    var backgroundReads = 0
    let pending = Task { @MainActor in
      _ = try await f.coordinator.prepareResources(for: ticket,
        readLocalFont: { await gate.read() }, readLocalBackground: { backgroundReads += 1; return .absent })
    }
    defer { pending.cancel() }
    try await gate.entered(); pending.cancel(); gate.finish()
    let error = await failure { try await pending.value }
    XCTAssertTrue(error is CancellationError); XCTAssertEqual(backgroundReads, 0)
    XCTAssertNil(f.coordinator.publication(for: f.owner)); XCTAssertEqual(try f.register.read().state, .missing)
  }

  func testReadFailureAndPresentLocalDataNeverBorrowRemoteOrChangeSavedValue() async throws {
    let f = try Fixture(); defer { f.close() }
    let previous = try success(f.coordinator.commit(f.coordinator.prepare(#"{"time":31}"#)))
    let ticket = try f.coordinator.prepare(#"{"customBackground":"https://example.invalid/a.png"}"#)
    var requests = 0
    let error = await failure {
      try await f.coordinator.prepareResources(for: ticket, readLocalFont: { throw Failure.read },
        readLocalBackground: { XCTFail("Read continued after font I/O error"); return .absent })
    }
    guard let error = error as? Failure, case .read = error else { return XCTFail("Lost actual local read error") }
    XCTAssertEqual(f.coordinator.publication(for: f.owner)?.disk, previous.disk)
    for local in [WebsiteConfigBackgroundResource.Local.empty, .data(Data())] {
      let ready = try await f.coordinator.prepareResources(for: ticket,
        readLocalFont: { .absent }, readLocalBackground: { local }, fetchRemoteBackground: { address, _ in
          requests += 1; return .failed(address: address)
        })
      switch (local, ready.background.state) {
      case (.empty, .none), (.data, .failed(.undecodable)): break
      default: XCTFail("Lost local presence semantics")
      }
    }
    XCTAssertEqual(requests, 0)
    XCTAssertEqual(try f.register.read().state, .available(previous.draft.projection.runtime))
  }

  func testSuspendedReadAllowsIndependentWriterButCannotOverwriteItsRecord() async throws {
    let f = try Fixture(), gate = Gate(); defer { gate.finish(); f.close() }
    let previous = try success(f.coordinator.commit(f.coordinator.prepare(#"{"time":31}"#)))
    let ticket = try f.coordinator.prepare(#"{"time":32}"#)
    var ready: WebsiteConfigCommitCoordinator.ResourcesPrepared?
    let pending = Task { @MainActor in
      ready = try await f.coordinator.prepareResources(for: ticket,
        readLocalFont: { await gate.read() }, readLocalBackground: { .absent })
    }
    defer { pending.cancel() }
    try await gate.entered()
    let writer = WebsiteConfigFileRegister(directory: f.directory)
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"time":33}"#, pointsPerRem: 16, context: .init())
    guard case .committed = try writer.commit(draft, replacing: XCTUnwrap(writer.read().revision)) else {
      return XCTFail("Async read held the file lock")
    }
    gate.finish()
    try await pending.value
    guard case .conflict = try f.coordinator.commit(XCTUnwrap(ready)) else { return XCTFail("Async resource overwrote independent writer") }
    XCTAssertEqual(try writer.read().state, .available(draft.projection.runtime))
    XCTAssertEqual(f.coordinator.publication(for: f.owner)?.disk, previous.disk)
  }

  func testSupersededProducerFailureBecomesStaleInsteadOfAnOldReadError() async throws {
    let f = try Fixture(); defer { f.close() }
    let ticket = try f.coordinator.prepare("{}")
    let error = await failure {
      try await f.coordinator.prepareResources(for: ticket, readLocalFont: {
        _ = try f.coordinator.prepare(#"{"time":44}"#); throw Failure.read
      }, readLocalBackground: { XCTFail("Retired failure continued"); return .absent })
    }
    stale(error); XCTAssertEqual(try f.register.read().state, .missing)
  }

  func testInvalidBudgetDoesNoIOButRetiresPreviousResourceResult() async throws {
    let f = try Fixture(); defer { f.close() }
    let ticket = try f.coordinator.prepare("{}")
    let old = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    var reads = 0
    let error = await failure {
      try await f.coordinator.prepareResources(for: ticket, readLocalFont: { reads += 1; return .absent },
        readLocalBackground: { reads += 1; return .absent }, maximumFontBytes: 0)
    }
    guard let error = error as? WebsiteConfigFontResourceError, case .invalidLimit = error else { return XCTFail("Wrong budget error") }
    XCTAssertEqual(reads, 0)
    guard case .stale = try f.coordinator.commit(old) else { return XCTFail("Failed new admission resurrected old resource") }
    for index in 0..<4 {
      let old = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
      var limits = WebsiteConfigBackgroundResource.Limits()
      switch index {
      case 0: limits.encodedBytes = 0
      case 1: limits.pixels = 0
      case 2: limits.decodedBytes = 0
      default: limits.frames = 0
      }
      let error = await failure {
        try await f.coordinator.prepareResources(for: ticket, readLocalFont: { reads += 1; return .absent },
          readLocalBackground: { reads += 1; return .absent }, backgroundLimits: limits)
      }
      XCTAssertEqual(error as? WebsiteConfigBackgroundResourceError, .invalidLimits)
      XCTAssertEqual(reads, 0)
      guard case .stale = try f.coordinator.commit(old) else { return XCTFail("Invalid background budget retained old admission") }
    }
  }

  func testStaleConfigurationCannotReadOrRetireCurrentResources() async throws {
    let f = try Fixture(); defer { f.close() }
    let old = try f.coordinator.prepare(#"{"time":31}"#)
    let current = try f.coordinator.prepare(#"{"time":32}"#)
    let ready = try f.coordinator.prepareResources(for: current, localFont: .absent, localBackground: .absent)
    let error = await failure {
      try await f.coordinator.prepareResources(for: old,
        readLocalFont: { XCTFail("Stale configuration read local font"); return .absent },
        readLocalBackground: { XCTFail("Stale configuration read background"); return .absent })
    }
    stale(error)
    _ = try success(f.coordinator.commit(ready))
  }

  func testCancellationBeforeAdmissionDoesNotRetireCurrentReadyResources() async throws {
    let f = try Fixture(); defer { f.close() }
    let ticket = try f.coordinator.prepare("{}")
    let ready = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    let pending = Task { @MainActor in
      _ = try await f.coordinator.prepareResources(for: ticket,
        readLocalFont: { XCTFail("Cancelled task started I/O"); return .absent },
        readLocalBackground: { XCTFail("Cancelled task continued I/O"); return .absent })
    }
    pending.cancel()
    let error = await failure { try await pending.value }
    XCTAssertTrue(error is CancellationError)
    _ = try success(f.coordinator.commit(ready))
  }

  func testExplicitCancellationRetiresCompletedAsyncTicketWithoutWriting() async throws {
    let f = try Fixture(); defer { f.close() }
    let ticket = try f.coordinator.prepare("{}")
    let ready = try await f.coordinator.prepareResources(for: ticket,
      readLocalFont: { await Task.yield(); return .absent }, readLocalBackground: { .absent })
    XCTAssertTrue(f.coordinator.cancel(ready))
    XCTAssertFalse(f.coordinator.cancel(ready))
    guard case .stale = try f.coordinator.commit(ready) else { return XCTFail("Cancelled returned ticket committed") }
    XCTAssertNil(f.coordinator.publication(for: f.owner))
    XCTAssertEqual(try f.register.read().state, .missing)
  }

  func testBackgroundOnlyAdmissionRetiresPendingRemoteValueAndError() async throws {
    for throwsError in [false, true] {
      let f = try Fixture(); defer { f.close() }
      let ticket = try f.coordinator.prepare(#"{"customBackground":"https://example.invalid/a.png"}"#)
      var replacement: WebsiteConfigCommitCoordinator.BackgroundPrepared?
      let error = await failure {
        try await f.coordinator.prepareResources(for: ticket,
          readLocalFont: { .absent }, readLocalBackground: { .absent }, fetchRemoteBackground: { address, _ in
            replacement = try f.coordinator.prepareBackground(for: ticket, local: .empty)
            await Task.yield()
            if throwsError { throw Failure.read }
            return .failed(address: address)
          })
      }
      stale(error)
      XCTAssertEqual(try f.register.read().state, .missing)
      let publication = try success(f.coordinator.commit(XCTUnwrap(replacement)))
      XCTAssertNil(publication.font)
      guard case .none? = publication.background?.state else { return XCTFail("Lost replacement background") }
    }
  }

  func testFontBytesAreOwnedBeforeTheFollowingBackgroundSuspension() async throws {
    let f = try Fixture(); defer { f.close() }
    let ticket = try f.coordinator.prepare("{}")
    let data = OwnedTestFontFixture.make(postScriptName: "TypebarAsyncOwned" + UUID().uuidString.replacingOccurrences(of: "-", with: ""))
    let mutable = NSMutableData(data: data)
    let ready = try await f.coordinator.prepareResources(for: ticket,
      readLocalFont: { .data(Data(referencing: mutable)) }, readLocalBackground: {
        mutable.length = 0; await Task.yield(); return .absent
      })
    XCTAssertEqual(ready.font.ownedLocalData, data)
    XCTAssertEqual(ready.font.primary.candidate, .local)
    let publication = try success(f.coordinator.commit(ready))
    XCTAssertEqual(publication.font?.ownedLocalData, data)
  }

  func testCommittedJointResourcesActuallyShapeTextAndRenderThePreparedImage() async throws {
    let f = try Fixture(); defer { f.close() }
    let ticket = try f.coordinator.prepare(#"{"customBackground":"https://example.invalid/a.png"}"#)
    let data = OwnedTestFontFixture.make(postScriptName: "TypebarAsyncJoint" + UUID().uuidString.replacingOccurrences(of: "-", with: ""), advanceWidth: 900)
    let image = try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: .init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: Data([255, 0, 0, 255]) as CFData)!, decode: nil,
      shouldInterpolate: false, intent: .defaultIntent))
    let output = NSMutableData()
    let encoder = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(encoder, image, nil); XCTAssertTrue(CGImageDestinationFinalize(encoder))
    let ready = try await f.coordinator.prepareResources(for: ticket,
      readLocalFont: { await Task.yield(); return .data(data) }, readLocalBackground: { .absent },
      fetchRemoteBackground: { address, _ in await Task.yield(); return .received(address: address, data: output as Data) })
    let publication = try success(f.coordinator.commit(ready))
    let font = try XCTUnwrap(publication.font?.renderingFont)
    XCTAssertEqual(NSAttributedString(string: "x", attributes: [.font: font]).size().width,
      font.pointSize * 0.9, accuracy: 0.001)
    guard case .ready(let preparedImage)? = publication.background?.state else { return XCTFail("Joint image was not ready") }
    let surface = WebsiteConfigBackgroundSurfaceView()
    defer { surface.stop() }
    surface.setFrameSize(CGSize(width: 4, height: 4))
    surface.configure(image: preparedImage, identity: UUID(), fit: .max,
      filter: publication.draft.pagePreferences.backgroundFilter)
    XCTAssertNil(surface.error)
    let rendered = try XCTUnwrap(surface.renderedImage)
    XCTAssertEqual(rendered.width, 4); XCTAssertEqual(rendered.height, 4)
    var pixel = [UInt8](repeating: 0, count: 4)
    try pixel.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1,
        bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(rendered, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    XCTAssertEqual(pixel, [255, 0, 0, 255])
  }
}
