import Foundation
import Observation

/// Anonymous numeric samples only. Not a replay or ranking proof.
struct AccountResultChartData: Codable, Equatable, Sendable {
  struct Sample: Codable, Equatable, Sendable, Identifiable {
    let elapsed: Double
    let wpm: Double
    let burst: Double
    let errors: Int
    var id: Double { elapsed }
  }
  let version: Int
  let samples: [Sample]
  init(version: Int = 1, samples: [Sample]) { self.version = version; self.samples = samples }
  var isValid: Bool {
    guard version == 1, (1...122).contains(samples.count) else { return false }
    var previous = 0.0
    for sample in samples {
      guard sample.elapsed.isFinite, sample.elapsed > previous, sample.elapsed <= 122,
        sample.wpm.isFinite, sample.burst.isFinite,
        (0...1_000_000_000).contains(sample.wpm), (0...1_000_000_000).contains(sample.burst),
        (0...1_800_000).contains(sample.errors) else { return false }
      previous = sample.elapsed
    }
    return true
  }
  func matches(duration: Double) -> Bool {
    isValid && duration.isFinite && duration > 0 && duration <= 122
      && (samples.last?.elapsed ?? .infinity) <= duration + 0.011
  }
  private enum CodingKeys: String, CodingKey { case version, samples }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(version: try values.decode(Int.self, forKey: .version), samples: try values.decode([Sample].self, forKey: .samples))
    guard isValid else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid anonymous performance chart")) }
  }
  func encode(to encoder: Encoder) throws {
    guard isValid else { throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath, debugDescription: "Invalid anonymous performance chart")) }
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(version, forKey: .version); try values.encode(samples, forKey: .samples)
  }
  func nearest(to elapsed: Double) -> Sample? {
    guard elapsed.isFinite else { return nil }
    return samples.min { abs($0.elapsed-elapsed) == abs($1.elapsed-elapsed)
      ? $0.elapsed < $1.elapsed : abs($0.elapsed-elapsed) < abs($1.elapsed-elapsed) }
  }
}

/// Copy value evidence before entering a worker; no SwiftData model crosses actors.
struct AccountResultChartInput: Sendable {
  let prompt: String
  let events: [TypingReplayEvent]
  let duration: Double
  let directory: ResultTargetWordDirectory?
  let basis: ResultScoringUnitBasis?
  private let configuration: Data
  init(_ result: CompletedTestResult) throws {
    prompt = result.prompt; events = result.replayEvents; duration = result.chartDuration
    directory = result.targetWordDirectory; basis = result.characterStats.sourceUnitBasis
    configuration = try JSONEncoder().encode(result.configuration)
  }
  func calculate() -> AccountResultChartData? {
    guard !Task.isCancelled, duration.isFinite, duration > 0, duration <= 122,
      let config = try? JSONDecoder().decode(TestConfiguration.self, from: configuration) else { return nil }
    let points = ResultPerformanceTrace.points(prompt: prompt, events: events, duration: duration,
      configuration: config, targetWordDirectory: directory, sourceScoringBasis: basis)
    let data = AccountResultChartData(samples: points.map {
      .init(elapsed: $0.elapsed, wpm: Double($0.wpm), burst: $0.burstWpm, errors: $0.errorCount)
    })
    return !Task.isCancelled && data.matches(duration: duration) ? data : nil
  }
  func value() async throws -> AccountResultChartData? {
    try Task.checkCancellation()
    let worker = Task.detached(priority: .utility) { calculate() }
    let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation()
    return result
  }
}

struct AccountResultChartRead: Equatable, Sendable {
  let scope: ResultPublicationScope
  let generation: UInt64
  let id: UUID
}

struct AccountResultChartScale {
  let unit: TypingSpeedUnit
  let speedLower: Double
  let speedUpper: Double
  let errorLower: Double
  let errorUpper: Double
  init(data: AccountResultChartData, unit: TypingSpeedUnit, startsAtZero: Bool) {
    self.unit = unit
    let speeds = data.samples.flatMap { [unit.converted(wpm: $0.wpm),unit.converted(wpm: $0.burst)] }
    speedLower = startsAtZero ? 0 : DailyActivityOverviewScale.niceLowerBound(for: speeds.min() ?? 0)
    speedUpper = max(DailyActivityOverviewScale.niceUpperBound(for: speeds.max() ?? 0),speedLower+max(0.01,abs(speedLower)*0.1))
    errorLower = startsAtZero ? 0 : floor(DailyActivityOverviewScale.niceLowerBound(for: Double(data.samples.map(\.errors).min() ?? 0)))
    errorUpper = max(ceil(DailyActivityOverviewScale.niceUpperBound(for: Double(data.samples.map(\.errors).max() ?? 0))),errorLower+1)
  }
  var errorTickPositions: [Double] {
    stride(from:errorLower,through:errorUpper,by:max(1,ceil((errorUpper-errorLower)/4)))
      .map { ($0-errorLower)/(errorUpper-errorLower) }
  }
  func speedPosition(_ wpm: Double) -> Double { (unit.converted(wpm:wpm)-speedLower)/(speedUpper-speedLower) }
  func errorPosition(_ errors: Int) -> Double { (Double(errors)-errorLower)/(errorUpper-errorLower) }
  func speed(at y: Double) -> Double { speedLower+y*(speedUpper-speedLower) }
  func errors(at y: Double) -> Double { errorLower+y*(errorUpper-errorLower) }
}

@MainActor @Observable final class AccountResultChartLoader {
  enum State: Equatable { case loading, unavailable, failed(String), ready(AccountResultChartData) }
  private(set) var state: State = .loading
  private var generation = UUID()
  func load(_ request: @MainActor () async throws -> AccountResultChartData?) async {
    let ticket = UUID(); generation = ticket; state = .loading
    do {
      let value = try await request()
      guard generation == ticket, !Task.isCancelled else { return }
      state = value.map(State.ready) ?? .unavailable
    } catch {
      guard generation == ticket, !Task.isCancelled else { return }
      state = .failed(error.localizedDescription)
    }
  }
}
