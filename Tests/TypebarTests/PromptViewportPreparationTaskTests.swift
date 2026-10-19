import AppKit
import XCTest
@testable import Typebar

@MainActor final class PromptViewportPreparationTaskTests: XCTestCase {
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
  private let style = PromptRenderStyle(theme: .init(background: .white, panel: .white,
    accent: .blue, colorScheme: .light))

  private func sequence(_ prompt: String) throws -> PromptViewportFieldLayoutSequence {
    let session = TypingSession(configuration: .words(prompt.split(separator: " ").count), prompt: prompt)
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    return try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
  }

  func testPublishesFirstWindowBeforeCompletingRemainingGeometry() async throws {
    let layout = try sequence("one two three four five six")
    let owner = PromptViewportPreparationTask()
    var progress: [(Int, Bool)] = []
    var completed = false
    let running = owner.start(sequence: layout, batchSize: 2, isCurrent: { true },
      onBatch: { snapshot in
        progress.append((layout.nextField, snapshot.hasCompleteHeight))
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.accessibilityText, "one two three four five six")
      }, completion: { result in
        if case .success = result { completed = true }
      })
    await running.value
    XCTAssertEqual(progress.map(\.0), [2, 4, 6])
    XCTAssertEqual(progress.map(\.1), [false, false, true])
    XCTAssertTrue(completed)
    XCTAssertFalse(owner.isPreparing)
  }

  func testCancelInsideFirstBatchSuppressesLaterBatchesAndCompletion() async throws {
    let layout = try sequence("one two three four five six")
    let owner = PromptViewportPreparationTask()
    var received = [Int]()
    var completed = false
    let running = owner.start(sequence: layout, batchSize: 2, isCurrent: { true },
      onBatch: { snapshot in
        received.append(snapshot.windows[0].fields.lowerBound)
        owner.cancel()
      }, completion: { _ in completed = true })
    await running.value
    XCTAssertEqual(received, [0])
    XCTAssertFalse(completed)
    XCTAssertFalse(owner.isPreparing)
    XCTAssertEqual(layout.nextField, 2)
  }

  func testChangedPublicationContextStopsAtLastAcceptedBatch() async throws {
    let layout = try sequence("one two three four five six")
    let owner = PromptViewportPreparationTask()
    var current = true
    var received = [Int]()
    var completed = false
    let running = owner.start(sequence: layout, batchSize: 2, isCurrent: { current },
      onBatch: { snapshot in
        received.append(snapshot.windows[0].fields.lowerBound)
        current = false // The host changed attempt, input, width, or style.
      }, completion: { _ in completed = true })
    await running.value
    XCTAssertEqual(received, [0])
    XCTAssertFalse(completed)
    XCTAssertFalse(owner.isPreparing)
  }

  func testRestartInsideFirstBatchCannotPublishOlderRequest() async throws {
    let old = try sequence("one two three four five six")
    let fresh = try sequence("oak pine maple cedar")
    let owner = PromptViewportPreparationTask()
    var events = [String]()
    var freshTask: Task<Void, Never>?
    let oldTask = owner.start(sequence: old, batchSize: 2, isCurrent: { true },
      onBatch: { _ in
        events.append("old-batch")
        freshTask = owner.start(sequence: fresh, batchSize: 2, isCurrent: { true },
          onBatch: { snapshot in
            events.append("fresh-\(snapshot.windows[0].fields.lowerBound)")
          }, completion: { result in
            if case .success = result { events.append("fresh-complete") }
          })
      }, completion: { _ in events.append("old-complete") })
    await oldTask.value
    await freshTask?.value
    XCTAssertEqual(events, ["old-batch", "fresh-0", "fresh-2", "fresh-complete"])
    XCTAssertEqual(old.nextField, 2)
    XCTAssertEqual(fresh.nextField, 4)
    XCTAssertFalse(owner.isPreparing)
  }

  func testInvalidBatchSizeReportsFailureWithoutPublishing() async throws {
    let layout = try sequence("one two")
    let owner = PromptViewportPreparationTask()
    var batches = 0
    var failed = false
    let running = owner.start(sequence: layout, batchSize: 0, isCurrent: { true },
      onBatch: { _ in batches += 1 }, completion: { result in
        if case .failure = result { failed = true }
      })
    await running.value
    XCTAssertEqual(batches, 0)
    XCTAssertTrue(failed)
    XCTAssertFalse(owner.isPreparing)
  }

  func testBoundedDemandStopsAtFirstViewportThenResumesWithoutMeasuringRest() async throws {
    let layout = try sequence("one two three four five six")
    let owner = PromptViewportPreparationTask()
    var published: [(Int, Bool)] = []
    var completed = 0
    let first = owner.start(sequence: layout, batchSize: 2, throughFieldCount: 2,
      isCurrent: { true }, onBatch: { snapshot in
        published.append((layout.nextField, snapshot.hasCompleteHeight))
      }, completion: { result in
        if case .success = result { completed += 1 }
      })
    await first.value
    XCTAssertEqual(published.map(\.0), [2])
    XCTAssertEqual(published.map(\.1), [false])
    XCTAssertEqual(layout.nextField, 2)
    XCTAssertEqual(completed, 1)
    let remaining = owner.start(sequence: layout, batchSize: 2, throughFieldCount: 6,
      isCurrent: { true }, onBatch: { snapshot in
        published.append((layout.nextField, snapshot.hasCompleteHeight))
      }, completion: { result in
        if case .success = result { completed += 1 }
      })
    await remaining.value
    XCTAssertEqual(published.map(\.0), [2, 4, 6])
    XCTAssertEqual(published.map(\.1), [false, false, true])
    XCTAssertEqual(completed, 2)
    XCTAssertFalse(owner.isPreparing)
  }

  func testInvalidDemandCannotAdvanceMeasuredPrefix() async throws {
    let layout = try sequence("one two three")
    let owner = PromptViewportPreparationTask()
    var failures = 0
    for requested in [0, layout.fieldCount + 1] {
      let running = owner.start(sequence: layout, batchSize: 2, throughFieldCount: requested,
        isCurrent: { true }, onBatch: { _ in XCTFail("Invalid demand published") },
        completion: { result in
          if case .failure = result { failures += 1 }
        })
      await running.value
    }
    XCTAssertEqual(failures, 2)
    XCTAssertEqual(layout.nextField, 0)
    XCTAssertFalse(owner.isPreparing)
  }

  func testDemandEndingInsideBatchDoesNotOvermeasureAndCompletedDemandDoesNotRepublish() async throws {
    let layout = try sequence("one two three four five")
    let owner = PromptViewportPreparationTask()
    var positions: [Int] = []
    var completions = 0
    for _ in 0..<2 {
      let running = owner.start(sequence: layout, batchSize: 2, throughFieldCount: 3,
        isCurrent: { true }, onBatch: { _ in positions.append(layout.nextField) },
        completion: { result in
          if case .success = result { completions += 1 }
        })
      await running.value
    }
    XCTAssertEqual(positions, [2, 3])
    XCTAssertEqual(layout.nextField, 3)
    XCTAssertEqual(completions, 2)
  }

  func testHundredThousandWordFirstBatchCanPublishWithoutMeasuringRest() async throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["TYPEBAR_ENDURANCE_TESTS"] == "1",
      "Run explicitly with TYPEBAR_ENDURANCE_TESTS=1")
    let count = 100_001
    let prompt = Array(repeating: "oak", count: count).joined(separator: " ")
    let layout = try sequence(prompt)
    let owner = PromptViewportPreparationTask()
    var received = 0
    var completed = false
    let running = owner.start(sequence: layout, batchSize: 2, throughFieldCount: 2,
      isCurrent: { true },
      onBatch: { snapshot in
        received += 1
        XCTAssertEqual(snapshot.windows[0].runs.flatMap(\.cells).count, 8)
        XCTAssertFalse(snapshot.hasCompleteHeight)
        XCTAssertEqual(snapshot.accessibilityText, prompt)
      }, completion: { result in
        if case .success = result { completed = true }
      })
    await running.value
    XCTAssertEqual(received, 1)
    XCTAssertTrue(completed)
    XCTAssertEqual(layout.nextField, 2)
    XCTAssertFalse(owner.isPreparing)
  }

  func testReleasedOwnerStopsAfterCurrentBatch() async throws {
    let layout = try sequence("one two three four five six")
    var owner: PromptViewportPreparationTask? = PromptViewportPreparationTask()
    weak var released = owner
    var batches = 0
    var completed = false
    let running = owner!.start(sequence: layout, batchSize: 2, isCurrent: { true },
      onBatch: { _ in
        batches += 1
        owner = nil
      }, completion: { _ in completed = true })
    await running.value
    XCTAssertNil(released)
    XCTAssertEqual(batches, 1)
    XCTAssertFalse(completed)
  }
}
