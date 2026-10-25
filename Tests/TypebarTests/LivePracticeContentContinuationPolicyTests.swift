import XCTest
@testable import Typebar

final class LivePracticeContentContinuationPolicyTests: XCTestCase {
  func testBlindFeedbackDoesNotRetireTheContentPullButInitialReplacementStaysStrict() {
    let original = TestConfiguration.words(201).with(modifiers: [.referenceStream])
    var changed = original; changed.rules.blindMode = true
    XCTAssertTrue(LivePracticeContentContinuationPolicy.matchesGeneration(current: changed, requested: original))
    XCTAssertFalse(LivePracticeContentReplacementPolicy.shouldApply(hasStarted: false,
      currentConfiguration: changed, requestedConfiguration: original))
  }
  func testThresholdModesMemoriesAndProjectionsDoNotRetireAnExistingContentPull() throws {
    var original = TestConfiguration.words(201).with(modifiers: [.referenceStream])
    original.rules = PracticeThresholdSource(configuration: .init()).applying(to: original.rules)
    var thresholds = PracticeThresholdConfiguration()
    try thresholds.apply(.minimumWpm(mode: .custom, customValue: 0))
    try thresholds.apply(.minimumAccuracy(mode: .custom, customValue: 91.5))
    try thresholds.apply(.minimumWordBurst(mode: .flex, customValue: 83.5))
    var changed = original
    changed.rules = PracticeThresholdSource(configuration: thresholds).applying(to: changed.rules)
    XCTAssertTrue(LivePracticeContentContinuationPolicy.matchesGeneration(current: changed, requested: original))
    XCTAssertFalse(LivePracticeContentReplacementPolicy.shouldApply(hasStarted: false,
      currentConfiguration: changed, requestedConfiguration: original), "Initial replacement must retain its stricter admission")
  }

  func testOtherRulesLanguageLimitsAndGeneratorsStillRetireThePull() {
    let original = TestConfiguration.words(201).with(modifiers: [.referenceStream])
    var changed = original; changed.rules.strictSpace = true
    XCTAssertFalse(LivePracticeContentContinuationPolicy.matchesGeneration(current: changed, requested: original))
    changed = original; changed.language = .spanish
    XCTAssertFalse(LivePracticeContentContinuationPolicy.matchesGeneration(current: changed, requested: original))
    changed = original; changed.wordLimit = 202
    XCTAssertFalse(LivePracticeContentContinuationPolicy.matchesGeneration(current: changed, requested: original))
    changed = original; changed.contentOptions.includeNumbers = true
    XCTAssertFalse(LivePracticeContentContinuationPolicy.matchesGeneration(current: changed, requested: original))
    changed = original; changed.englishVariant = .british
    XCTAssertFalse(LivePracticeContentContinuationPolicy.matchesGeneration(current: changed, requested: original))
  }
}
