import XCTest
@testable import Typebar

final class LivePracticeContentContinuationPolicyTests: XCTestCase {
  @MainActor func testAllImmediateWebsiteInputOptionsRetainContentButNotInitialReplacementAdmission() throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft("{}", pointsPerRem: 16, context: .init())
    let original = TestConfiguration.words(201).with(modifiers: [.referenceStream])
    for target in InputRuleCommandCatalog.items.compactMap({ InputRuleCommandCatalog.target(for: $0.id) }) {
      if case .lazyMode = target { continue }
      let edited = try WebsiteConfigNativeProfile.editDraft(draft, key: target.websiteKey, value: target.websiteValue,
        pointsPerRem: 16, context: .init(), testActive: false)
      let changed = edited.inputRules.applying(to: original)
      XCTAssertTrue(LivePracticeContentContinuationPolicy.matchesGeneration(current: changed, requested: original), target.websiteKey)
      if changed != original {
        XCTAssertFalse(LivePracticeContentReplacementPolicy.shouldApply(hasStarted: false,
          currentConfiguration: changed, requestedConfiguration: original))
      }
    }
  }
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
    var changed = original; changed.difficulty = .expert
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
