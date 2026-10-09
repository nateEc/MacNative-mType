import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class TapeNewlineFlowTests: XCTestCase {
  private func nativeFixture() -> (AttributedString, [TapePromptWord]) {
    let strings = ["abc↵", "def", "ghi↵", "jkl↵", "mno", "pqr"]
    var text = AttributedString(), words: [TapePromptWord] = []
    for (index, string) in strings.enumerated() {
      let start = text.characters.count
      text.append(AttributedString(string))
      words.append(.init(index: index, glyphID: index * 100, characters: start..<(start + string.count),
        newlineCharacterOffset: string.hasSuffix("↵") ? start + string.count - 1 : nil))
      text.append(AttributedString(string.hasSuffix("↵") ? "\n" : " "))
    }
    text.foregroundColor = .gray
    return (text, words)
  }

  func testActualNativeWordRemovalKeepsItsReturnRowAndOtherCanonicalGlyphs() throws {
    let (text, words) = nativeFixture(), layout = TapeNewlineTextLayout()
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)
    layout.configure(text: text, words: words, font: font, rightToLeft: false, resets: true)
    let oldHeight = layout.metrics.contentHeight
    let oldY = try XCTUnwrap(layout.wordRect(at: words[2].characters.lowerBound)).minY
    let pass = try XCTUnwrap(layout.requestScroll(at: words[4].characters.lowerBound, mode: .word,
      viewportWidth: 400, duration: 0, time: 0, overflowing: { index, _ in index == 1 }))
    XCTAssertEqual(pass.removedWords, [1])
    XCTAssertNil(layout.glyphRect(at: words[1].characters.lowerBound, minimumOffset: words[1].characters.lowerBound))
    XCTAssertNotNil(layout.glyphRect(at: words[0].characters.lowerBound, minimumOffset: words[0].characters.lowerBound))
    XCTAssertEqual(layout.metrics.contentHeight, oldHeight)
    XCTAssertEqual(try XCTUnwrap(layout.wordRect(at: words[2].characters.lowerBound)).minY, oldY)
    XCTAssertEqual(try XCTUnwrap(layout.wordRect(at: words[2].characters.lowerBound)).minX,
      ("abc" as NSString).size(withAttributes: [.font: font]).width, accuracy: 1e-7)
    _ = layout.requestScroll(at: words[4].characters.lowerBound, mode: .word, viewportWidth: 400,
      duration: 0, time: 1, overflowing: { index, _ in index == 0 })
    _ = layout.requestScroll(at: words[4].characters.lowerBound, mode: .word, viewportWidth: 400,
      duration: 0, time: 2, overflowing: { _, _ in false })
    XCTAssertNil(layout.wordRect(at: words[0].characters.lowerBound))
    XCTAssertEqual(layout.metrics.contentHeight, oldHeight, "Horizontal cleanup leaves beforeNewline and newline boxes")
    XCTAssertEqual(try XCTUnwrap(layout.wordRect(at: words[2].characters.lowerBound)).minY, oldY)
    XCTAssertEqual(try XCTUnwrap(layout.wordRect(at: words[2].characters.lowerBound)).minX, 0)
    XCTAssertEqual(layout.retirementBoundary(before: 3, hideBound: oldY), 1,
      "An empty row's beforeNewline box still determines vertical retirement")
    layout.configure(text: text, words: words, font: font, rightToLeft: false, resets: true)
    XCTAssertNotNil(layout.wordRect(at: words[0].characters.lowerBound))
    XCTAssertNotNil(layout.wordRect(at: words[1].characters.lowerBound))
  }

  private func updateNative(_ view: TapePromptNativeView, _ motion: PromptCaretMotionCoordinator,
    attempt: UUID, typed: String, rtl: Bool = false, time: TimeInterval,
    vertical: @escaping (PromptWordRetirement) -> Void,
    horizontal: @escaping (PromptTapeWordRemoval) -> Void) {
    let (text, words) = nativeFixture()
    var offsets: [Int: Int] = [:]
    for word in words { for (position, offset) in word.characters.enumerated() { offsets[word.glyphID + position] = offset } }
    let glyph = 400 + typed.count
    var config = PromptCaretNativeView.Configuration(text: text, mainOffset: nil, paceOffset: nil,
      mainStyle: .off, paceStyle: .off, font: .monospacedSystemFont(ofSize: 28, weight: .medium),
      lineSpacing: 0, rightToLeft: rtl, accent: .yellow, motion: .off, reducesMotion: false,
      frameRate: 60, attemptID: attempt, coordinator: motion, mainGlyphID: glyph)
    config.latestInput = { .init(attemptID: attempt, typed: typed, composition: "", glyphID: glyph) }
    view.configure(rendering: .init(text: text, glyphCharacterOffsets: offsets),
      anchorCharacterIndex: offsets[glyph]!, wordAnchorCharacterIndex: offsets[400]!, mode: .letter,
      margin: 0.25, smoothScroll: false,
      retirement: .init(attemptID: attempt, activeWordID: 400, characterOffsets: offsets,
        smoothScroll: false, reducesMotion: false, words: words.map { .init(index: $0.index, glyphID: $0.glyphID) },
        onRetire: vertical), newlineWords: words, onTapeWordsRemoved: horizontal, carets: config, at: time)
  }

  func testActualViewReportsHorizontalIdentitiesWithoutPublishingAVerticalPrefixOrCollapsingRows() {
    for rtl in [false, true] {
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 80, height: 160))
      let motion = PromptCaretMotionCoordinator(), attempt = UUID()
      var vertical: [PromptWordRetirement] = [], horizontal: [PromptTapeWordRemoval] = []
      defer { view.stop() }
      updateNative(view, motion, attempt: attempt, typed: "", rtl: rtl, time: 0,
        vertical: { vertical.append($0) }, horizontal: { horizontal.append($0) })
      let height = view.subviews[0].frame.height
      updateNative(view, motion, attempt: attempt, typed: "m", rtl: rtl, time: 1,
        vertical: { vertical.append($0) }, horizontal: { horizontal.append($0) })
      XCTAssertTrue(horizontal.isEmpty, "Native configure cannot mutate a SwiftUI session synchronously")
      view.present(at: 1); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
      XCTAssertEqual(horizontal, [.init(attemptID: attempt, wordIndices: [0, 1, 2])])
      XCTAssertTrue(vertical.isEmpty)
      XCTAssertEqual(view.subviews[0].frame.height, height)
      let x = motion.wordsTapeMargin, correction = motion.pace.cumulativeTapeCorrection
      for time in [1.01, 1.02] {
        updateNative(view, motion, attempt: attempt, typed: "m", rtl: rtl, time: time,
          vertical: { vertical.append($0) }, horizontal: { horizontal.append($0) })
      }
      view.present(at: 1.02); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
      XCTAssertEqual(horizontal.count, 1)
      XCTAssertEqual(motion.wordsTapeMargin, x)
      XCTAssertEqual(motion.pace.cumulativeTapeCorrection, correction)
      XCTAssertEqual(view.subviews[0].frame.height, height)
    }
  }

  func testStopAndNewAttemptInvalidateQueuedHorizontalWordRemovalAndItsTopology() {
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 80, height: 160))
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    var horizontal: [PromptTapeWordRemoval] = []
    defer { view.stop() }
    updateNative(view, motion, attempt: attempt, typed: "", time: 0, vertical: { _ in }, horizontal: { horizontal.append($0) })
    let fresh = motion.wordsTapeMargin
    updateNative(view, motion, attempt: attempt, typed: "m", time: 1, vertical: { _ in }, horizontal: { horizontal.append($0) })
    view.stop()
    updateNative(view, motion, attempt: UUID(), typed: "", time: 2, vertical: { _ in }, horizontal: { horizontal.append($0) })
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
    XCTAssertTrue(horizontal.isEmpty)
    XCTAssertEqual(motion.wordsTapeMargin, fresh)
  }

  func testActualHorizontalHolesAndRefreshKeepNonemptyNativePixelsWithoutShowingWindow() throws {
    for rtl in [false, true] {
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 80, height: 160),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 80, height: 160))
      window.contentView = view; view.layer?.backgroundColor = NSColor.black.cgColor
      let motion = PromptCaretMotionCoordinator(), attempt = UUID()
      defer { view.stop(); window.contentView = nil; window.close() }
      updateNative(view, motion, attempt: attempt, typed: "", rtl: rtl, time: 0, vertical: { _ in }, horizontal: { _ in })
      updateNative(view, motion, attempt: attempt, typed: "m", rtl: rtl, time: 1, vertical: { _ in }, horizontal: { _ in })
      var images: [NSBitmapImageRep] = []
      for stage in ["retired", "refresh"] {
        if stage == "refresh" {
          updateNative(view, motion, attempt: attempt, typed: "m", rtl: rtl, time: 1, vertical: { _ in }, horizontal: { _ in })
        }
        view.present(at: 1); view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap); images.append(bitmap)
        if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
          try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
            URL(fileURLWithPath: directory).appendingPathComponent("tape-newline-overflow-\(rtl ? "rtl" : "ltr")-\(stage).png"))
        }
      }
      var ink = 0, differences = 0
      for y in 0..<images[0].pixelsHigh { for x in 0..<images[0].pixelsWide {
        let before = try XCTUnwrap(images[0].colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        let after = try XCTUnwrap(images[1].colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        if before.redComponent + before.greenComponent + before.blueComponent > 0.2 { ink += 1 }
        if abs(before.redComponent - after.redComponent) + abs(before.greenComponent - after.greenComponent)
          + abs(before.blueComponent - after.blueComponent) > 0.01 { differences += 1 }
      } }
      XCTAssertGreaterThan(ink, 20)
      XCTAssertEqual(differences, 0)
      XCTAssertFalse(window.isVisible)
    }
  }

  func testHorizontalRemovalKeepsStructuralRowsAndNonPrefixHolesAcrossRequests() throws {
    let words: [TapeNewlineWordMetric] = [
      .init(index: 0, width: 48, gap: 12, newlineWidth: 12),
      .init(index: 1, width: 36, gap: 12),
      .init(index: 2, width: 24, gap: 12, newlineWidth: 12),
      .init(index: 3, width: 48, gap: 12, newlineWidth: 12),
      .init(index: 4, width: 36, gap: 12), .init(index: 5, width: 48, gap: 12)]
    var flow = TapeNewlineFlow()
    flow.configure(words: words, resets: true)
    let first = try XCTUnwrap(flow.scroll(active: 4, viewportWidth: 400,
      overflowing: { $0 == 1 }, fillerMargin: { _ in 0 }))
    XCTAssertEqual(first.removedWords, [1])
    XCTAssertEqual(first.compensation, 48)
    XCTAssertEqual(flow.nodes.filter { $0.kind == .newline }.count, 3)
    XCTAssertTrue(flow.nodes.contains(.init(kind: .word, index: 0)))
    XCTAssertFalse(flow.nodes.contains(.init(kind: .word, index: 1)))
    flow.configure(words: words, resets: false)
    XCTAssertFalse(flow.nodes.contains(.init(kind: .word, index: 1)), "A render rebuild cannot restore a removed box")
    flow.configure(words: words, resets: true)
    XCTAssertTrue(flow.nodes.contains(.init(kind: .word, index: 1)))
  }

  func testPersistentNativeTopologyAndFillersAgainstTwoCompletePinnedScrollRequests() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"],
      ProcessInfo.processInfo.environment["TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE"] != nil else {
      throw XCTSkip("Requires pinned reference and locked Anime.js archive")
    }
    struct Word: Decodable { let index: Int; let width, gap: Double; let newlineWidth: Double? }
    struct Node: Decodable { let kind: TapeNewlineFlow.Node.Kind; let index: Int }
    struct Sample: Decodable { let milliseconds: Int; let indents: [String: Double] }
    struct Pass: Decodable {
      let removed, nodes: [Node]; let corrections: [Double]; let target: Double; let samples: [Sample]
    }
    struct Fixture: Decodable {
      let rtl, smooth: Bool; let overflow: [Int]; let viewportWidth: Double; let active: Int
      let words: [Word]; let passes: [Pass]
    }
    struct Evidence: Decodable { let pin: String; let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent(
      "Scripts/check-source-tape-newline-overflow.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw NSError(domain: "TapeNewlineOverflowProbe", code: Int(process.terminationStatus)) }
    let evidence = try JSONDecoder().decode(Evidence.self, from: data)
    XCTAssertEqual(evidence.pin, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(evidence.fixtures.count, 120)
    for (index, fixture) in evidence.fixtures.enumerated() {
      var flow = TapeNewlineFlow(), channels: [Int: PromptCaretChannel] = [:]
      flow.configure(words: fixture.words.map { .init(index: $0.index, width: $0.width,
        gap: $0.gap, newlineWidth: $0.newlineWidth.map { CGFloat($0) }) }, resets: true)
      for word in fixture.words where word.newlineWidth != nil { channels[word.index] = .init() }
      for (request, source) in fixture.passes.enumerated() {
        let start = Double(request) * 0.150, label = "fixture \(index), request \(request)"
        let pass = try XCTUnwrap(flow.scroll(active: fixture.active, viewportWidth: fixture.viewportWidth,
          overflowing: { fixture.overflow.contains($0) }, fillerMargin: { channels[$0]?.tapeMargin ?? 0 }))
        XCTAssertEqual(pass.beforeActive * (fixture.rtl ? 1 : -1), source.target, accuracy: 1e-7, label)
        XCTAssertEqual(pass.compensation * (fixture.rtl ? -1 : 1), source.corrections.first ?? 0, accuracy: 1e-7, label)
        XCTAssertEqual(pass.removedWords, Set(source.removed.filter { $0.kind == .word }.map(\.index)), label)
        XCTAssertEqual(flow.nodes, source.nodes.map { .init(kind: $0.kind, index: $0.index) }, label)
        let survivingFillers = Set(flow.nodes.filter { $0.kind == .afterNewline }.map(\.index))
        channels = channels.filter { survivingFillers.contains($0.key) }
        for (filler, target) in pass.indents {
          var channel = channels[filler] ?? .init()
          channel.shiftTapeOrigin(by: -(pass.fillerCorrections[filler] ?? 0))
          channel.tapeScroll(to: target, at: start, duration: fixture.smooth ? 0.125 : 0)
          channels[filler] = channel
        }
        for sample in source.samples {
          if sample.milliseconds > 0 {
            for key in Array(channels.keys) { channels[key]?.sample(at: start + Double(sample.milliseconds) / 1000) }
          }
          for (filler, expected) in sample.indents {
            XCTAssertEqual(try XCTUnwrap(channels[Int(filler)!]?.tapeMargin), expected, accuracy: 1e-7,
              "\(label), filler \(filler) @\(sample.milliseconds)ms")
          }
        }
      }
    }
  }
}
