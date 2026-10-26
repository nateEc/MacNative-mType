import Foundation
import XCTest
@testable import Typebar

final class WebsitePaceTimerStateTests: XCTestCase {
  struct Request: Decodable {
    let word: Int, letter: Int
    let durationMilliseconds: Double
  }
  struct Event: Decodable {
    let kind: String, now: Double, visible: Bool
    let word: Int?, correct: Bool?, value: Bool?, words: [String]?
    let delivered: Int?, created: Int?, request: Request?, nextDelayMilliseconds: Double?
  }
  struct Scenario: Decodable { let speed: String; let rawWords: [String]; let events: [Event] }
  struct Output: Decodable { let revision: String; let actualModules: Int; let scenarios: [Scenario] }

  func source() throws -> Output {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned clean reference")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      root.appendingPathComponent("Scripts/check-source-pace-first-frame.mjs").path, reference, "--timer-fixtures"]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let result = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(result.revision, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(result.actualModules, 2)
    return result
  }

  func testElapsedFrameReadDoesNotDeliverSourceTimers() throws {
    let scenario = try XCTUnwrap(source().scenarios.first { $0.speed == "300" && $0.rawWords == ["ab ", "cd ", "efg"] })
    let start = try XCTUnwrap(scenario.events.first { $0.kind == "start" })
    let read = try XCTUnwrap(scenario.events.first { $0.kind == "read" })
    let expected = try XCTUnwrap(read.request)
    var progress = try XCTUnwrap(WebsitePaceTimerState(wpm: 300,
      catalog: .init(prompt: "", noSpaceWords: scenario.rawWords)))
    progress.start(atMilliseconds: start.now, blind: false)
    let delivery = try XCTUnwrap(scenario.events.first { $0.kind == "deliver" })
    progress.deliver(try XCTUnwrap(progress.nextTimeout).ticket, atMilliseconds: delivery.now, blind: false)
    // Observing the state at the later read time does not deliver any callback.
    XCTAssertGreaterThan(read.now, delivery.now)
    XCTAssertEqual(progress.lastRequest?.target, .init(word: expected.word, letter: expected.letter))
    XCTAssertEqual(try XCTUnwrap(progress.lastRequest).durationMilliseconds, expected.durationMilliseconds)
  }

  func testAllDeliveredRequestsAgainstCompletePinnedPaceAndWordModules() throws {
    let output = try source()
    XCTAssertEqual(output.scenarios.count, 40)
    XCTAssertEqual(output.scenarios.reduce(0) { $0 + $1.events.count }, 1840)
    for scenario in output.scenarios {
      let speed = scenario.speed == "Infinity" ? Double.infinity : try XCTUnwrap(Double(scenario.speed))
      var rawWords = scenario.rawWords
      var state = try XCTUnwrap(WebsitePaceTimerState(wpm: speed,
        catalog: .init(prompt: "", noSpaceWords: rawWords)))
      var blind = false
      var tickets: [Int: WebsitePaceTimerState.Ticket] = [:]
      for (index, event) in scenario.events.enumerated() {
        let context = "\(scenario.speed) \(scenario.rawWords) event \(index) \(event.kind)"
        switch event.kind {
        case "start": state.start(atMilliseconds: event.now, blind: blind)
        case "deliver":
          if let id = event.delivered, let ticket = tickets.removeValue(forKey: id) {
            state.deliver(ticket, atMilliseconds: event.now, blind: blind)
          }
        case "commit": state.handleCommit(word: try XCTUnwrap(event.word),
          correct: try XCTUnwrap(event.correct), blind: blind)
        case "blind": blind = try XCTUnwrap(event.value)
        case "append":
          let added = try XCTUnwrap(event.words)
          rawWords += added; state.appendWords(added)
        case "initialize": state = try XCTUnwrap(WebsitePaceTimerState(wpm: speed,
          catalog: .init(prompt: "", noSpaceWords: rawWords)))
        case "reset": state.reset()
        case "read": break
        default: XCTFail("Unknown event \(event.kind)")
        }
        if let created = event.created, let pending = state.nextTimeout {
          tickets[created] = pending.ticket
        }
        XCTAssertEqual(state.isVisible, event.visible, context)
        if event.visible, let request = event.request {
          XCTAssertEqual(state.lastRequest?.target, .init(word: request.word, letter: request.letter), context)
          XCTAssertEqual(try XCTUnwrap(state.lastRequest).durationMilliseconds,
            request.durationMilliseconds, accuracy: 1e-8, context)
          XCTAssertEqual(state.nextTimeout?.delayMilliseconds, event.nextDelayMilliseconds, context)
        }
      }
    }
  }

  func testDeliveryOwnershipClockValidationAndSnapshotIsolation() throws {
    let catalog = PaceCaretCatalog(prompt: "ab cd")
    for speed in [Double.nan, -Double.infinity, -1, 0, 0.99] {
      XCTAssertNil(WebsitePaceTimerState(wpm: speed, catalog: catalog))
    }
    var state = try XCTUnwrap(WebsitePaceTimerState(wpm: .infinity, catalog: catalog))
    state.start(atMilliseconds: .nan, blind: false)
    XCTAssertNil(state.lastRequest)
    state.start(atMilliseconds: 1000, blind: false)
    let initial = state
    let ticket = try XCTUnwrap(state.nextTimeout).ticket
    for time in [Double.nan, .infinity, 999] {
      state.deliver(ticket, atMilliseconds: time, blind: false)
      XCTAssertEqual(state.lastRequest, initial.lastRequest)
      XCTAssertEqual(state.nextTimeout, initial.nextTimeout)
    }
    state.deliver(ticket, atMilliseconds: 1004, blind: false)
    XCTAssertEqual(state.lastRequest?.target, .init(word: 0, letter: 2))
    XCTAssertEqual(state.lastRequest?.durationMilliseconds, -4)
    XCTAssertEqual(initial.lastRequest?.target, .init(word: 0, letter: 1))
    let delivered = state
    state.deliver(ticket, atMilliseconds: 1010, blind: false)
    XCTAssertEqual(state.lastRequest, delivered.lastRequest)
    XCTAssertEqual(state.nextTimeout, delivered.nextTimeout)
    state = try XCTUnwrap(WebsitePaceTimerState(wpm: 60, catalog: catalog))
    state.start(atMilliseconds: 2000, blind: false)
    let fresh = state
    state.deliver(ticket, atMilliseconds: 2010, blind: false)
    XCTAssertEqual(state.lastRequest, fresh.lastRequest)
    XCTAssertEqual(state.nextTimeout, fresh.nextTimeout)
    state.reset()
    XCTAssertTrue(state.isVisible)
    XCTAssertNil(state.nextTimeout)
    state.deliver(try XCTUnwrap(fresh.nextTimeout).ticket, atMilliseconds: 2500, blind: false)
    XCTAssertEqual(state.lastRequest, fresh.lastRequest)
  }

  func testAppendingCannotReviveExhaustedAttempt() throws {
    var state = try XCTUnwrap(WebsitePaceTimerState(wpm: 60,
      catalog: .init(prompt: "", noSpaceWords: [])))
    state.start(atMilliseconds: 0, blind: false)
    XCTAssertFalse(state.isVisible)
    state.appendWords(["ab "])
    state.start(atMilliseconds: 1, blind: false)
    XCTAssertNil(state.lastRequest)
    XCTAssertNil(state.nextTimeout)
  }
}
