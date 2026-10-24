import AppKit
import ImageIO
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Typebar

@MainActor
final class BackgroundViewportHostTests: XCTestCase {
  @MainActor private final class Fixture {
    let suite = "typebar.background-viewport.\(UUID())"
    let defaults: UserDefaults
    let settings: AppSettings
    let container: ModelContainer
    let host: NSHostingView<AnyView>
    let window: NSWindow

    init() throws {
      defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      settings = AppSettings(defaults: defaults,
        feedbackSound: .init(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      settings.reducePracticeMotion = true
      settings.showAllPracticeLines = true
      let configuration = TestConfiguration.words(201).with(modifiers: [.noQuit])
      XCTAssertTrue(settings.saveActiveTestSelection(.init(preset: .init(configuration: configuration),
        testParameterMemory: .legacyDefaults(configuration: configuration))))
      let image = try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: .init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: Data([255, 0, 0, 255]) as CFData)!, decode: nil,
        shouldInterpolate: false, intent: .defaultIntent))
      let output = NSMutableData()
      let encoder = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
      CGImageDestinationAddImage(encoder, image, nil)
      XCTAssertTrue(CGImageDestinationFinalize(encoder))
      try settings.importLocalBackground(data: output as Data)
      container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
        SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
      let prompt = (0..<201).map { "word\($0)" }.joined(separator: " ")
      let content = TypebarApp.practiceContent(settings: settings,
        account: AccountSession(defaults: defaults), announcements: RemoteAnnouncementCenter(defaults: defaults),
        hotkey: GlobalHotkeyMonitor(), systemKeyboardGuide: SystemKeyboardGuideMonitor(observesInputSourceChanges: false),
        network: NetworkConnectivityMonitor(), systemAppearance: SystemAppearanceMonitor(),
        wholePreviewPrepare: { configuration, _, _ in TypingSession(configuration: configuration, prompt: prompt) })
        .modelContainer(container)
      host = NSHostingView(rootView: AnyView(content))
      window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 480),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.colorSpace = .sRGB; window.contentView = host
    }

    func views<T: NSView>(_ type: T.Type, in root: NSView? = nil) -> [T] {
      let root = root ?? host
      return (root as? T).map { [$0] } ?? root.subviews.flatMap { views(type, in: $0) }
    }
    func flush() {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.02))
      host.layoutSubtreeIfNeeded()
    }
    func waitUntil(_ ready: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
      let deadline = Date().addingTimeInterval(15)
      repeat { flush() } while !ready() && Date() < deadline
      XCTAssertTrue(ready(), "Production background host did not settle", file: file, line: line)
    }
    func close() {
      host.rootView = AnyView(EmptyView()); flush()
      window.contentView = nil; window.close()
      defaults.removePersistentDomain(forName: suite)
      withExtendedLifetime(container) {}
    }
    func cornerPixel() throws -> [UInt8] {
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let image = try XCTUnwrap(bitmap.cgImage)
      var pixel = [UInt8](repeating: 0, count: 4)
      try pixel.withUnsafeMutableBytes { buffer in
        let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1,
          bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: -4, y: -4, width: image.width, height: image.height))
      }
      return pixel
    }
  }

  func testProductionBackgroundCoversViewportAndDoesNotScrollWithLongDocument() throws {
    let fixture = try Fixture()
    defer { fixture.close() }
    fixture.waitUntil {
      fixture.views(WebsiteConfigBackgroundSurfaceView.self).first?.renderedImage != nil
        && fixture.views(TypingInputView.self).first?.acceptsTextInput == true
    }
    let surface = try XCTUnwrap(fixture.views(WebsiteConfigBackgroundSurfaceView.self).first)
    let prompt = try XCTUnwrap(fixture.views(PromptFieldNativeView.self).first)
    let page = try XCTUnwrap(prompt.enclosingScrollView)
    let document = try XCTUnwrap(page.documentView)
    XCTAssertGreaterThan(document.frame.height, fixture.host.bounds.height + 100)
    XCTAssertEqual(surface.bounds.width, fixture.host.bounds.width, accuracy: 0.01)
    XCTAssertEqual(surface.bounds.height, fixture.host.bounds.height, accuracy: 0.01)
    XCTAssertNil(surface.enclosingScrollView, "A fixed background must not belong to the scrolling document")
    XCTAssertEqual(try fixture.cornerPixel(), [255, 0, 0, 255], "The scroll layer must not cover the viewport background")
    let before = surface.convert(surface.bounds, to: fixture.host)
    page.contentView.scroll(to: CGPoint(x: 0, y: 200)); page.reflectScrolledClipView(page.contentView)
    fixture.flush()
    XCTAssertGreaterThan(page.contentView.bounds.minY, 100, "The foreground really must scroll")
    XCTAssertEqual(surface.convert(surface.bounds, to: fixture.host), before)
    XCTAssertEqual(try fixture.cornerPixel(), [255, 0, 0, 255])
    XCTAssertTrue(fixture.views(WebsiteConfigBackgroundSurfaceView.self).first === surface)
    XCTAssertNil(surface.hitTest(CGPoint(x: 10, y: 10)))
    XCTAssertFalse(fixture.window.isVisible)
  }

  func testProductionViewportResizeAndRemovalKeepTheInputAndRetireTheSurface() throws {
    let fixture = try Fixture()
    defer { fixture.close() }
    fixture.waitUntil {
      fixture.views(WebsiteConfigBackgroundSurfaceView.self).first?.renderedImage != nil
        && fixture.views(TypingInputView.self).first?.acceptsTextInput == true
    }
    let surface = try XCTUnwrap(fixture.views(WebsiteConfigBackgroundSurfaceView.self).first)
    let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    let application = fixture.settings.customBackgroundApplicationID
    fixture.window.setContentSize(CGSize(width: 840, height: 560))
    fixture.waitUntil { fixture.host.bounds.size == CGSize(width: 840, height: 560) }
    XCTAssertEqual(surface.bounds.size, fixture.host.bounds.size)
    XCTAssertEqual(surface.renderedImage?.width, Int(ceil(840 * fixture.window.backingScaleFactor)))
    XCTAssertEqual(surface.renderedImage?.height, Int(ceil(560 * fixture.window.backingScaleFactor)))
    XCTAssertTrue(fixture.views(WebsiteConfigBackgroundSurfaceView.self).first === surface)
    XCTAssertEqual(fixture.settings.customBackgroundApplicationID, application)
    try fixture.settings.removeLocalBackground()
    fixture.waitUntil { fixture.views(WebsiteConfigBackgroundSurfaceView.self).isEmpty }
    XCTAssertNil(surface.renderedImage); XCTAssertEqual(surface.player.state, .stopped)
    XCTAssertTrue(fixture.views(TypingInputView.self).first === input)
    XCTAssertTrue(input.acceptsTextInput); XCTAssertFalse(fixture.window.isVisible)
  }
}
