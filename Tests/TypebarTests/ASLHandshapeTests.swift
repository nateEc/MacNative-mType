import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class ASLHandshapeTests: XCTestCase {
  private let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
  private func shape(_ letter: Character) throws -> ASLHandshape {
    try XCTUnwrap(ASLHandshapePolicy.handshape(for: letter))
  }

  func testAlphabetCannotCollapseDifferentFingerThumbAndContactRelationships() {
    // Compare the full production drawing, not just a new model identity.
    // Distinct pictures are necessary but not sufficient for semantic fidelity.
    for pair in [("A", "D"), ("A", "I"), ("C", "E"), ("M", "N"), ("S", "T")] {
      let first = Character(pair.0), second = Character(pair.1)
      let firstDrawing = ASLHandshapeDrawing(ASLHandshapePolicy.handshape(for: first)!)
      let secondDrawing = ASLHandshapeDrawing(ASLHandshapePolicy.handshape(for: second)!)
      XCTAssertNotEqual(firstDrawing.parts.map { $0.path.description }, secondDrawing.parts.map { $0.path.description },
        "Renderer must distinguish \(first) from \(second)")
    }
  }

  func testExactlyAsciiLettersAreSupportedWithoutUnicodeCaseExpansion() throws {
    for letter in alphabet {
      XCTAssertEqual(try shape(letter), try shape(Character(String(letter).lowercased())))
      XCTAssertEqual(try shape(letter).fingers.count, 4)
    }
    for letter in Array("7_ßﬀéＡ🙂\n ") + [Character("a\u{301}")] {
      XCTAssertNil(ASLHandshapePolicy.handshape(for: letter), String(letter))
    }
  }

  func testFistLettersDifferByThumbPlacementNotFakeRaisedFingers() throws {
    for letter in Array("ASMNT") { XCTAssertTrue(try shape(letter).fingers.allSatisfy { $0 == .folded }) }
    XCTAssertEqual(try shape("A").thumb, .alongside)
    XCTAssertEqual(try shape("S").thumb, .acrossFist)
    XCTAssertEqual(try shape("T").thumb, .underFingers(1))
    XCTAssertEqual(try shape("N").thumb, .underFingers(2))
    XCTAssertEqual(try shape("M").thumb, .underFingers(3))
  }

  func testDAndFAreDifferentContactAndExtendedFingerConfigurations() throws {
    let d = try shape("D"), f = try shape("F")
    XCTAssertEqual(d[.index], .extended); XCTAssertEqual(d.thumb, .touchesMiddle)
    XCTAssertTrue([ASLFinger.middle, .ring, .little].allSatisfy { d[$0] == .curved })
    XCTAssertEqual(f[.index], .curved); XCTAssertEqual(f.thumb, .touchesIndex)
    XCTAssertTrue([ASLFinger.middle, .ring, .little].allSatisfy { f[$0] == .extended })
  }

  func testCurvedCAndOHaveAnOpenGapOrActualThumbContactWhileEIsHooked() throws {
    XCTAssertTrue(try shape("C").fingers.allSatisfy { $0 == .curved })
    XCTAssertEqual(try shape("C").thumb, .openOpposition)
    XCTAssertEqual(try shape("O").thumb, .touchesAll)
    XCTAssertTrue(try shape("E").fingers.allSatisfy { $0 == .hooked })
    XCTAssertEqual(try shape("E").thumb, .acrossPalm)
    let c = ASLHandshapeDrawing(try shape("C")), o = ASLHandshapeDrawing(try shape("O"))
    let cTip = try XCTUnwrap(c.parts[1].path.currentPoint), cThumb = try XCTUnwrap(c.parts.last?.path.currentPoint)
    XCTAssertGreaterThan(hypot(cTip.x - cThumb.x, cTip.y - cThumb.y), 20)
    for finger in o.parts[1...4] { XCTAssertEqual(finger.path.currentPoint, o.parts.last?.path.currentPoint) }
  }

  func testRelatedPairsKeepTheirHandConfigurationAndChangeOrientation() throws {
    for (a, b) in [(Character("G"), Character("Q")), ("H", "U"), ("K", "P")] {
      var first = try shape(a), second = try shape(b)
      XCTAssertNotEqual(first.orientation, second.orientation)
      first.orientation = second.orientation
      XCTAssertEqual(first, second)
    }
    XCTAssertEqual(try shape("G").orientation, .sideways)
    XCTAssertEqual(try shape("Q").orientation, .downward)
    XCTAssertEqual(try shape("P").orientation, .angledDown)
  }

  func testUVRDistinguishJoinedSpreadAndCrossedFingers() throws {
    let u = try shape("U"), v = try shape("V"), r = try shape("R")
    XCTAssertEqual(u.fingers, v.fingers); XCTAssertEqual(u.fingers, r.fingers)
    XCTAssertEqual(u.arrangement, .joined); XCTAssertEqual(v.arrangement, .spread)
    XCTAssertEqual(r.arrangement, .crossed)
    XCTAssertEqual(try shape("W").fingers.filter { $0 == .extended }.count, 3)
    XCTAssertEqual(try shape("X")[.index], .hooked)
    XCTAssertEqual(try shape("Y")[.little], .extended); XCTAssertEqual(try shape("Y").thumb, .extended)
  }

  func testIAndJShareLittleFingerPoseButOnlyJHasMotionAndZUsesIndex() throws {
    var i = try shape("I"), j = try shape("J")
    XCTAssertEqual(i[.little], .extended); XCTAssertEqual(i[.index], .folded)
    i.motion = j.motion; XCTAssertEqual(i, j)
    XCTAssertEqual(j.motion, .jCurve)
    XCTAssertEqual(try shape("Z")[.index], .extended)
    XCTAssertEqual(try shape("Z").motion, .zZigzag)
    XCTAssertEqual(alphabet.filter { ASLHandshapePolicy.motionCue(for: $0) != nil }, Array("JZ"))
  }

  func testEveryHandDrawingIsFiniteBoundedAndDifferentWithoutLetterText() throws {
    var fingerprints = Set<String>()
    for letter in alphabet {
      let drawing = ASLHandshapeDrawing(try shape(letter))
      XCTAssertEqual(drawing.parts.count, 6)
      for part in drawing.parts {
        let bounds = part.path.boundingRect.insetBy(dx: -part.width / 2, dy: -part.width / 2)
        XCTAssertTrue([bounds.minX, bounds.maxX, bounds.minY, bounds.maxY].allSatisfy(\.isFinite))
        XCTAssertTrue(CGRect(x: -5, y: -5, width: 110, height: 110).contains(bounds), "\(letter): \(bounds)")
      }
      let fingerprint = drawing.parts.map { $0.path.description }.joined(separator: "|") + (drawing.motion?.description ?? "")
      XCTAssertTrue(fingerprints.insert(fingerprint).inserted, "Duplicate drawing for \(letter)")
    }
  }

  func testAccessibilityDoesNotExposeTheTargetLetterAsAnAnswerLabel() {
    for letter in alphabet {
      let label = ASLHandshapeGlyph(character: letter, color: .gray, background: .clear, size: 28).accessibilityPrompt
      if !"JZ".contains(letter) { XCTAssertEqual(label, "ASL 指语字形") }
    }
  }

  func testFoldedFingerHasACompactKnuckleInsteadOfSelfOverlappingLoop() throws {
    let drawing = ASLHandshapeDrawing(try shape("A"))
    for part in drawing.parts[1...4] {
      XCTAssertLessThanOrEqual(part.path.boundingRect.height + part.width, 24,
        "Folded fingers must not draw an up-and-back tube that crosses itself")
    }
  }

  func testActualAlphabetRendersTwentySixDistinctHandsInOneNeverVisibleWindow() throws {
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 104, height: 112),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    defer { window.contentView = nil; window.close() }
    var rasters: [Data] = []
    for letter in alphabet {
      let view = NSHostingView(rootView: ASLHandshapeGlyph(character: letter, color: .black,
        background: .clear, size: 100).frame(width: 104, height: 112).background(Color.white))
      view.frame = .init(x: 0, y: 0, width: 104, height: 112); window.contentView = view
      view.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.03))
      let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: bitmap)
      var pixels = Data(), ink = 0
      for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
        let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        let gray = UInt8((color.redComponent.clamped(to: 0...1) * 255).rounded())
        pixels.append(gray); if gray < 220 { ink += 1 }
      } }
      XCTAssertGreaterThan(ink, 150, "\(letter) must contain an actual hand, not blank canvas")
      XCTAssertFalse(rasters.contains(pixels), "\(letter) must not repeat another letter's raster")
      rasters.append(pixels)
      if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("asl-handshape-\(letter).png"))
      }
      XCTAssertFalse(window.isVisible)
      window.contentView = nil
    }
  }

  func testProductionSizeAlphabetSheetsRenderWithoutActivatingWindows() throws {
    for size in [28.0, 52.0] {
      let width = 7 * (size + 24), height = 4 * (size * 1.1 + 32)
      let content = Grid(horizontalSpacing: 12, verticalSpacing: 12) {
        ForEach(0..<4) { row in
          GridRow {
            ForEach(0..<7) { column in
              let index = row * 7 + column
              if index < self.alphabet.count {
                VStack(spacing: 4) {
                  // QA caption only; no answer labels in the production glyph.
                  Text(String(self.alphabet[index])).font(.system(size: 11, design: .monospaced)).foregroundStyle(.black)
                  ASLHandshapeGlyph(character: self.alphabet[index], color: .black, background: .clear, size: size)
                }
                .frame(width: size + 12, height: size * 1.1 + 20)
              } else { Color.clear.frame(width: size + 12, height: size * 1.1 + 20) }
            }
          }
        }
      }.padding(6).frame(width: width, height: height).background(Color.white)
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: height),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
      defer { window.contentView = nil; window.close() }
      let view = NSHostingView(rootView: content); window.contentView = view
      view.frame = .init(x: 0, y: 0, width: width, height: height)
      view.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: bitmap)
      if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("asl-alphabet-\(Int(size)).png"))
      }
      XCTAssertFalse(window.isVisible)
    }
  }

  private func raster<V: View>(_ content: V, name: String) throws -> Data {
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 80, height: 60),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    defer { window.contentView = nil; window.close() }
    let view = NSHostingView(rootView: content.frame(width: 80, height: 60, alignment: .topLeading).background(Color.white))
    view.frame = .init(x: 0, y: 0, width: 80, height: 60); window.contentView = view
    view.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.04))
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
      let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("asl-\(name).png"))
    }
    var pixels = Data()
    for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
      let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
      for component in [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent] {
        pixels.append(UInt8((component.clamped(to: 0...1) * 255).rounded()))
      }
    } }
    XCTAssertFalse(window.isVisible)
    return pixels
  }

  func testActualPracticePromptDisplaysWrongUnsupportedInputAsTextRatherThanAFakeHandOrTarget() throws {
    for character in Array("7ß") {
      let actual = try raster(ASLPracticePrompt(glyphs: [.init(character: "A", state: .incorrect, typedCharacter: character)],
        fontSize: 28, accent: .blue), name: "wrong-\(character == "7" ? "digit" : "unicode")")
      let expected = try raster(Text(String(character)).font(.system(size: 28, design: .monospaced)).foregroundStyle(.red),
        name: "expected-\(character == "7" ? "digit" : "unicode")")
      XCTAssertEqual(actual, expected, "Unsupported typed \(character) must remain the actual entered text")
    }
  }

  func testHiddenActualPromptHasNoHandInkOrAnswerLabelSubstitute() throws {
    let actual = try raster(ASLPracticePrompt(glyphs: [.init(character: "A", state: .hidden)],
      fontSize: 28, accent: .blue), name: "hidden")
    let empty = try raster(Color.clear, name: "empty")
    XCTAssertEqual(actual, empty)
  }

  func testHandshapePresentationCannotChangePromptInputScoringOrReplay() throws {
    let start = Date(timeIntervalSince1970: 100)
    func run(_ modifiers: [TestModifier]) throws -> CompletedTestResult {
      var session = TypingSession(configuration: TestConfiguration.words(2).with(modifiers: modifiers), prompt: "jz adimnst")
      session.insert("x", at: start)
      // Build actual geometry while the mistaken character is displayed.
      for glyph in session.promptGlyphsInDisplayOrder {
        if let shape = ASLHandshapePolicy.handshape(for: glyph.typedCharacter ?? glyph.character) {
          _ = ASLHandshapeDrawing(shape)
        }
      }
      session.deleteBackward(at: start.addingTimeInterval(0.1))
      session.insertBatch("jz adimnst", at: start.addingTimeInterval(1))
      XCTAssertEqual(session.prompt, "jz adimnst"); XCTAssertEqual(session.typed, "jz adimnst")
      XCTAssertEqual(session.outcome, .completed)
      return try XCTUnwrap(session.result(at: start.addingTimeInterval(2)))
    }
    let ordinary = try run([]), asl = try run([.aslVisual])
    XCTAssertEqual(asl.typedCharacterCount, ordinary.typedCharacterCount)
    XCTAssertEqual(asl.correctCharacterCount, ordinary.correctCharacterCount)
    XCTAssertEqual(asl.errorCount, ordinary.errorCount)
    XCTAssertEqual(asl.wpm, ordinary.wpm); XCTAssertEqual(asl.rawWpm, ordinary.rawWpm)
    XCTAssertEqual(asl.accuracy, ordinary.accuracy)
    XCTAssertEqual(asl.preciseWpm, ordinary.preciseWpm)
    XCTAssertEqual(asl.preciseRawWpm, ordinary.preciseRawWpm)
    XCTAssertEqual(asl.preciseAccuracy, ordinary.preciseAccuracy)
    XCTAssertEqual(asl.replayEvents, ordinary.replayEvents)
    XCTAssertEqual(asl.startedAt, ordinary.startedAt); XCTAssertEqual(asl.finishedAt, ordinary.finishedAt)
  }
}
