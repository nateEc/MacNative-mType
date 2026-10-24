import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Typebar

@MainActor
final class WebsiteConfigModelResourceTests: XCTestCase {
  @MainActor private final class Fixture {
    let suite = "typebar-model-resources.\(UUID())"
    let defaults: UserDefaults
    let directory: URL
    let fonts: URL
    let settings: AppSettings
    let source: WebsiteConfigEnvironmentSource
    let register: WebsiteConfigFileRegister
    let coordinator: WebsiteConfigCommitCoordinator
    let owner = UUID()
    init() throws {
      defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-model-resources-\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      fonts = directory.appendingPathComponent("fonts")
      try FileManager.default.createDirectory(at: fonts, withIntermediateDirectories: false)
      settings = AppSettings(defaults: defaults, feedbackSound: .init(loadSound: { _ in nil }, beep: {}),
        localBackgroundStore: .inMemory(), localPracticeFontResources: .init(directoryURL: fonts, defaults: defaults))
      settings.preferenceConfigurationSaves.register(owner: owner, save: { XCTFail("Resource reads must not broadcast legacy saves") })
      source = WebsiteConfigEnvironmentSource(settings: settings, account: AccountSession(defaults: defaults),
        pointsPerRem: 16, documentComplete: true, development: false)
      register = WebsiteConfigFileRegister(directory: directory)
      coordinator = WebsiteConfigCommitCoordinator(router: settings.preferenceConfigurationSaves, register: register, environment: source.read)
    }
    func font(_ data: Data) throws {
      try data.write(to: fonts.appendingPathComponent("local-practice-font-active-a.ttf"))
    }
    func close() { source.stop(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
  }
  private func success(_ outcome: WebsiteConfigCommitCoordinator.Outcome) throws -> WebsiteConfigCommitCoordinator.Publication {
    guard case .committed(let value) = outcome else { throw NSError(domain: "TypebarQA", code: 1) }
    return value
  }
  private func png() throws -> Data {
    let image = try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: .init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: Data([255, 0, 0, 255]) as CFData)!, decode: nil,
      shouldInterpolate: false, intent: .defaultIntent))
    let output = NSMutableData()
    let encoder = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(encoder, image, nil); XCTAssertTrue(CGImageDestinationFinalize(encoder))
    return output as Data
  }

  func testActualModelReadersPrepareOwnedFontAndLocalBackgroundThenCommitJointValue() async throws {
    let f = try Fixture(); defer { f.close() }
    let name = "TypebarModelResource" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let font = OwnedTestFontFixture.make(postScriptName: name, advanceWidth: 900), image = try png()
    try f.font(font)
    try f.settings.importLocalBackground(data: image)
    for _ in 0..<100 where f.source.read() == nil { await Task.yield() }
    let ticket = try f.coordinator.prepare(#"{"customBackground":"https://example.invalid/a.png","time":37}"#)
    var requests = 0
    let ready = try await f.coordinator.prepareResources(for: ticket, from: f.settings, fetchRemoteBackground: { address, _ in
      requests += 1; return .failed(address: address)
    })
    XCTAssertEqual(ready.font.ownedLocalData, font); XCTAssertEqual(ready.font.primary.font.fontName, name)
    XCTAssertEqual(ready.background.source, .local)
    guard case .ready(let background) = ready.background.state else { return XCTFail("Local model image was not ready") }
    XCTAssertEqual(background.encodedData, image); XCTAssertEqual(requests, 0)
    XCTAssertFalse((CTFontManagerCopyAvailablePostScriptNames() as? [String])?.contains(name) == true)
    XCTAssertEqual(try f.register.read().state, .missing)
    let publication = try success(f.coordinator.commit(ready))
    XCTAssertEqual(try f.register.read().state, .available(publication.draft.projection.runtime))
    XCTAssertEqual(publication.font?.ownedLocalData, font)
  }

  func testCorruptModelFontSelectionStopsPreparationAndPreservesThePreviousRecord() async throws {
    let f = try Fixture(); defer { f.close() }
    let previous = try success(f.coordinator.commit(f.coordinator.prepare(#"{"time":31}"#)))
    f.defaults.set(17, forKey: LocalPracticeFontPreferenceKeys.selected)
    let ticket = try f.coordinator.prepare(#"{"customBackground":"https://example.invalid/a.png","time":37}"#)
    var requests = 0
    do {
      _ = try await f.coordinator.prepareResources(for: ticket, from: f.settings, fetchRemoteBackground: { address, _ in
        requests += 1; return .failed(address: address)
      })
      XCTFail("Corrupt choice silently became absent")
    } catch { XCTAssertEqual(error as? LocalPracticeFontReadError, .invalidSelection) }
    XCTAssertEqual(requests, 0)
    XCTAssertEqual(try f.register.read().state, .available(previous.draft.projection.runtime))
    XCTAssertEqual(f.coordinator.publication(for: f.owner)?.disk, previous.disk)
  }

  func testPresentEmptyFontKeepsLocalFailureAndOmitsConfiguredPrimary() async throws {
    let f = try Fixture(); defer { f.close() }
    try f.font(Data())
    let ticket = try f.coordinator.prepare(#"{"fontFamily":"Courier"}"#)
    let ready = try await f.coordinator.prepareResources(for: ticket, from: f.settings)
    XCTAssertEqual(ready.font.localFailure, .undecodable)
    XCTAssertEqual(ready.font.candidates.first, .local)
    XCTAssertFalse(ready.font.candidates.contains(.family("Courier")))
    _ = try success(f.coordinator.commit(ready))
  }

  func testModelReadBudgetRefusesOversizeBeforeAnyRemoteRequest() async throws {
    let f = try Fixture(); defer { f.close() }
    try f.font(Data([1, 2, 3]))
    let ticket = try f.coordinator.prepare(#"{"customBackground":"https://example.invalid/a.png"}"#)
    var requests = 0
    do {
      _ = try await f.coordinator.prepareResources(for: ticket, from: f.settings,
        fetchRemoteBackground: { address, _ in requests += 1; return .failed(address: address) }, maximumFontBytes: 2)
      XCTFail("Model font read ignored admission budget")
    } catch { XCTAssertEqual(error as? LocalPracticeFontReadError, .resourceLimit) }
    XCTAssertEqual(requests, 0); XCTAssertEqual(try f.register.read().state, .missing)
  }

  func testModelAdmissionDoesNotPromoteDOMOnlyDataAddressesToImportedSettings() async throws {
    let f = try Fixture(); defer { f.close() }
    let image = try png()
    let address = "data:image/png;base64," + image.base64EncodedString()
    let json = String(decoding: try JSONSerialization.data(withJSONObject: ["customBackground": address]), as: UTF8.self)
    let ticket = try f.coordinator.prepare(json)
    XCTAssertEqual(ticket.draft.pagePreferences.backgroundAddress, .string(""))
    var requests = 0
    let reader = WebsiteConfigBackgroundRemoteReader { _, _ in requests += 1; return image }
    let ready = try await f.coordinator.prepareResources(for: ticket, from: f.settings, remoteReader: reader)
    guard case .none = ready.background.state else { return XCTFail("Import widened the original schema") }
    XCTAssertEqual(requests, 0)
    let publication = try success(f.coordinator.commit(ready))
    XCTAssertEqual(publication.draft.projection.runtime["customBackground"], .string(""))
    XCTAssertEqual(try f.register.read().state, .available(publication.draft.projection.runtime))
  }

  func testActualHTTPModelProducerCommitsFailureIntentWithoutChangingItsAddress() async throws {
    let f = try Fixture(); defer { f.close() }
    let configuration = CustomBackgroundDownload.configuration(); configuration.protocolClasses = [BackgroundBytesProtocol.self]
    let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
    let reader = WebsiteConfigBackgroundRemoteReader { try await CustomBackgroundDownload.data(from: $0, maximumBytes: $1, session: session) }
    let ticket = try f.coordinator.prepare(#"{"customBackground":"https://background-test.invalid/render.png?image=1"}"#)
    for (status, data, reason) in [(404, Data([1]), WebsiteConfigBackgroundResource.Failure.transport),
      (200, Data(repeating: 7, count: 4), .resourceLimit)] {
      BackgroundBytesProtocol.fixture.set(status: status, data: data)
      var limits = WebsiteConfigBackgroundResource.Limits(); limits.encodedBytes = 3
      let ready = try await f.coordinator.prepareResources(for: ticket, from: f.settings, remoteReader: reader, backgroundLimits: limits)
      guard case .failed(let failure) = ready.background.state else { return XCTFail("Failure was presented as no image") }
      XCTAssertEqual(failure, reason)
    }
    let ready = try await f.coordinator.prepareResources(for: ticket, from: f.settings, remoteReader: reader)
    let publication = try success(f.coordinator.commit(ready))
    XCTAssertEqual(publication.background?.source, .remote(ticket.draft.pagePreferences.backgroundAddress))
    XCTAssertEqual(try f.register.read().state, .available(publication.draft.projection.runtime))
  }

  func testActualHTTPModelProducerPreparesImageAndCommitsItsUnchangedAddress() async throws {
    let f = try Fixture(); defer { f.close() }
    let image = try png()
    let configuration = CustomBackgroundDownload.configuration(); configuration.protocolClasses = [BackgroundBytesProtocol.self]
    let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
    BackgroundBytesProtocol.fixture.set(status: 200, data: image)
    let reader = WebsiteConfigBackgroundRemoteReader { try await CustomBackgroundDownload.data(from: $0, maximumBytes: $1, session: session) }
    let ticket = try f.coordinator.prepare(#"{"customBackground":"https://background-test.invalid/owned.png?variant=1"}"#)
    let ready = try await f.coordinator.prepareResources(for: ticket, from: f.settings, remoteReader: reader)
    guard case .ready(let background) = ready.background.state else { return XCTFail("Actual remote bytes were not prepared") }
    XCTAssertEqual(background.encodedData, image)
    let publication = try success(f.coordinator.commit(ready))
    XCTAssertEqual(publication.background?.source, .remote(ticket.draft.pagePreferences.backgroundAddress))
    XCTAssertEqual(try f.register.read().state, .available(publication.draft.projection.runtime))
  }
}
