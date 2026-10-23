import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Typebar

@MainActor
final class WebsiteConfigBackgroundPlayerTests: XCTestCase {
  private final class Clock {
    var time = 0.0
    var delays: [Double] = []
    var pending: [CheckedContinuation<Void, Error>] = []
    func sleep(_ delay: Double) async throws {
      delays.append(delay)
      try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func wake(_ index: Int = 0) { pending.remove(at: index).resume() }
    func drain() { let old = pending; pending = []; for item in old { item.resume() } }
  }
  private func settle() async { for _ in 0..<40 { await Task.yield() } }
  private func playback(loop: Int = 0, duration: Double = 0.125,
    color: [UInt8] = [255, 0, 0, 255], still: Bool = false) throws -> WebsiteConfigBackgroundPlayback {
    let image = try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: .init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: Data(color) as CFData)!, decode: nil,
      shouldInterpolate: false, intent: .defaultIntent))
    let frame = WebsiteConfigBackgroundResource.Frame(image: image, properties:
      [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: duration]] as CFDictionary)
    return try .init(image: .init(encodedData: Data(), type: UTType.gif.identifier,
      properties: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loop]] as CFDictionary,
      frames: still ? [frame] : [frame, frame]))
  }

  func testStartPublishesImmediatelyAndLateWakeSkipsExpiredFrames() async throws {
    let clock = Clock()
    let player = WebsiteConfigBackgroundPlayer(now: { clock.time }, sleep: { try await clock.sleep($0) })
    defer { player.stop(); clock.drain() }
    var indices: [Int] = []
    player.start(try playback(), present: { indices.append($0.frameIndex) })
    XCTAssertEqual(indices, [0]); XCTAssertEqual(player.state, .playing)
    await settle()
    XCTAssertEqual(clock.delays, [0.125])
    guard !clock.pending.isEmpty else { return XCTFail("No native task wait") }
    clock.time = 0.425; clock.wake(); await settle()
    XCTAssertEqual(indices, [0, 1], "No replay of expired intermediate frames")
    XCTAssertEqual(try XCTUnwrap(clock.delays.last), 0.075, accuracy: 1e-12)
  }

  func testEarlyWakeDoesNotRepublishOrRestartClock() async throws {
    let clock = Clock()
    let player = WebsiteConfigBackgroundPlayer(now: { clock.time }, sleep: { try await clock.sleep($0) })
    defer { player.stop(); clock.drain() }
    var indices: [Int] = []
    player.start(try playback(), present: { indices.append($0.frameIndex) })
    await settle()
    guard !clock.pending.isEmpty else { return XCTFail("No wait") }
    clock.time = 0.025; clock.wake(); await settle()
    XCTAssertEqual(indices, [0])
    XCTAssertEqual(try XCTUnwrap(clock.delays.last), 0.1, accuracy: 1e-12)
    guard !clock.pending.isEmpty else { return XCTFail("No rearmed wait") }
    clock.time = 0.125; clock.wake(); await settle()
    XCTAssertEqual(indices, [0, 1])
  }

  func testPresentationCostAndTaskQueueDelayAreSubtractedBeforeWaiting() async throws {
    for consumedInCallback in [true, false] {
      let clock = Clock()
      let player = WebsiteConfigBackgroundPlayer(now: { clock.time }, sleep: { try await clock.sleep($0) })
      var deliveries = 0
      player.start(try playback(), present: { _ in
        deliveries += 1
        if consumedInCallback { clock.time = 0.05 }
      })
      // The wait Task has not entered yet; simulate time consumed by its actor queue.
      if !consumedInCallback { clock.time = 0.05 }
      await settle()
      XCTAssertEqual(deliveries, 1)
      XCTAssertEqual(try XCTUnwrap(clock.delays.first), 0.075, accuracy: 1e-12)
      player.stop(); clock.drain(); await settle()
    }
  }

  func testPauseFreezesElapsedAndResumeRetainsRemainingFrameTime() async throws {
    let clock = Clock()
    let player = WebsiteConfigBackgroundPlayer(now: { clock.time }, sleep: { try await clock.sleep($0) })
    defer { player.stop(); clock.drain() }
    var indices: [Int] = []
    player.start(try playback(), present: { indices.append($0.frameIndex) })
    await settle()
    clock.time = 0.05; player.pause()
    XCTAssertEqual(player.state, .paused)
    let waits = clock.delays.count
    clock.time = 100; clock.drain(); await settle()
    XCTAssertEqual(indices, [0]); XCTAssertEqual(clock.delays.count, waits)
    player.resume(); await settle()
    XCTAssertEqual(player.state, .playing)
    XCTAssertEqual(indices, [0])
    XCTAssertEqual(try XCTUnwrap(clock.delays.last), 0.075, accuracy: 1e-12)
    guard !clock.pending.isEmpty else { return XCTFail("No resumed wait") }
    clock.time = 100.08; clock.wake(); await settle()
    XCTAssertEqual(indices, [0, 1])
  }

  func testReplacementAndStopRejectAnOldSleeperThatIgnoresCancellation() async throws {
    let clock = Clock()
    let player = WebsiteConfigBackgroundPlayer(now: { clock.time }, sleep: { try await clock.sleep($0) })
    defer { player.stop(); clock.drain() }
    var old: [Int] = [], new: [Int] = []
    player.start(try playback(), present: { old.append($0.frameIndex) })
    await settle()
    clock.time = 10
    let replacement = try playback(color: [0, 0, 255, 255])
    player.start(replacement, present: { new.append($0.frameIndex) })
    await settle()
    XCTAssertEqual(clock.pending.count, 2)
    guard clock.pending.count == 2 else { return XCTFail("Both independently suspended tasks required") }
    clock.time = 10.13; clock.wake(0); await settle()
    XCTAssertEqual(old, [0]); XCTAssertEqual(new, [0])
    XCTAssertTrue(player.currentSample?.frame.image === replacement.image.frames[0].image)
    player.stop(); clock.drain(); await settle()
    XCTAssertEqual(player.state, .stopped); XCTAssertNil(player.currentSample)
    XCTAssertEqual(new, [0]); XCTAssertEqual(clock.delays.count, 2)
  }

  func testPresentationCanReplaceOrStopReentrantlyWithoutOldRearming() async throws {
    let clock = Clock()
    let player = WebsiteConfigBackgroundPlayer(now: { clock.time }, sleep: { try await clock.sleep($0) })
    defer { player.stop(); clock.drain() }
    let next = try playback(still: true)
    var old = 0, new = 0
    player.start(try playback(), present: { _ in
      old += 1
      player.start(next, present: { _ in new += 1 })
    })
    await settle()
    XCTAssertEqual(old, 1); XCTAssertEqual(new, 1)
    XCTAssertEqual(player.state, .finished); XCTAssertTrue(clock.delays.isEmpty)
    player.start(try playback(), present: { _ in player.stop() })
    await settle()
    XCTAssertEqual(player.state, .stopped); XCTAssertTrue(clock.delays.isEmpty)
  }

  func testFiniteAndStillPlaybackFinishWithoutAnotherWait() async throws {
    let clock = Clock()
    let player = WebsiteConfigBackgroundPlayer(now: { clock.time }, sleep: { try await clock.sleep($0) })
    defer { player.stop(); clock.drain() }
    var indices: [Int] = []
    player.start(try playback(loop: 1), present: { indices.append($0.frameIndex) })
    await settle()
    guard !clock.pending.isEmpty else { return XCTFail("No wait") }
    clock.time = 0.125; clock.wake(); await settle()
    XCTAssertEqual(indices, [0, 1]); XCTAssertEqual(player.state, .finished)
    XCTAssertEqual(clock.delays.count, 1); XCTAssertTrue(clock.pending.isEmpty)
    player.pause(); player.resume(); await settle()
    XCTAssertEqual(indices, [0, 1]); XCTAssertEqual(clock.delays.count, 1)
    player.start(try playback(still: true), present: { indices.append($0.frameIndex) })
    await settle()
    XCTAssertEqual(indices, [0, 1, 0]); XCTAssertEqual(player.state, .finished)
    XCTAssertEqual(clock.delays.count, 1)
  }

  func testInvalidClockAndWaitFailureRetireOnlyTheirCurrentRun() async throws {
    let clock = Clock()
    let player = WebsiteConfigBackgroundPlayer(now: { clock.time }, sleep: { try await clock.sleep($0) })
    defer { player.stop(); clock.drain() }
    var failures: [WebsiteConfigBackgroundPlayer.Failure] = []
    player.start(try playback(), present: { _ in }, failed: { failures.append($0) })
    await settle()
    guard !clock.pending.isEmpty else { return XCTFail("No wait") }
    clock.time = -1; clock.wake(); await settle()
    XCTAssertEqual(failures, [.invalidClock]); XCTAssertEqual(player.state, .failed)
    clock.time = 0
    player.start(try playback(), present: { _ in }, failed: { failures.append($0) })
    await settle()
    guard !clock.pending.isEmpty else { return XCTFail("No wait") }
    clock.pending.removeFirst().resume(throwing: CocoaError(.fileReadUnknown)); await settle()
    XCTAssertEqual(failures, [.invalidClock, .waitFailed]); XCTAssertEqual(player.state, .failed)
    clock.time = .nan
    player.start(try playback(), present: { _ in XCTFail("Invalid clock published") }, failed: { failures.append($0) })
    XCTAssertEqual(failures.last, .invalidClock); XCTAssertEqual(player.state, .failed)
  }

  func testLongWaitIsBoundedAndTaskDoesNotRetainPlayer() async throws {
    let clock = Clock()
    var player: WebsiteConfigBackgroundPlayer? = .init(now: { clock.time }, sleep: { try await clock.sleep($0) })
    weak let released = player
    var deliveries = 0
    player?.start(try playback(duration: 1000), present: { _ in deliveries += 1 })
    await settle()
    XCTAssertEqual(clock.delays, [60])
    guard !clock.pending.isEmpty else { return XCTFail("No bounded wait") }
    clock.time = 60; clock.wake(); await settle()
    XCTAssertEqual(clock.delays, [60, 60]); XCTAssertEqual(deliveries, 1)
    player = nil
    XCTAssertNil(released)
    clock.drain(); await settle()
    XCTAssertEqual(deliveries, 1)
  }

  func testUncancelledCancellationErrorReportsFailureBeforeReentrantReplacement() async throws {
    let clock = Clock()
    let player = WebsiteConfigBackgroundPlayer(now: { clock.time }, sleep: { try await clock.sleep($0) })
    defer { player.stop(); clock.drain() }
    let replacement = try playback(still: true)
    var failures: [WebsiteConfigBackgroundPlayer.Failure] = [], replacements = 0
    player.start(try playback(), present: { _ in }, failed: { error in
      failures.append(error)
      player.start(replacement, present: { _ in replacements += 1 })
    })
    await settle()
    guard !clock.pending.isEmpty else { return XCTFail("No wait") }
    clock.pending.removeFirst().resume(throwing: CancellationError()); await settle()
    XCTAssertEqual(failures, [.waitFailed]); XCTAssertEqual(replacements, 1)
    XCTAssertEqual(player.state, .finished); XCTAssertNil(player.failure)
    XCTAssertTrue(player.currentSample?.frame.image === replacement.image.frames[0].image)
    XCTAssertEqual(clock.delays.count, 1)
  }

  func testInjectedClockReentryCannotOverwriteANewerPlayback() async throws {
    let clock = Clock()
    var onRead: (() -> Void)?
    var player: WebsiteConfigBackgroundPlayer!
    player = .init(now: {
      let callback = onRead; onRead = nil; callback?()
      return clock.time
    }, sleep: { try await clock.sleep($0) })
    defer { player.stop(); clock.drain() }
    let replacement = try playback(still: true)
    var old = 0, new = 0
    onRead = { player.start(replacement, present: { _ in new += 1 }) }
    player.start(try playback(), present: { _ in old += 1 })
    await settle()
    XCTAssertEqual(old, 0); XCTAssertEqual(new, 1)
    XCTAssertEqual(player.state, .finished); XCTAssertTrue(clock.delays.isEmpty)
  }

  func testRealContinuousClockTaskDeliversAndStopsWithoutAWindow() async throws {
    let player = WebsiteConfigBackgroundPlayer()
    defer { player.stop() }
    let delivered = expectation(description: "Actual native sleep delivered final frame")
    var indices: [Int] = []
    let first = try playback(duration: 0.02, still: true).image.frames[0]
    let second = try playback(duration: 0.02, color: [0, 0, 255, 255], still: true).image.frames[0]
    let source = WebsiteConfigBackgroundResource.Image(encodedData: Data(), type: UTType.gif.identifier,
      properties: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 1]] as CFDictionary,
      frames: [first, second])
    let renderer = WebsiteConfigBackgroundRasterizer(useSoftwareRenderer: true)
    let box = CGRect(x: 0, y: 0, width: 1, height: 1)
    var painted: [[UInt8]] = []
    player.start(try .init(image: source), present: { sample in
      indices.append(sample.frameIndex)
      do {
        let image = try renderer.renderViewport(frame: sample.frame,
          layout: .init(imageBox: box, transform: .identity, transformedBounds: box), fit: .max,
          filter: .init(), viewport: box.size, pointsPerRem: 16, pixelsPerPoint: 1, sampling: .nearest)
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
          let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
          context.draw(image, in: box)
        }
        painted.append(bytes)
      } catch { XCTFail("Actual timer-to-viewport failed: \(error)") }
      if sample.frameIndex == 1 { delivered.fulfill() }
    })
    await fulfillment(of: [delivered], timeout: 5)
    XCTAssertEqual(indices, [0, 1]); XCTAssertEqual(player.state, .finished)
    XCTAssertEqual(painted, [[255, 0, 0, 255], [0, 0, 255, 255]])
  }
}
