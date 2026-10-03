import Foundation
import Observation

/// A value-only snapshot; a SwiftData model must never enter a worker.
/// Only the small configuration is encoded, not the potentially huge tape.
struct ResultWPMConsistencyInput: Sendable {
  let prompt: String
  let events: [TypingReplayEvent]
  let duration: TimeInterval
  let targetWordDirectory: ResultTargetWordDirectory?
  let sourceScoringBasis: ResultScoringUnitBasis?
  private let configurationData: Data?
  private let recordedEventsData: Data?
  private let recordedDirectoryData: Data?

  init(prompt: String, events: [TypingReplayEvent], duration: TimeInterval,
    configuration: TestConfiguration?, targetWordDirectory: ResultTargetWordDirectory?,
    sourceScoringBasis: ResultScoringUnitBasis?) throws {
    self.prompt = prompt; self.events = events; self.duration = duration
    self.targetWordDirectory = targetWordDirectory; self.sourceScoringBasis = sourceScoringBasis
    configurationData = try configuration.map { try JSONEncoder().encode($0) }
    recordedEventsData = nil; recordedDirectoryData = nil
  }

  /// Copy persisted bytes on the model actor; decode the tape only in the worker.
  init(prompt: String, duration: TimeInterval, configurationData: Data?,
    replayEventsData: Data?, targetWordDirectoryData: Data?, sourceScoringBasis: ResultScoringUnitBasis?) {
    self.prompt = prompt; self.duration = duration; self.configurationData = configurationData
    self.sourceScoringBasis = sourceScoringBasis
    events = []; targetWordDirectory = nil
    recordedEventsData = replayEventsData; recordedDirectoryData = targetWordDirectoryData
  }

  func calculate() -> Double? {
    guard !Task.isCancelled else { return nil }
    let configuration: TestConfiguration?
    if let configurationData {
      guard let decoded = try? JSONDecoder().decode(TestConfiguration.self, from: configurationData) else { return nil }
      configuration = decoded
    } else { configuration = nil }
    var decodedEvents = events, decodedDirectory = targetWordDirectory
    if let recordedEventsData {
      guard let decoded = try? JSONDecoder().decode([TypingReplayEvent].self, from: recordedEventsData) else { return nil }
      decodedEvents = decoded
    }
    if let recordedDirectoryData {
      guard let decoded = try? JSONDecoder().decode(ResultTargetWordDirectory.self, from: recordedDirectoryData) else { return nil }
      decodedDirectory = decoded
    }
    return ResultPerformanceTrace.wpmConsistency(prompt: prompt, events: decodedEvents, duration: duration,
      configuration: configuration, targetWordDirectory: decodedDirectory, sourceScoringBasis: sourceScoringBasis)
  }

  func value(calculation: @escaping @Sendable (Self) async -> Double? = { $0.calculate() }) async -> Double? {
    guard !Task.isCancelled else { return nil }
    let worker = Task<Double?, Never>.detached(priority: .utility) {
      guard !Task.isCancelled else { return nil }
      return await calculation(self)
    }
    let value = await withTaskCancellationHandler {
      await worker.value
    } onCancel: {
      worker.cancel()
    }
    return Task.isCancelled ? nil : value
  }
}

enum ResultWPMConsistencyLoadState: Equatable {
  case loading, unavailable, value(Double)
}

@MainActor @Observable final class ResultWPMConsistencyLoader {
  private(set) var state: ResultWPMConsistencyLoadState = .loading
  private var generation = UUID()

  func load(_ input: ResultWPMConsistencyInput?,
    calculation: @escaping @Sendable (ResultWPMConsistencyInput) async -> Double? = { $0.calculate() }
  ) async {
    let current = UUID()
    generation = current
    guard let input else { state = .unavailable; return }
    state = .loading
    let value = await input.value(calculation: calculation)
    guard generation == current, !Task.isCancelled else { return }
    state = value.map(ResultWPMConsistencyLoadState.value) ?? .unavailable
  }
}
