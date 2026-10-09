import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class TapeNewlinePrefixTests: XCTestCase {
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)
  private func fixture(rtl: Bool = false, first: String? = nil, retained: Bool = false) -> (PromptRendering, [TapePromptWord]) {
    let parts = [first ?? (rtl ? "אבג" : "abc"), rtl ? "דהו" : "def", rtl ? "זחט" : "ghi"]
    var text = AttributedString(), offsets: [Int: Int] = [:], words: [TapePromptWord] = []
    for index in (retained ? 1 : 0)..<3 {
      let start = text.characters.count
      let string = parts[index] + (index < 2 ? "↵" : "")
      text.append(AttributedString(string))
      for character in 0..<string.count { offsets[index * 100 + character] = start + character }
      words.append(.init(index: index, glyphID: index * 100, characters: start..<(start + string.count),
        newlineCharacterOffset: index < 2 ? start + string.count - 1 : nil))
      if index < 2 { text.append(AttributedString("\n")) }
    }
    text.foregroundColor = .gray
    return (.init(text: text, glyphCharacterOffsets: offsets), words)
  }
  private func config(_ motion: PromptCaretMotionCoordinator, attempt: UUID, rtl: Bool, markers: Bool = true) -> PromptCaretNativeView.Configuration {
    var config = PromptCaretNativeView.Configuration(text: AttributedString(), mainOffset: nil, paceOffset: nil,
      mainStyle: markers ? .bar : .off, paceStyle: markers ? .outline : .off, font: font, lineSpacing: 0, rightToLeft: rtl,
      accent: .yellow, motion: .off, reducesMotion: false, frameRate: 60,
      attemptID: attempt, coordinator: motion, mainGlyphID: 100)
    config.mainPresentation = { .init(isVisible: true, isBlinking: false) }
    config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: 200) }
    return config
  }
  private func update(_ view: TapePromptNativeView, motion: PromptCaretMotionCoordinator, attempt: UUID,
    rtl: Bool = false, first: String? = nil, retained: Bool, time: TimeInterval, markers: Bool = true,
    typed: String? = nil) {
    let (rendering, words) = fixture(rtl: rtl, first: first, retained: retained)
    let offset = rendering.glyphCharacterOffsets[100]!
    var configuration = config(motion, attempt: attempt, rtl: rtl, markers: markers)
    if let typed {
      configuration.mainGlyphID = 100 + typed.count
      configuration.latestInput = { .init(attemptID: attempt, typed: typed, composition: "", glyphID: 100 + typed.count) }
    }
    view.configure(rendering: rendering, anchorCharacterIndex: offset + (typed?.count ?? 0), wordAnchorCharacterIndex: offset,
      mode: typed == nil ? .word : .letter, margin: 0.25, smoothScroll: true,
      retirement: .init(attemptID: attempt, activeWordID: 100, characterOffsets: rendering.glyphCharacterOffsets,
        smoothScroll: true, reducesMotion: false, words: words.map { .init(index: $0.index, glyphID: $0.glyphID) },
        firstRetainedWordIndex: retained ? 1 : 0), newlineWords: words,
      carets: configuration, at: time)
  }

  func testActualPrefixAcknowledgementKeepsFuturePaceXWhileItsRowRebases() throws {
    for rtl in [false, true] {
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 160))
      let motion = PromptCaretMotionCoordinator(), attempt = UUID()
      defer { view.stop() }
      update(view, motion: motion, attempt: attempt, rtl: rtl, retained: false, time: 0)
      let before = try XCTUnwrap(motion.pace.visibleRect)
      update(view, motion: motion, attempt: attempt, rtl: rtl, retained: true, time: 1)
      XCTAssertEqual(motion.pace.visibleRect, before, "Configure is not a presentation frame")
      view.present(at: 1)
      let after = try XCTUnwrap(motion.pace.visibleRect)
      XCTAssertEqual(after.minX, before.minX, accuracy: 1e-7, "Leading filler removal must also rebase retained filler origins")
      XCTAssertLessThan(after.minY, before.minY, "The retired row is no longer materialized")
      view.present(at: 1.05)
      XCTAssertEqual(try XCTUnwrap(motion.pace.visibleRect).minX, before.minX, accuracy: 1e-7)
    }
  }

  func testActualPrefixCompensationUsesPresentedCappedFillerNotFullRemovedWordWidth() {
    for rtl in [false, true] {
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 80, height: 160))
      let motion = PromptCaretMotionCoordinator(), attempt = UUID(), first = String(repeating: "amber", count: 12)
      defer { view.stop() }
      update(view, motion: motion, attempt: attempt, rtl: rtl, first: first, retained: false, time: 0)
      let before = motion.wordsTapeMargin
      XCTAssertGreaterThan(abs(before), 240)
      update(view, motion: motion, attempt: attempt, rtl: rtl, first: first, retained: true, time: 1)
      XCTAssertEqual(motion.wordsTapeMargin, before + (rtl ? -240 : 240), accuracy: 1e-7,
        "Source cleanup reads the rendered leading filler, including its cap")
    }
  }

  func testRetainedNativeFillerRebasesFromItsLastPresentedValueWithoutSampling() throws {
    for rtl in [false, true] {
      let layout = TapeNewlineTextLayout(), (original, words) = fixture(rtl: rtl)
      layout.configure(text: original.text, words: words, font: font, rightToLeft: rtl, resets: true)
      layout.request(layout.plan(at: 0, viewportWidth: 400), duration: 0, at: 0)
      let (changed, changedWords) = fixture(rtl: rtl, first: "amberviolet")
      layout.configure(text: changed.text, words: changedWords, font: font, rightToLeft: rtl, resets: false)
      layout.request(layout.plan(at: 0, viewportWidth: 400), duration: 0.125, at: 1)
      layout.sample(at: 1.04)
      func inline(_ rect: CGRect) -> CGFloat { rtl ? layout.leadingEdge - rect.maxX : rect.minX }
      let firstRetained = try XCTUnwrap(layout.wordRect(at: changedWords[1].characters.lowerBound))
      let removed = inline(firstRetained)
      let future = inline(try XCTUnwrap(layout.wordRect(at: changedWords[2].characters.lowerBound)))
      let (pruned, retained) = fixture(rtl: rtl, retained: true)
      layout.configure(text: pruned.text, words: retained, font: font, rightToLeft: rtl, resets: false)
      layout.request(layout.plan(at: 0, viewportWidth: 400), duration: 0.125, at: 1.05)
      XCTAssertEqual(inline(try XCTUnwrap(layout.wordRect(at: retained[1].characters.lowerBound))), future - removed,
        accuracy: 1e-7, "An input/configure request cannot advance either old filler tween")
      layout.sample(at: 1.163)
      let independent = TapeNewlineTextLayout()
      independent.configure(text: pruned.text, words: retained, font: font, rightToLeft: rtl, resets: true)
      independent.request(independent.plan(at: 0, viewportWidth: 400), duration: 0, at: 0)
      let expected = try XCTUnwrap(independent.wordRect(at: retained[1].characters.lowerBound))
      let expectedInline = rtl ? independent.leadingEdge - expected.maxX : expected.minX
      XCTAssertEqual(inline(try XCTUnwrap(layout.wordRect(at: retained[1].characters.lowerBound))), expectedInline, accuracy: 1e-7)
    }
  }

  func testRepeatedPrefixAcknowledgementCannotApplyTheCorrectionTwice() {
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 160))
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    defer { view.stop() }
    update(view, motion: motion, attempt: attempt, retained: false, time: 0)
    update(view, motion: motion, attempt: attempt, retained: true, time: 1)
    let words = motion.wordsTapeMargin, correction = motion.pace.cumulativeTapeCorrection
    for time in [1.01, 1.02, 1.03] { update(view, motion: motion, attempt: attempt, retained: true, time: time) }
    XCTAssertEqual(motion.wordsTapeMargin, words)
    XCTAssertEqual(motion.pace.cumulativeTapeCorrection, correction)
  }

  func testRestartClearsPendingNativePrefixCorrectionAndRetainedIndents() throws {
    let layout = TapeNewlineTextLayout(), (full, words) = fixture(), (pruned, retained) = fixture(retained: true)
    layout.configure(text: full.text, words: words, font: font, rightToLeft: false, resets: true)
    layout.request(layout.plan(at: 0, viewportWidth: 400), duration: 0, at: 0)
    layout.configure(text: pruned.text, words: retained, font: font, rightToLeft: false, resets: false)
    layout.configure(text: full.text, words: words, font: font, rightToLeft: false, resets: true)
    layout.request(layout.plan(at: 0, viewportWidth: 400), duration: 0, at: 1)
    XCTAssertEqual(try XCTUnwrap(layout.wordRect(at: words[1].characters.lowerBound)).minX,
      ("abc" as NSString).size(withAttributes: [.font: font]).width, accuracy: 1e-7)
    XCTAssertFalse(layout.isAnimating)
  }

  func testPrefixAcknowledgementAndNewLetterShareOneCorrectionAndDoNotSampleTheNewTween() {
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 160))
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    defer { view.stop() }
    update(view, motion: motion, attempt: attempt, retained: false, time: 0, typed: "")
    let correction = motion.pace.cumulativeTapeCorrection
    let removed = ("abc" as NSString).size(withAttributes: [.font: font]).width
    update(view, motion: motion, attempt: attempt, retained: true, time: 1, typed: "d")
    XCTAssertEqual(motion.wordsTapeMargin, 0, accuracy: 1e-7)
    XCTAssertEqual(motion.pace.cumulativeTapeCorrection, correction + removed, accuracy: 1e-7)
    let reference = PromptCaretMotionCoordinator()
    reference.tapeScroll(to: -("d" as NSString).size(withAttributes: [.font: font]).width, duration: 0.125, at: 1)
    for time in [1.031, 1.062, 1.113, 1.15] {
      view.present(at: time); reference.sample(at: time)
      XCTAssertEqual(motion.wordsTapeMargin, reference.wordsTapeMargin, accuracy: 1e-7)
    }
  }

  func testStopAndNewAttemptCannotKeepAnOldPrefixCompensation() {
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 160))
    let motion = PromptCaretMotionCoordinator(), old = UUID()
    defer { view.stop() }
    update(view, motion: motion, attempt: old, retained: false, time: 0)
    update(view, motion: motion, attempt: old, retained: true, time: 1)
    view.stop()
    update(view, motion: motion, attempt: UUID(), retained: false, time: 2)
    XCTAssertEqual(motion.wordsTapeMargin, -("abc" as NSString).size(withAttributes: [.font: font]).width, accuracy: 1e-7)
    let freshView = TapePromptNativeView(frame: view.frame), fresh = PromptCaretMotionCoordinator()
    defer { freshView.stop() }
    update(freshView, motion: fresh, attempt: UUID(), retained: false, time: 2)
    // Startup itself may fold a settled initial tape margin into the pace
    // correction. A restart must match an actual fresh owner, not zero.
    XCTAssertEqual(motion.pace.cumulativeTapeCorrection, fresh.pace.cumulativeTapeCorrection)
    XCTAssertEqual(motion.pace.visibleRect, fresh.pace.visibleRect)
    XCTAssertFalse(motion.isAnimatingTape)
  }

  func testActualNativePrefixPixelsArePreservedAcrossWholeRowRebasingWithoutShowingWindow() throws {
    for rtl in [false, true] {
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 160),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 160))
      view.layer?.backgroundColor = NSColor.black.cgColor; window.contentView = view
      let motion = PromptCaretMotionCoordinator(), attempt = UUID()
      defer { view.stop(); window.contentView = nil; window.close() }
      let (rendering, words) = fixture(rtl: rtl), layout = TapeNewlineTextLayout()
      layout.configure(text: rendering.text, words: words, font: font, rightToLeft: rtl, resets: true)
      var images: [NSBitmapImageRep] = []
      for retained in [false, true] {
        let time: TimeInterval = retained ? 1 : 0
        update(view, motion: motion, attempt: attempt, rtl: rtl, retained: retained, time: time, markers: false)
        view.present(at: time); view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap); images.append(bitmap)
        if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
          try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
            URL(fileURLWithPath: directory).appendingPathComponent("tape-newline-prefix-\(rtl ? "rtl" : "ltr")-\(retained ? "after" : "before").png"))
        }
      }
      let scale = CGFloat(images[0].pixelsHigh) / 160, row = Int(layout.metrics.rowHeight * scale)
      var ink = 0, differences = 0
      for y in 0..<(row * 2) { for x in 0..<images[0].pixelsWide {
        let old = try XCTUnwrap(images[0].colorAt(x: x, y: y + row)?.usingColorSpace(.deviceRGB))
        let new = try XCTUnwrap(images[1].colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        if old.redComponent + old.greenComponent + old.blueComponent > 0.2 { ink += 1 }
        if abs(old.redComponent - new.redComponent) + abs(old.greenComponent - new.greenComponent)
          + abs(old.blueComponent - new.blueComponent) > 0.01 { differences += 1 }
      } }
      XCTAssertGreaterThan(ink, 20, "An empty crop cannot prove prefix preservation")
      XCTAssertEqual(differences, 0, "Retained native rows must keep exactly the same visible pixels")
      XCTAssertFalse(window.isVisible)
    }
  }

  private func sourceFixture(changed: Bool = false, retained: Int = 0) -> (PromptRendering, [TapePromptWord]) {
    let strings = [changed ? "amberviolet" : "abc", "👩🏽‍💻é", "אבג", "jkl", "mno", "pqr"]
    var text = AttributedString(), words: [TapePromptWord] = [], offsets: [Int: Int] = [:]
    for index in retained..<strings.count {
      let start = text.characters.count, string = strings[index] + (index < 5 ? "↵" : "")
      text.append(AttributedString(string))
      words.append(.init(index: index, glyphID: index * 100, characters: start..<(start + string.count),
        newlineCharacterOffset: index < 5 ? start + string.count - 1 : nil))
      offsets[index * 100] = start
      if index < 5 { text.append(AttributedString("\n")) }
    }
    return (.init(text: text, glyphCharacterOffsets: offsets), words)
  }

  func testNativeTextKitPrefixAndFillerFramesAgainstCompletePinnedScrollTape() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"],
      ProcessInfo.processInfo.environment["TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE"] != nil else {
      throw XCTSkip("Requires fixed clean reference and locked Anime.js archive")
    }
    func metrics(_ changed: Bool) -> [[String: Any]] {
      let (rendering, words) = sourceFixture(changed: changed), layout = TapeNewlineTextLayout()
      layout.configure(text: rendering.text, words: words, font: font, rightToLeft: false, resets: true)
      return layout.wordMetrics.map { ["index": $0.index, "width": $0.width, "gap": $0.gap,
        "newlineWidth": $0.newlineWidth.map { $0 as Any } ?? NSNull()] }
    }
    struct Sample: Decodable { let milliseconds: Int; let indents: [String: Double] }
    struct Fixture: Decodable {
      let retained: Int; let rtl, smooth, running, multipleLeading: Bool
      let viewportWidth, width: Double; let samples: [Sample]
    }
    struct Output: Decodable { let pin: String; let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe(), input = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent(
      "Scripts/check-source-tape-newline-prefix.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardInput = input; try process.run()
    try input.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject:
      ["before": metrics(false), "changed": metrics(true)])); try input.fileHandleForWriting.close()
    let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw NSError(domain: "TapeNewlinePrefixProbe", code: Int(process.terminationStatus)) }
    let source = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(source.pin, "91bd24bb8513785c7364cbea29296ff7adafac41"); XCTAssertEqual(source.fixtures.count, 64)
    for (index, fixture) in source.fixtures.enumerated() {
      let layout = TapeNewlineTextLayout(), (full, words) = sourceFixture()
      layout.configure(text: full.text, words: words, font: font, rightToLeft: fixture.rtl, resets: true)
      let active = words[fixture.retained].characters.lowerBound
      layout.request(layout.plan(at: active, viewportWidth: fixture.viewportWidth), duration: 0, at: 0)
      if fixture.running {
        let (changed, descriptors) = sourceFixture(changed: true)
        layout.configure(text: changed.text, words: descriptors, font: font, rightToLeft: fixture.rtl, resets: false)
        layout.request(layout.plan(at: descriptors[fixture.retained].characters.lowerBound, viewportWidth: fixture.viewportWidth),
          duration: fixture.smooth ? 0.125 : 0, at: 1)
        for ms in 1...40 { layout.sample(at: 1 + Double(ms) / 1000) }
      }
      let (_, oldWords) = sourceFixture(changed: fixture.running)
      XCTAssertEqual(try XCTUnwrap(layout.prefixCompensation(at: oldWords[fixture.retained].characters.lowerBound)),
        fixture.width, accuracy: 1e-6, "fixture \(index): presented leading filler")
      let (pruned, retained) = sourceFixture(retained: fixture.retained)
      layout.configure(text: pruned.text, words: retained, font: font, rightToLeft: fixture.rtl, resets: false)
      layout.request(layout.plan(at: 0, viewportWidth: fixture.viewportWidth), duration: fixture.smooth ? 0.125 : 0, at: 1.05)
      for sample in fixture.samples {
        if sample.milliseconds > 0 { layout.sample(at: 1.05 + Double(sample.milliseconds) / 1000) }
        for (word, expected) in sample.indents {
          let next = try XCTUnwrap(retained.first { $0.index == Int(word)! + 1 })
          let rect = try XCTUnwrap(layout.wordRect(at: next.characters.lowerBound))
          let actual = fixture.rtl ? layout.leadingEdge - rect.maxX : rect.minX
          XCTAssertEqual(actual, expected, accuracy: 1e-6, "fixture \(index), filler \(word), \(sample.milliseconds)ms")
        }
      }
    }
  }
}
