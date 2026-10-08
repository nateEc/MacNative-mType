import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class ASLPromptCaretTests: XCTestCase {
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)

  private func configuration(_ coordinator: PromptCaretMotionCoordinator = .init(),
    mainID: Int? = 23, mainStyle: TypingCaretStyle = .bar, paceStyle: TypingCaretStyle = .outline
  ) -> PromptCaretNativeView.Configuration {
    .init(text: AttributedString(), mainOffset: nil, paceOffset: nil,
      mainStyle: mainStyle, paceStyle: paceStyle, font: font, lineSpacing: 12,
      rightToLeft: false, accent: .blue, motion: .off, reducesMotion: false,
      frameRate: 60, attemptID: UUID(), coordinator: coordinator, mainGlyphID: mainID,
      automaticallyPresents: false)
  }

  private func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
    (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
  }

  private func mounted(_ prompt: ASLPracticePrompt, width: CGFloat = 280)
    -> (NSWindow, NSHostingView<ASLPracticePrompt>) {
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: 220),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    let host = NSHostingView(rootView: prompt)
    host.frame = .init(x: 0, y: 0, width: width, height: 220)
    host.wantsLayer = true; host.layer?.backgroundColor = NSColor.white.cgColor
    window.contentView = host
    settle(host)
    return (window, host)
  }

  private func settle(_ host: NSView) {
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    host.layoutSubtreeIfNeeded()
  }

  private func capture(_ host: NSView, name: String) throws -> Data {
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
      try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }
    return png
  }

  private func rendering(_ text: String, ids: [Int], colors: [Color]) -> PromptRendering {
    var result = AttributedString(), offsets: [Int: Int] = [:]
    for (index, character) in text.enumerated() {
      offsets[ids[index]] = result.characters.count
      var value = AttributedString(String(character)); value.foregroundColor = colors[index % colors.count]
      result += value
    }
    return .init(text: result, glyphCharacterOffsets: offsets)
  }

  func testCurrentHandDoesNotEmbedAFakeCaretInItsInkOrBackground() throws {
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 100, height: 70),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    defer { window.contentView = nil; window.close() }
    var pixels: [Data] = []
    for state: TypingPromptCharacterState in [.current, .pending] {
      let content = ASLPracticePrompt(glyphs: [.init(character: "A", state: state)], fontSize: 28, accent: .blue)
        .frame(width: 100, height: 70, alignment: .topLeading).background(Color.white)
      let host = NSHostingView(rootView: content)
      host.frame = .init(x: 0, y: 0, width: 100, height: 70); window.contentView = host
      host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.04))
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      pixels.append(try XCTUnwrap(bitmap.tiffRepresentation))
      XCTAssertFalse(window.isVisible); window.contentView = nil
    }
    XCTAssertEqual(pixels[0], pixels[1], "Only the independent caret may identify the current position")
  }

  func testProductionASLConsumesSharedRenderingAndItsOwnActualLayoutCarets() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let branch = try XCTUnwrap(app.range(of: "if practiceVisualEffect.usesASL {"))
    let end = try XCTUnwrap(app.range(of: "} else if practiceVisualEffect.usesChoo {", range: branch.upperBound..<app.endIndex))
    let asl = String(app[branch.upperBound..<end.lowerBound])
    XCTAssertTrue(asl.contains("rendering: rendering"), "ASL must not bypass the selected theme/highlight/text presentation")
    XCTAssertTrue(asl.contains("carets: specialPromptCaretConfiguration"), "ASL needs independent main and pace carets")
    XCTAssertTrue(asl.contains("glyphIDs: specialPromptGlyphIDs"), "Actual cell bounds must map to canonical IDs, not text offsets")
  }

  func testFinalSharedAttributesOverrideLegacyStateAndTypedReplacement() throws {
    let glyphs: [TypingPromptGlyph] = [.init(character: "A", state: .current),
      .init(character: "B", state: .incorrect, typedCharacter: "7"), .init(character: "C", state: .correct)]
    let ids = [5, 23, 11]
    let result = ASLPromptGlyphContent.make(glyphs: glyphs, ids: ids,
      rendering: rendering("AB•", ids: ids, colors: [.purple, .orange, .clear]))
    XCTAssertEqual(result.map { String($0.text.characters) }, ["A", "B", "•"])
    XCTAssertEqual(result.map { $0.text.foregroundColor }, [.purple, .orange, .clear])
    // The shared typo policy can choose the target B, not the mistaken 7.
    XCTAssertEqual(result[1].text.characters.first, "B")
  }

  func testUnicodeCompositionHintAndUnderlineAttributesAreNotFlattened() throws {
    var main = AttributedString("é🙂"); main.foregroundColor = .green
    main.underlineStyle = .single; main.appKit.underlineColor = .magenta
    var hint = AttributedString("x"); hint.baselineOffset = -12; hint.foregroundColor = .red
    let contents = ASLPromptGlyphContent.make(glyphs: [.init(character: "A", state: .incorrect)], ids: [23],
      rendering: .init(text: main + hint, glyphCharacterOffsets: [23: 0]))
    XCTAssertEqual(String(contents[0].main.characters), "é🙂")
    XCTAssertEqual(contents[0].main.foregroundColor, .green)
    XCTAssertNotNil(contents[0].main.underlineStyle)
    XCTAssertEqual(contents[0].main.appKit.underlineColor, .magenta)
    XCTAssertEqual(String(try XCTUnwrap(contents[0].hint).characters), "x")
  }

  func testSharedPlanSlicesByCanonicalIDsAndCharacterOffsetsNotUnicodeBytes() {
    let ids = [42, 5, 99], glyphs = "abc".map { TypingPromptGlyph(character: $0, state: .pending) }
    let result = ASLPromptGlyphContent.make(glyphs: glyphs, ids: ids,
      rendering: .init(text: AttributedString("a\u{301}🙂z"), glyphCharacterOffsets: [42: 0, 5: 1, 99: 2]))
    XCTAssertEqual(result.map { String($0.text.characters) }, ["a\u{301}", "🙂", "z"])
  }

  func testLongSharedPlanBuildsEveryRangeWithoutPerCellWholePromptSearch() {
    let count = 10_000, ids = Array(0..<count)
    let glyphs = Array(repeating: TypingPromptGlyph(character: "a", state: .pending), count: count)
    let start = ProcessInfo.processInfo.systemUptime
    let result = ASLPromptGlyphContent.make(glyphs: glyphs, ids: ids,
      rendering: .init(text: AttributedString(String(repeating: "a", count: count)),
        glyphCharacterOffsets: Dictionary(uniqueKeysWithValues: ids.map { ($0, $0) })))
    XCTAssertEqual(result.count, count)
    XCTAssertTrue(result.allSatisfy { String($0.text.characters) == "a" })
    print("ASL 10000 shared cell ranges: \(ProcessInfo.processInfo.systemUptime - start) seconds (no GUI)")
  }

  func testMountedASLHandBoundsDriveCanonicalMainAndIndependentPace() throws {
    let ids = [5, 23, 11], glyphs = "a7z".map { TypingPromptGlyph(character: $0, state: .pending) }
    let coordinator = PromptCaretMotionCoordinator()
    var config = configuration(coordinator)
    config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: 11) }
    let (window, host) = mounted(.init(glyphs: glyphs, fontSize: 28, accent: .yellow,
      glyphIDs: ids, rendering: rendering("a7z", ids: ids, colors: [.gray]), carets: config))
    defer { window.contentView = nil; window.close() }
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let child = try XCTUnwrap(descendants(host, PromptCaretNativeView.self).first)
    child.layout(); child.present(at: 0)
    XCTAssertEqual(descendants(host, PromptCaretNativeView.self).count, 1)
    let standalone = NSHostingView(rootView: ASLHandshapeGlyph(character: "a", color: .gray, background: .clear, size: 28))
    XCTAssertEqual(try XCTUnwrap(container.rect(for: 5)).size, standalone.fittingSize,
      "SwiftUI rounds the real cell to 29×31; do not substitute the unrounded 28.56-point proposal")
    XCTAssertEqual(coordinator.main.position, container.rect(for: 23))
    XCTAssertEqual(coordinator.pace.position, container.rect(for: 11))
    XCTAssertNotEqual(coordinator.main.position, coordinator.pace.position)
    XCTAssertNil(container.rect(for: 1), "Canonical IDs must never be guessed from TextKit offsets")
    XCTAssertFalse(window.isVisible)
  }

  func testActualSwiftUILayoutWrapAndResizeReanchorBothCarets() throws {
    let ids = [5, 23, 11, 42], glyphs = "abcd".map { TypingPromptGlyph(character: $0, state: .pending) }
    let coordinator = PromptCaretMotionCoordinator()
    var config = configuration(coordinator, mainID: 11)
    config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: 42) }
    let (window, host) = mounted(.init(glyphs: glyphs, fontSize: 28, accent: .yellow,
      glyphIDs: ids, carets: config))
    defer { window.contentView = nil; window.close() }
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let child = try XCTUnwrap(descendants(host, PromptCaretNativeView.self).first)
    child.layout(); child.present(at: 0)
    let old = try XCTUnwrap(coordinator.main.position)
    host.setFrameSize(.init(width: 60, height: 220)); settle(host)
    child.layout(); child.present(at: 0.1)
    let new = try XCTUnwrap(coordinator.main.position)
    XCTAssertGreaterThan(new.minY, old.minY)
    XCTAssertEqual(new, container.rect(for: 11)); XCTAssertEqual(coordinator.pace.position, container.rect(for: 42))
    XCTAssertEqual(descendants(host, PromptCaretNativeView.self).count, 1)
    _ = try capture(host, name: "asl-caret-wrapped")
    XCTAssertFalse(window.isVisible)
  }

  func testActualZeroWidthNewlineUsesPreviousHandButHiddenInkRetainsItsOwnBox() throws {
    let ids = [5, 23, 11], glyphs: [TypingPromptGlyph] = [.init(character: "a", state: .pending),
      .init(character: "\n", state: .pending), .init(character: "z", state: .hidden)]
    let coordinator = PromptCaretMotionCoordinator()
    let (window, host) = mounted(.init(glyphs: glyphs, fontSize: 28, accent: .yellow,
      glyphIDs: ids, carets: configuration(coordinator)))
    defer { window.contentView = nil; window.close() }
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let child = try XCTUnwrap(descendants(host, PromptCaretNativeView.self).first)
    child.layout(); child.present(at: 0)
    XCTAssertEqual(coordinator.main.position, container.rect(for: 5))
    let hidden = try XCTUnwrap(container.rect(for: 11))
    let visible = try XCTUnwrap(container.rect(for: 5))
    XCTAssertEqual(hidden.width, visible.width)
    XCTAssertEqual(hidden.height, visible.height, accuracy: 1e-9)
    XCTAssertGreaterThan(hidden.minY, try XCTUnwrap(container.rect(for: 5)).minY)
    XCTAssertFalse(window.isVisible)
  }

  func testBlinkOnlyChangesMainMarkerNotHandInkOrPace() throws {
    let ids = [5, 23, 11], glyphs = "azf".map { TypingPromptGlyph(character: $0, state: .pending) }
    let coordinator = PromptCaretMotionCoordinator()
    var config = configuration(coordinator)
    config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: 11) }
    let (window, host) = mounted(.init(glyphs: glyphs, fontSize: 28, accent: .yellow,
      glyphIDs: ids, rendering: rendering("azf", ids: ids, colors: [.black, .gray, .red]), carets: config))
    defer { window.contentView = nil; window.close() }
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let child = try XCTUnwrap(descendants(host, PromptCaretNativeView.self).first)
    child.layout(); child.present(at: 0)
    let markers = descendants(child, NSHostingView<PromptCaretMarkerView>.self)
    let main = try XCTUnwrap(markers.first { $0.rootView.style == .bar })
    let pace = try XCTUnwrap(markers.first { $0.rootView.style == .outline })
    let frame = container.rect(for: 23), positions = [coordinator.main.position, coordinator.pace.position]
    let on = try capture(host, name: "asl-caret-on")
    child.present(at: 0.75)
    XCTAssertEqual(main.alphaValue, 0); XCTAssertEqual(pace.alphaValue, 1)
    XCTAssertEqual(container.rect(for: 23), frame)
    XCTAssertEqual([coordinator.main.position, coordinator.pace.position], positions)
    let off = try capture(host, name: "asl-caret-off")
    XCTAssertNotEqual(on, off)
    XCTAssertFalse(window.isVisible)
  }

  func testChangingSharedThemeAndVisibilityKeepsActualLayoutAndCaretIdentity() throws {
    let ids = [5, 23, 11], glyphs = "azf".map { TypingPromptGlyph(character: $0, state: .pending) }
    let coordinator = PromptCaretMotionCoordinator(), config = configuration(coordinator, paceStyle: .off)
    let (window, host) = mounted(.init(glyphs: glyphs, fontSize: 28, accent: .yellow,
      glyphIDs: ids, rendering: rendering("azf", ids: ids, colors: [.purple, .orange, .green]), carets: config))
    defer { window.contentView = nil; window.close() }
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let child = try XCTUnwrap(descendants(host, PromptCaretNativeView.self).first)
    child.layout(); child.present(at: 0)
    let frames = ids.map { container.rect(for: $0) }
    let themed = try capture(host, name: "asl-shared-theme")
    host.rootView = .init(glyphs: glyphs, fontSize: 28, accent: .yellow, glyphIDs: ids,
      rendering: rendering("azf", ids: ids, colors: [.clear]), carets: config)
    settle(host); child.layout(); child.present(at: 0.1)
    XCTAssertTrue(descendants(host, PromptCaretNativeView.self).first === child)
    XCTAssertEqual(ids.map { container.rect(for: $0) }, frames)
    XCTAssertEqual(coordinator.main.position, frames[1])
    let hidden = try capture(host, name: "asl-shared-hidden")
    XCTAssertNotEqual(themed, hidden)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: hidden))
    var blue = 0, otherColoredInk = 0
    for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
      if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.5 {
        let channels = [color.redComponent, color.greenComponent, color.blueComponent]
        if channels.max()! - channels.min()! > 0.12 {
          if color.blueComponent > color.redComponent + 0.1 && color.blueComponent > color.greenComponent + 0.1 { blue += 1 }
          else { otherColoredInk += 1 }
        }
      }
    } }
    XCTAssertGreaterThan(blue, 5, "The independent caret remains visible")
    XCTAssertEqual(otherColoredInk, 0, "Hidden hands must not leave any purple/orange/green ink")
    XCTAssertFalse(window.isVisible)
  }

  func testNativeBridgeRetiresWithoutRetainingContainerOrOwningAnotherTimer() {
    weak var weakView: ASLPromptCaretContainer?
    autoreleasepool {
      let parent = NSView(frame: .init(x: 0, y: 0, width: 280, height: 100))
      var view: ASLPromptCaretContainer? = ASLPromptCaretContainer(frame: parent.bounds)
      weakView = view
      parent.addSubview(view!)
      var config = configuration(); config.automaticallyPresents = true
      view?.configure(config, frames: [23: .init(x: 20, y: 0, width: 30, height: 32)], glyphIDs: [23])
      view?.removeFromSuperview(); view = nil
    }
    XCTAssertNil(weakView)
  }

  func testMissingSharedIDDoesNotRestoreARetiredOrHiddenTargetThroughLegacyFallback() {
    let glyphs = "az".map { TypingPromptGlyph(character: $0, state: .pending) }
    let content = ASLPromptGlyphContent.make(glyphs: glyphs, ids: [5, 23],
      rendering: .init(text: AttributedString("z"), glyphCharacterOffsets: [23: 0]))
    XCTAssertEqual(String(content[0].text.characters), "", "A supplied rendering owns which cells exist")
    XCTAssertEqual(String(content[1].text.characters), "z")
  }

  func testMissingActualFrameCannotBorrowAPreviousCellAsIfItWereMeasuredZeroWidth() {
    let view = ASLPromptCaretContainer(frame: .init(x: 0, y: 0, width: 200, height: 100))
    defer { view.stop() }
    view.configure(configuration(), frames: [23: .init(x: 20, y: 0, width: 30, height: 32)], glyphIDs: [5, 23, 11])
    XCTAssertNil(view.rect(for: 11), "Missing/pruned is not the same as an actual zero-width cell")
  }

  func testActualASLBoxesAgainstCompletePinnedCaretResolver() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned clean reference")
    }
    struct Position: Decodable { let left, top, width: Double }
    struct Fixture: Decodable { let style: String; let index: Int; let after: Bool; let source: Position }
    struct Output: Decodable { let pin: String; let fixtures: [Fixture] }
    let ids = [5, 23, 11], glyphs = "a\nz".map { TypingPromptGlyph(character: $0, state: .pending) }
    let (window, host) = mounted(.init(glyphs: glyphs, fontSize: 28, accent: .yellow,
      glyphIDs: ids, carets: configuration()))
    defer { window.contentView = nil; window.close() }
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let frames = try ids.map { try XCTUnwrap(container.measuredRect(for: $0)) }
    XCTAssertEqual(frames[1].width, 0)
    let metrics = frames.map { ["x": Double($0.minX), "y": Double($0.minY),
      "width": Double($0.width), "height": Double($0.height)] }
    let json = String(decoding: try JSONSerialization.data(withJSONObject: metrics), as: UTF8.self)
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-special-caret.mjs").path,
      reference, "--emit-fixtures", String(Double((" " as NSString).size(withAttributes: [.font: font]).width)), json]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    guard process.terminationStatus == 0 else { return }
    let source = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(source.pin, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(source.fixtures.count, 16)
    for fixture in source.fixtures {
      let style: TypingCaretStyle
      switch fixture.style {
      case "default": style = .bar
      case "block": style = .block
      case "outline": style = .outline
      case "underline": style = .underline
      default: XCTFail("Unexpected pinned style"); continue
      }
      let coordinator = PromptCaretMotionCoordinator()
      let view = ASLPromptCaretContainer(frame: .init(x: 0, y: 0, width: 280, height: 200))
      defer { view.stop() }
      var config = configuration(coordinator, mainStyle: .off, paceStyle: style)
      config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
        fromAfter: false, targetAfter: fixture.after, fraction: 1, targetGlyphID: ids[fixture.index]) }
      // The probe's explicit owned word origin is (13, 7), not browser layout.
      view.configure(config, frames: Dictionary(uniqueKeysWithValues: zip(ids, frames.map { $0.offsetBy(dx: 13, dy: 7) })), glyphIDs: ids)
      let child = try XCTUnwrap(descendants(view, PromptCaretNativeView.self).first)
      child.layout(); child.present(at: 0)
      let rect = try XCTUnwrap(coordinator.pace.position)
      let marker = try XCTUnwrap(descendants(child, NSHostingView<PromptCaretMarkerView>.self).first)
      if style == .bar { XCTAssertEqual(marker.frame.midX, fixture.source.left + 1, accuracy: 1e-8) }
      else {
        XCTAssertEqual(rect.minX, fixture.source.left, accuracy: 1e-8)
        XCTAssertEqual(rect.width, fixture.source.width, accuracy: 1e-8)
      }
    }
    XCTAssertFalse(window.isVisible)
  }

  func testMissingSharedCellsAreNeitherRevealedNorLaidOutBeforeRetainedText() throws {
    let ids = [5, 23, 11], glyphs = "a\nz".map { TypingPromptGlyph(character: $0, state: .pending) }
    let coordinator = PromptCaretMotionCoordinator()
    let config = configuration(coordinator, mainID: 11)
    let (window, host) = mounted(.init(glyphs: glyphs, fontSize: 28, accent: .yellow,
      glyphIDs: ids, rendering: .init(text: AttributedString("z"), glyphCharacterOffsets: [11: 0]),
      carets: config))
    defer { window.contentView = nil; window.close() }
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let child = try XCTUnwrap(descendants(host, PromptCaretNativeView.self).first)
    child.layout(); child.present(at: 0)
    XCTAssertNil(container.measuredRect(for: 5)); XCTAssertNil(container.measuredRect(for: 23))
    let retained = try XCTUnwrap(container.measuredRect(for: 11))
    host.rootView = .init(glyphs: [glyphs[2]], fontSize: 28, accent: .yellow,
      glyphIDs: [11], rendering: .init(text: AttributedString("z"), glyphCharacterOffsets: [11: 0]),
      carets: config)
    settle(host); child.layout(); child.present(at: 0.1)
    XCTAssertEqual(retained, container.measuredRect(for: 11), "Omitted cells must have exactly the standalone retained layout")
    XCTAssertEqual(coordinator.main.position, retained)
    XCTAssertFalse(window.isVisible)
  }

  func testFontSizeChangesActualHandAndFallbackTextCaretGeometry() throws {
    let ids = [5, 23, 11], glyphs = "a7z".map { TypingPromptGlyph(character: $0, state: .pending) }
    let coordinator = PromptCaretMotionCoordinator(), config = configuration(coordinator)
    let (window, host) = mounted(.init(glyphs: glyphs, fontSize: 28, accent: .yellow, glyphIDs: ids,
      carets: config, font: font))
    defer { window.contentView = nil; window.close() }
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let child = try XCTUnwrap(descendants(host, PromptCaretNativeView.self).first)
    child.layout(); child.present(at: 0)
    let oldHand = try XCTUnwrap(container.rect(for: 5)), oldText = try XCTUnwrap(coordinator.main.position)
    let largeFont = NSFont.monospacedSystemFont(ofSize: 52, weight: .regular)
    let larger = PromptCaretNativeView.Configuration(text: AttributedString(), mainOffset: nil, paceOffset: nil,
      mainStyle: .bar, paceStyle: .off, font: largeFont, lineSpacing: 12, rightToLeft: false,
      accent: .blue, motion: .off, reducesMotion: true, frameRate: 60, attemptID: config.attemptID,
      coordinator: coordinator, mainGlyphID: 23, automaticallyPresents: false)
    host.rootView = .init(glyphs: glyphs, fontSize: 52, accent: .yellow, glyphIDs: ids, carets: larger, font: largeFont)
    settle(host); child.layout(); child.present(at: 0.1)
    let newHand = try XCTUnwrap(container.rect(for: 5)), newText = try XCTUnwrap(coordinator.main.position)
    XCTAssertGreaterThan(newHand.width, oldHand.width)
    XCTAssertGreaterThan(newText.width, oldText.width)
    XCTAssertEqual(newText, container.rect(for: 23))
    XCTAssertEqual(descendants(host, PromptCaretNativeView.self).count, 1)
    XCTAssertFalse(window.isVisible)
  }

  func testMainOffKeepsActualASLPaceMarkerWithoutInventingCharacterHighlight() throws {
    let ids = [5, 23], glyphs = "az".map { TypingPromptGlyph(character: $0, state: .current) }
    let coordinator = PromptCaretMotionCoordinator()
    var config = configuration(coordinator, mainStyle: .off, paceStyle: .block)
    config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: 23) }
    let (window, host) = mounted(.init(glyphs: glyphs, fontSize: 28, accent: .yellow,
      glyphIDs: ids, carets: config))
    defer { window.contentView = nil; window.close() }
    let container = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let child = try XCTUnwrap(descendants(host, PromptCaretNativeView.self).first)
    child.layout(); child.present(at: 0)
    let markers = descendants(child, NSHostingView<PromptCaretMarkerView>.self)
    XCTAssertNil(coordinator.main.position)
    XCTAssertEqual(markers.count, 1); XCTAssertEqual(markers.first?.rootView.style, .block)
    XCTAssertEqual(coordinator.pace.position, container.rect(for: 23))
    XCTAssertFalse(window.isVisible)
  }

  func testDetachedBridgeStopsChildPresentationEvenIfATestStillOwnsTheChild() throws {
    let parent = NSView(frame: .init(x: 0, y: 0, width: 280, height: 100))
    let view = ASLPromptCaretContainer(frame: parent.bounds)
    parent.addSubview(view)
    view.configure(configuration(paceStyle: .off),
      frames: [23: .init(x: 20, y: 0, width: 30, height: 32)], glyphIDs: [23])
    let child = try XCTUnwrap(descendants(view, PromptCaretNativeView.self).first)
    child.layout(); child.present(at: 0)
    let marker = try XCTUnwrap(descendants(child, NSHostingView<PromptCaretMarkerView>.self).first)
    XCTAssertEqual(marker.alphaValue, 1)
    view.removeFromSuperview(); child.present(at: 0.75)
    XCTAssertEqual(marker.alphaValue, 1, "Detached configuration must no longer run the old blink provider")
  }

  func testSharedTypoHintAndWordUnderlineRenderWithNativeHands() throws {
    let glyphs: [TypingPromptGlyph] = [.init(character: "a", state: .correct),
      .init(character: "b", state: .incorrect, typedCharacter: "x")]
    var a = AttributedString("a"); a.foregroundColor = .black
    var b = AttributedString("b"); b.foregroundColor = .red
    b.underlineStyle = .single; b.appKit.underlineColor = .red
    var hint = AttributedString("x"); hint.foregroundColor = .red; hint.baselineOffset = -28 * 0.42
    let (window, host) = mounted(.init(glyphs: glyphs, fontSize: 28, accent: .yellow,
      glyphIDs: [5, 23], rendering: .init(text: a + b + hint, glyphCharacterOffsets: [5: 0, 23: 1])))
    defer { window.contentView = nil; window.close() }
    let png = try capture(host, name: "asl-shared-hint-underline")
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
    var red = 0, antialiasedRed = 0
    var redMass: Double = 0
    for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
      if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.5 {
        if color.redComponent > 0.6, color.greenComponent < 0.4, color.blueComponent < 0.4 { red += 1 }
        if color.redComponent - max(color.greenComponent, color.blueComponent) > 0.12 { antialiasedRed += 1 }
        redMass += max(0, color.redComponent - max(color.greenComponent, color.blueComponent)) * color.alphaComponent
      }
    } }
    print("ASL error pixels strong=\(red), antialiased=\(antialiasedRed), red channel mass=\(redMass)")
    XCTAssertGreaterThan(red, 20, "The underline has solid error ink")
    XCTAssertGreaterThan(antialiasedRed, 100, "Thin native hand strokes must also be counted, not only solid pixels")
    XCTAssertGreaterThan(redMass, 40, "The underline alone is insufficient; the actual hand must have colored ink")
    XCTAssertFalse(window.isVisible)
  }

  func testSwiftUIRemovalStopsOldCaretAndRestoresOnlyOneNewOwner() throws {
    let ids = [5, 23], glyphs = "az".map { TypingPromptGlyph(character: $0, state: .pending) }
    let coordinator = PromptCaretMotionCoordinator(), config = configuration(coordinator, paceStyle: .off)
    let (window, host) = mounted(.init(glyphs: glyphs, fontSize: 28, accent: .yellow,
      glyphIDs: ids, carets: config))
    defer { window.contentView = nil; window.close() }
    let old = try XCTUnwrap(descendants(host, PromptCaretNativeView.self).first)
    old.layout(); old.present(at: 0)
    let marker = try XCTUnwrap(descendants(old, NSHostingView<PromptCaretMarkerView>.self).first)
    host.rootView = .init(glyphs: glyphs, fontSize: 28, accent: .yellow, glyphIDs: ids)
    settle(host)
    XCTAssertTrue(descendants(host, PromptCaretNativeView.self).isEmpty)
    old.present(at: 0.75); XCTAssertEqual(marker.alphaValue, 1)
    host.rootView = .init(glyphs: glyphs, fontSize: 28, accent: .yellow, glyphIDs: ids, carets: config)
    settle(host)
    let new = try XCTUnwrap(descendants(host, PromptCaretNativeView.self).first)
    XCTAssertFalse(new === old)
    XCTAssertEqual(descendants(host, PromptCaretNativeView.self).count, 1)
    new.layout(); new.present(at: 1)
    let position = coordinator.main.position
    XCTAssertNotNil(position)
    old.present(at: 2); XCTAssertEqual(coordinator.main.position, position)
    XCTAssertFalse(window.isVisible)
  }
}
