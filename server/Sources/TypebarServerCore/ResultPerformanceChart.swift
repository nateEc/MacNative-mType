import Foundation
import Vapor

/// Private client-reported aggregate trace; never competitive evidence.
public struct ResultPerformanceChart: Content, Equatable, Sendable {
  public struct Sample: Content, Equatable, Sendable {
    public let elapsed: Double
    public let wpm: Double
    public let burst: Double
    public let errors: Int
    public init(elapsed: Double, wpm: Double, burst: Double, errors: Int) {
      self.elapsed = elapsed; self.wpm = wpm; self.burst = burst; self.errors = errors
    }
  }
  public let version: Int
  public let samples: [Sample]
  public init(version: Int = 1, samples: [Sample]) { self.version = version; self.samples = samples }
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
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(version: try values.decode(Int.self, forKey: .version), samples: try values.decode([Sample].self, forKey: .samples))
    guard isValid else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid anonymous performance chart")) }
  }
  public func encode(to encoder: Encoder) throws {
    guard isValid else { throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath, debugDescription: "Invalid anonymous performance chart")) }
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(version, forKey: .version); try values.encode(samples, forKey: .samples)
  }
}
