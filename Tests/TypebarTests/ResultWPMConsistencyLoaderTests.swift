import XCTest
@testable import Typebar

private actor WPMCalculationGate {
  private var entered = false
  private var opened = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var observers: [CheckedContinuation<Void, Never>] = []
  private(set) var cancellationObserved = false
  private(set) var calculations = 0

  func pause() async {
    entered = true
    observers.forEach { $0.resume() }; observers.removeAll()
    if opened { return }
    await withCheckedContinuation { waiters.append($0) }
  }
  func waitUntilEntered() async {
    if entered { return }
    await withCheckedContinuation { observers.append($0) }
  }
  func open() {
    opened = true
    waiters.forEach { $0.resume() }; waiters.removeAll()
  }
  func record(cancelled: Bool) { calculations += 1; cancellationObserved = cancelled }
}

final class ResultWPMConsistencyLoaderTests: XCTestCase {
  private static func calculationIsOnMainThread() -> Bool { Thread.isMainThread }
  private func input(configuration: TestConfiguration? = .words(1), duration: Double = 2,
    basis: ResultScoringUnitBasis? = .koreanJamo) throws -> ResultWPMConsistencyInput {
    try .init(prompt: "괅", events: [.init(offset: 0, kind: .insert, units: [0xad05],
      inputField: .init(index: 0, units: [0xad05]))], duration: duration,
      configuration: configuration, targetWordDirectory: nil, sourceScoringBasis: basis)
  }

  @MainActor func testWorkerCalculationDoesNotExecuteOnTheMainThread() async throws {
    let snapshot = try input()
    let value = await snapshot.value { value in
      Self.calculationIsOnMainThread() ? -1 : value.calculate()
    }
    XCTAssertEqual(value, 66.67)
  }

  @MainActor func testOwnedSnapshotKeepsConfigurationAndBasisWithoutSharingAModel() async throws {
    var configuration = TestConfiguration.words(1)
    let finite = try input(configuration: configuration, duration: 0.497)
    configuration = .timed(seconds: 1)
    let timed = try input(configuration: configuration, duration: 0.497)
    let finiteValue = await finite.value(), timedValue = await timed.value()
    XCTAssertEqual(finiteValue, 100)
    XCTAssertEqual(timedValue, 0)
    XCTAssertEqual(finite.sourceScoringBasis, .koreanJamo)
    XCTAssertEqual(finite.events[0].inputUnits, [0xad05])
  }

  @MainActor func testNewerLoadCannotBeOverwrittenByAnOlderCompletion() async throws {
    let loader = ResultWPMConsistencyLoader(), gate = WPMCalculationGate()
    let snapshot = try input()
    let old = Task { await loader.load(snapshot) { _ in await gate.pause(); return 12 } }
    await gate.waitUntilEntered()
    await loader.load(snapshot) { _ in 84 }
    XCTAssertEqual(loader.state, .value(84))
    await gate.open(); await old.value
    XCTAssertEqual(loader.state, .value(84))
  }

  @MainActor func testParentCancellationReachesWorkerAndDoesNotPublishAValue() async throws {
    let loader = ResultWPMConsistencyLoader(), gate = WPMCalculationGate()
    let snapshot = try input()
    let task = Task {
      await loader.load(snapshot) { _ in
        await gate.pause()
        await gate.record(cancelled: Task.isCancelled)
        return 88
      }
    }
    await gate.waitUntilEntered(); task.cancel(); await gate.open(); await task.value
    let cancelled = await gate.cancellationObserved
    XCTAssertTrue(cancelled)
    XCTAssertEqual(loader.state, .loading)
  }

  @MainActor func testCancelledBeforeStartDoesNotBeginCalculator() async throws {
    let gate = WPMCalculationGate(), calls = WPMCalculationGate(), snapshot = try input()
    let task = Task {
      await gate.pause()
      return await snapshot.value { _ in await calls.record(cancelled: Task.isCancelled); return 88 }
    }
    await gate.waitUntilEntered(); task.cancel(); await gate.open()
    let value = await task.value, count = await calls.calculations
    XCTAssertNil(value)
    XCTAssertEqual(count, 0)
  }

  @MainActor func testCancelledCoreCannotReturnAnUncancelledOrPartialPopulation() async throws {
    let gate = WPMCalculationGate(), snapshot = try input()
    let task = Task { await gate.pause(); return snapshot.calculate() }
    await gate.waitUntilEntered(); task.cancel(); await gate.open()
    let value = await task.value
    XCTAssertNil(value)
  }

  @MainActor func testUnavailableSnapshotNeverInventsZeroOrKeepsAPreviousValue() async throws {
    let loader = ResultWPMConsistencyLoader(), gate = WPMCalculationGate()
    await loader.load(try input())
    XCTAssertEqual(loader.state, .value(66.67))
    let snapshot = try input()
    let old = Task { await loader.load(snapshot) { _ in await gate.pause(); return 12 } }
    await gate.waitUntilEntered()
    await loader.load(nil)
    XCTAssertEqual(loader.state, .unavailable)
    await gate.open(); await old.value
    XCTAssertEqual(loader.state, .unavailable)
  }

  @MainActor func testPersistedBytesDecodeInWorkerAndPreserveScoringBasis() async throws {
    let direct = try input()
    let stored = ResultWPMConsistencyInput(prompt: direct.prompt, duration: direct.duration,
      configurationData: try JSONEncoder().encode(TestConfiguration.words(1)),
      replayEventsData: try JSONEncoder().encode(direct.events),
      targetWordDirectoryData: try JSONEncoder().encode(ResultTargetWordDirectory(words: ["괅"], noSpace: false)),
      sourceScoringBasis: .koreanJamo)
    let value = await stored.value { input in
      Self.calculationIsOnMainThread() ? -1 : input.calculate()
    }
    XCTAssertEqual(value, 66.67)
    XCTAssertTrue(stored.events.isEmpty)
  }

  @MainActor func testMalformedPersistedInputsAreUnavailableNotFallbackScores() async throws {
    let events = try JSONEncoder().encode(input().events)
    let configuration = try JSONEncoder().encode(TestConfiguration.words(1))
    let invalid = Data("invalid".utf8)
    let tapes: [(Data?, Data?, Data?)] = [
      (configuration, invalid, nil), (invalid, events, nil),
      (configuration, events, invalid), (configuration, nil, nil)]
    for (config, tape, directory) in tapes {
      let snapshot = ResultWPMConsistencyInput(prompt: "괅", duration: 2,
        configurationData: config, replayEventsData: tape, targetWordDirectoryData: directory,
        sourceScoringBasis: .koreanJamo)
      let value = await snapshot.value()
      XCTAssertNil(value)
    }
  }

  func testUnencodableConfigurationCannotSilentlyLoseItsMode() {
    var configuration = TestConfiguration.timed(seconds: 1)
    configuration.duration = .nan
    XCTAssertThrowsError(try input(configuration: configuration))
  }
}
