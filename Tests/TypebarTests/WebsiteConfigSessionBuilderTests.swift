import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigSessionBuilderTests: XCTestCase {
  private func draft(_ json: String) throws -> WebsiteConfigNativeDraft {
    try WebsiteConfigNativeProfile.prepareDraft(json, pointsPerRem: 16, context: .init(authenticated: true))
  }
  private func quote(_ id: String, _ length: QuoteLength, text: String = "ab") -> OfflineQuote {
    .init(id: id, title: "Owned builder fixture", text: text, language: .english, length: length)
  }
  func testWebsiteRandomFunboxesUseEntropyInsteadOfNativeIndexSequences() async throws {
    for (name, unit, expected, calls) in [
      ("binary", 0.5, "10000000", 1), ("gibberish", 0.0, "a", 2),
      ("ascii", 0.5, "PPPPPP", 7), ("specials", 0.0, "`", 2),
      ("hexadecimal", 0.5, "808080", 4),
    ] {
      let value = try draft("{\"mode\":\"words\",\"words\":3,\"funbox\":[\"\(name)\"]}")
      var samples = 0, rank = 0
      let result = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: .init(),
        random: .init(wordIndex: { rank += 1; return rank }, contentUnit: { samples += 1; return unit }))
      XCTAssertEqual(result.session.prompt, Array(repeating: expected, count: 3).joined(separator: " "), name)
      XCTAssertEqual(samples, calls * 3, name)
      XCTAssertEqual(result.session.generatedWordReplayHistory?.count, 3, name)
    }
  }

  func testWebsiteNetworkSourcesUseRandomSegmentsAndOnlyPunctuateWhenEnabled() async throws {
    for (name, unit, punctuation, expected, draws) in [
      ("IPv4", 0.5, false, "128.128.128.128", 4),
      ("IPv6", 0.5, false, Array(repeating: "8000", count: 8).joined(separator: ":"), 8),
      ("IPv4", 0.0, false, "0.0.0.0", 4),
      ("IPv6", 0.0, false, Array(repeating: "0000", count: 8).joined(separator: ":"), 8),
      ("IPv4", 0.0, true, "0.0.0.0/8", 6),
      ("IPv6", 0.0, true, "::/64", 10),
    ] {
      let value = try draft("{\"mode\":\"words\",\"words\":2,\"punctuation\":\(punctuation),\"funbox\":[\"\(name)\"]}")
      var samples = 0
      let result = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: .init(),
        random: .init(contentUnit: { samples += 1; return unit }))
      XCTAssertEqual(result.session.prompt, "\(expected) \(expected)", name)
      XCTAssertEqual(samples, draws * 2, name)
      XCTAssertEqual(result.session.generatedWordReplayHistory?.count, 2, name)
    }
  }

  func testTimedNetworkContinuationAppendsRandomTargetsAndRetainsPrefetchedHistory() async throws {
    for name in ["IPv4", "IPv6"] {
      let value = try draft("{\"mode\":\"time\",\"time\":60,\"funbox\":[\"\(name)\"]}")
      let ready = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: .init(),
        random: .init(contentUnit: { 0.5 }))
      var session = ready.session
      let initial = try XCTUnwrap(session.generatedWordReplayHistory?.count)
      let first = try XCTUnwrap(session.prompt.split(separator: " ").first)
      session.insertBatch(String(first) + " ")
      XCTAssertEqual(session.outcome, .active)
      let history = try XCTUnwrap(session.generatedWordReplayHistory)
      XCTAssertGreaterThan(history.count, initial)
      let tail = try XCTUnwrap(history.word(at: history.count - 1)?.target)
      let parts = tail.split(separator: name == "IPv4" ? "." : ":")
      XCTAssertEqual(parts.count, name == "IPv4" ? 4 : 8)
      if name == "IPv6" { XCTAssertTrue(parts.allSatisfy { $0.count == 4 }) }
      XCTAssertFalse(tail.contains("/"))
      let repeated = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: .init(),
        attemptSource: .repeatedWords(history, repeatedPace: false),
        random: .init(contentUnit: { XCTFail("Prefetched history must not regenerate"); return 0 }))
      XCTAssertEqual(repeated.session.generatedWordReplayHistory?.word(at: history.count - 1)?.target, tail)
    }
  }

  func testWebsiteHexadecimalPunctuationUsesItsOwnPrefixAndKeepsLowercaseBytes() async throws {
    let value = try draft(#"{"mode":"words","words":2,"funbox":["hexadecimal"],"punctuation":true}"#)
    let result = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: .init(),
      random: .init(contentUnit: { 0.5 }))
    XCTAssertEqual(result.session.prompt, "0x808080 0x808080")
  }
  func testWebsiteRandomSourcesReplayOwnedTargetsWithoutDrawingAgain() async throws {
    for kind in WebsiteRandomWordGenerator.Kind.allCases {
      let value = try draft("{\"mode\":\"words\",\"words\":3,\"funbox\":[\"\(kind.rawValue)\"]}")
      let original = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: .init(),
        random: .init(contentUnit: { 0.5 }))
      let history = try XCTUnwrap(original.session.generatedWordReplayHistory)
      let repeated = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: .init(),
        attemptSource: .repeatedWords(history, repeatedPace: true),
        random: .init(wordIndex: { XCTFail("Repeat cannot select another base word"); return 0 },
          contentUnit: { XCTFail("Repeat cannot regenerate a source word"); return 0 }))
      XCTAssertEqual(repeated.session.prompt, original.session.prompt, kind.rawValue)
      XCTAssertEqual(repeated.session.generatedWordReplayHistory?.count, history.count)
    }
  }

  func testWholePreviewUsesRandomSourceAndRetainsEveryOwnedWord() async throws {
    for (name, expected, calls) in [("binary", "10000000", 1), ("ascii", "PPPPPP", 7),
      ("IPv4", "128.128.128.128", 4),
      ("IPv6", Array(repeating: "8000", count: 8).joined(separator: ":"), 8)] {
      let value = try draft("{\"mode\":\"words\",\"words\":1001,\"showAllLines\":true,\"funbox\":[\"\(name)\"]}")
      var samples = 0
      let result = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: .init(),
        random: .init(contentUnit: { samples += 1; return 0.5 }))
      XCTAssertEqual(result.session.prompt, Array(repeating: expected, count: 1001).joined(separator: " "))
      XCTAssertEqual(samples, calls * 1001)
      XCTAssertEqual(result.session.generatedWordReplayHistory?.count, 1001)
    }
  }
  func testWebsiteHexadecimalRespectsOriginalPunctuationLanguageMetadata() async throws {
    let value = try draft(#"{"mode":"words","words":2,"language":"typing_of_the_dead","funbox":["hexadecimal"],"punctuation":true}"#)
    let result = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: .init(),
      random: .init(contentUnit: { 0.5 }))
    XCTAssertEqual(result.session.prompt, "808080 808080")
  }

  func testInvalidWebsiteEntropyFailsPreparationRatherThanPublishingAnEmptyAttempt() async throws {
    let value = try draft(#"{"mode":"words","words":3,"funbox":["binary"]}"#)
    do {
      _ = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: .init(),
        random: .init(contentUnit: { .nan }))
      XCTFail("Invalid entropy produced an attempt")
    } catch WebsiteConfigSessionBuildError.generationFailed {}
  }
  func testRebasedFiniteWordEndRemovesOnlyItsCommitWithoutMutatingHistory() async throws {
    var history = GeneratedWordReplayHistory(noSpace: false)
    history.append(source: "a", target: "a\n")
    history.append(source: "b", target: "b\n")
    history.append(source: "c", target: "c")
    let result = try await WebsiteConfigSessionBuilder.prepare(draft: draft(#"{"mode":"words","words":2}"#),
      scope: .init(), attemptSource: .repeatedWords(history, repeatedPace: false),
      random: .init(wordIndex: { XCTFail("Cached target cannot draw"); return 0 }))
    XCTAssertEqual(result.session.prompt, "a\nb")
    XCTAssertEqual(result.session.generatedWordReplayHistory?.word(at: 1)?.target, "b\n")
    XCTAssertEqual(result.session.generatedWordReplayHistory?.count, 3)
  }
  func testRebasedNoSpaceWordsKeepFusingUnicodeTargetsAsOwnedWords() async throws {
    var history = GeneratedWordReplayHistory(noSpace: true)
    history.append(source: "first", target: "🇺")
    history.append(source: "second", target: "🇸")
    history.append(source: "third", target: "z")
    let result = try await WebsiteConfigSessionBuilder.prepare(draft: draft(#"{"mode":"words","words":2,"funbox":["nospace"]}"#),
      scope: .init(), attemptSource: .repeatedWords(history, repeatedPace: false),
      random: .init(wordIndex: { XCTFail("Owned Unicode targets cannot draw"); return 0 }))
    XCTAssertTrue(result.session.prompt.utf16.elementsEqual("🇺🇸".utf16))
    XCTAssertEqual(result.session.generatedWordReplayHistory?.count, 3)
    XCTAssertEqual(result.session.generatedWordReplayHistory?.word(at: 0)?.target, "🇺")
    XCTAssertEqual(result.session.generatedWordReplayHistory?.word(at: 1)?.target, "🇸")
  }
  func testCustomSessionUsesWholeDraftRulesAndOrderedEffectsWithoutLegacySelectionLeaks() async throws {
    let value = try draft(#"{"mode":"custom","difficulty":"expert","strictSpace":true,"funbox":["ddoouubblleedd","ddoouubblleedd","rot13"],"time":47,"words":83}"#)
    let scope = WebsiteConfigSessionBuilder.Scope(customText: "ab")
    let result = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: scope)
    XCTAssertEqual(result.session.configuration.mode, .custom)
    XCTAssertEqual(result.session.configuration.difficulty, .expert)
    XCTAssertTrue(result.session.configuration.rules.strictSpace)
    XCTAssertEqual(result.session.prompt, "nnnnoooo")
    XCTAssertEqual(result.parameterMemory.duration, 47)
    XCTAssertEqual(result.parameterMemory.wordLimit, 83)
    XCTAssertNil(result.session.configuration.challengeID)
  }
  func testQuoteWeightsSurviveActualFactoryAndOnlyReturnedQueueAdvances() async throws {
    let value = try draft(#"{"mode":"quote","quoteLength":[0,0,1]}"#)
    let catalog = [quote("short", .short), quote("medium", .medium, text: "cd")]
    var scope = WebsiteConfigSessionBuilder.Scope()
    let random = WebsiteConfigSessionBuilder.Random(quoteIndex: { _ in 0 })
    var selected: [String] = []
    for _ in 0..<3 {
      let result = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: scope,
        loadQuotes: { _ in catalog }, random: random)
      selected.append(try XCTUnwrap(result.quote?.id))
      XCTAssertEqual(result.quoteSampler?.cycleSize, 3)
      XCTAssertEqual(result.session.prompt, result.quote?.text)
      scope.quoteSampler = result.quoteSampler
    }
    XCTAssertEqual(selected, ["short", "short", "medium"])
  }
  func testMissingQuoteCatalogRequestsSourceRecoveryInsteadOfEnglishFallback() async throws {
    let value = try draft(#"{"mode":"quote"}"#)
    do {
      _ = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: .init(), loadQuotes: { _ in [] })
      XCTFail("Missing quotes silently became another prompt")
    } catch WebsiteConfigSessionBuildError.reconfigurationRequired(let changes) {
      XCTAssertEqual(changes, ["mode": .string("words")])
    }
  }

  func testAllModesAndIndependentCustomMemoriesReachActualEngine() async throws {
    let memory = TypebarTestParameterMemory(duration: 11, wordLimit: 12,
      customTextDuration: 7, customTextWordLimit: 4, customTextSectionLimit: 2)
    for completion in [CustomTextCompletion.finish, .time, .words, .sections] {
      let value = try draft(#"{"mode":"custom","time":47,"words":83}"#)
      let scope = WebsiteConfigSessionBuilder.Scope(parameterMemory: memory, customText: "ab|cd",
        customCompletion: completion, customPipeDelimiter: true)
      let result = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: scope)
      XCTAssertEqual(result.session.configuration.duration, completion == .time ? 7 : nil)
      XCTAssertEqual(result.session.configuration.wordLimit, completion == .words ? 4 : nil)
      XCTAssertEqual(result.session.configuration.customTextSectionLimit, 2)
      XCTAssertEqual(result.parameterMemory.customTextDuration, 7)
      XCTAssertEqual(result.parameterMemory.customTextWordLimit, 4)
      XCTAssertEqual(result.parameterMemory.customTextSectionLimit, 2)
      XCTAssertEqual(result.parameterMemory.duration, 47)
      XCTAssertEqual(result.parameterMemory.wordLimit, 83)
    }
    for mode in ["time", "words", "zen"] {
      let value = try draft("{\"mode\":\"\(mode)\",\"time\":0,\"words\":0}")
      let result = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: .init(),
        loadQuotes: { _ in XCTFail("Non-quote path requested quotes"); return [] })
      XCTAssertEqual(result.session.configuration.mode.rawValue, mode)
      XCTAssertEqual(result.session.prompt.isEmpty, mode == "zen")
      if mode != "zen" { XCTAssertTrue(result.session.configuration.isInfinite) }
    }
  }

  func testExplicitCustomSourcesRejectUnavailableStateInsteadOfPlaceholderAndRetainLongText() async throws {
    let value = try draft(#"{"mode":"custom"}"#)
    for scope in [WebsiteConfigSessionBuilder.Scope(), .init(customText: "ab", customTextRecoveryBlocked: true)] {
      do {
        _ = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: scope)
        XCTFail("Unavailable custom source generated a placeholder")
      } catch WebsiteConfigSessionBuildError.customTextUnavailable {}
    }
    let text = Array(repeating: "owned", count: 2300).joined(separator: " ")
    let result = try await WebsiteConfigSessionBuilder.prepare(draft: value,
      scope: .init(customText: "owned", finiteTextSource: text))
    XCTAssertTrue(result.session.prompt.hasPrefix("owned"))
    XCTAssertEqual(result.scope.finiteTextSource, text)
  }

  func testSelectedFavoritesAndEmptyGroupsKeepSourceRecoveryAndDoNotFilterStaleIDs() async throws {
    let catalog = [quote("short", .short)]
    let selected = try await WebsiteConfigSessionBuilder.prepare(draft: draft(#"{"mode":"quote","quoteLength":[-2]}"#),
      scope: .init(selectedQuoteID: "short"), loadQuotes: { _ in catalog })
    XCTAssertEqual(selected.quote?.id, "short")
    XCTAssertEqual(selected.session.configuration.quoteSelectionMode, .search)
    for (groups, scope) in [
      ("[-2]", WebsiteConfigSessionBuilder.Scope(selectedQuoteID: "missing")),
      ("[-3,0]", .init(favoriteQuoteIDs: ["short", "missing"])),
      ("[]", .init())
    ] {
      do {
        _ = try await WebsiteConfigSessionBuilder.prepare(draft: draft("{\"mode\":\"quote\",\"quoteLength\":\(groups)}"),
          scope: scope, loadQuotes: { _ in catalog }, random: .init(quoteIndex: { $0 - 1 }))
        XCTFail("Unavailable selection silently substituted a quote")
      } catch WebsiteConfigSessionBuildError.reconfigurationRequired(let changes) {
        XCTAssertEqual(changes, ["quoteLength": .array((0...3).map { .number(Double($0)) })])
      }
    }
  }

  func testQueueIdentityIncludesCatalogAndSelectionAndFailedCandidateCannotConsumeInputScope() async throws {
    let value = try draft(#"{"mode":"quote","quoteLength":[0,0,1]}"#)
    let catalog = [quote("short", .short), quote("medium", .medium)]
    let random = WebsiteConfigSessionBuilder.Random(quoteIndex: { _ in 0 })
    let first = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: .init(),
      loadQuotes: { _ in catalog }, random: random)
    let candidate = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: first.scope,
      loadQuotes: { _ in catalog }, random: random)
    let retry = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: first.scope,
      loadQuotes: { _ in catalog }, random: random)
    XCTAssertEqual(candidate.quote, retry.quote)
    let changed = [quote("replacement", .short), quote("medium", .medium)]
    let refreshed = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: candidate.scope,
      loadQuotes: { _ in changed }, random: random)
    XCTAssertEqual(refreshed.quote?.id, "replacement")
    let newSelection = try await WebsiteConfigSessionBuilder.prepare(draft: draft(#"{"mode":"quote","quoteLength":[1]}"#),
      scope: candidate.scope, loadQuotes: { _ in catalog }, random: random)
    XCTAssertEqual(newSelection.quote?.id, "medium")
    XCTAssertEqual(newSelection.quoteSampler?.cycleSize, 1)
  }

  func testInvalidPolyglotImportsUseAdmittedDefaultsAndDirectionConflictRequiresRepreparation() async throws {
    let defaults = try draft("{}").generators.polyglotLanguages
    for names in ["[]", #"["french"]"#] {
      let admitted = try draft("{\"mode\":\"words\",\"words\":3,\"funbox\":[\"polyglot\"],\"customPolyglot\":\(names)}")
      XCTAssertEqual(admitted.generators.polyglotLanguages, defaults)
      let result = try await WebsiteConfigSessionBuilder.prepare(draft: admitted, scope: .init())
      XCTAssertEqual(result.session.configuration.mixedLanguageComponents, defaults)
    }
    do {
      _ = try await WebsiteConfigSessionBuilder.prepare(draft: draft(
        #"{"mode":"words","words":3,"funbox":["polyglot"],"customPolyglot":["arabic","hebrew"]}"#), scope: .init())
      XCTFail("Direction-conflicting language changed without resource repreparation")
    } catch WebsiteConfigSessionBuildError.reconfigurationRequired(let changes) {
      XCTAssertEqual(changes, ["language": .string("arabic")])
    }
    let result = try await WebsiteConfigSessionBuilder.prepare(draft: draft(
      #"{"mode":"words","words":3,"funbox":["polyglot"],"customPolyglot":["english","german"]}"#), scope: .init())
    XCTAssertEqual(result.session.configuration.language, .mixedLanguages)
    XCTAssertEqual(result.session.configuration.mixedLanguageComponents, [.english, .german])
    XCTAssertEqual(result.session.configuration.polyglotBaseLanguage, .english)
    XCTAssertEqual(result.session.configuration.polyglotUsesPrimaryInputNormalization, true)
    XCTAssertFalse(result.session.prompt.isEmpty)
  }

  func testFiniteAllLinesAndLiveReadersUseActualGenerationWithoutSilentFallback() async throws {
    let all = try await WebsiteConfigSessionBuilder.prepare(draft: draft(
      #"{"mode":"words","words":201,"showAllLines":true,"language":"code_swift","funbox":["rot13"]}"#), scope: .init())
    XCTAssertEqual(GeneratedWordBoundPolicy.wordCount(in: all.session.prompt), 201)
    XCTAssertEqual(all.session.configuration.websiteTextAlterationOrder, [.rot13])
    let value = try draft(#"{"mode":"words","words":3,"funbox":["wikipedia","ddoouubblleedd","ddoouubblleedd","rot13"]}"#)
    do {
      _ = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: .init())
      XCTFail("Live source silently used offline content")
    } catch WebsiteConfigSessionBuildError.externalNotProvided {}
    let live = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: .init(), loadExternal: { source, config in
      XCTAssertEqual(source, .encyclopedia); XCTAssertEqual(config.wordLimit, 3)
      return .init(source: source, initial: .init(text: "ab", noSpaceBoundarySource: nil),
        continuation: .init(text: "cd ef", noSpaceBoundarySource: nil), attribution: "Owned source")
    })
    XCTAssertTrue(live.session.prompt.hasPrefix("nnnnoooo"))
    XCTAssertEqual(live.external?.attribution, "Owned source")
    for invalid in [WebsiteConfigSessionBuilder.External(source: .poetry,
      initial: .init(text: "ab", noSpaceBoundarySource: nil), continuation: nil),
      .init(source: .encyclopedia, initial: .init(text: "", noSpaceBoundarySource: nil), continuation: nil)] {
      do {
        _ = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: .init(), loadExternal: { _, _ in invalid })
        XCTFail("Wrong or empty live source admitted")
      } catch WebsiteConfigSessionBuildError.invalidExternalSource {}
    }
  }
  func testCanonicallyEqualCatalogTextStillRefreshesExactTargetUnits() async throws {
    let value = try draft(#"{"mode":"quote","quoteLength":[0]}"#)
    let composed = quote("same", .short, text: "\u{00e9}")
    let decomposed = quote("same", .short, text: "e\u{0301}")
    XCTAssertEqual(composed.text, decomposed.text)
    XCTAssertNotEqual(Array(composed.text.utf16), Array(decomposed.text.utf16))
    let first = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: .init(), loadQuotes: { _ in [composed] })
    let next = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: first.scope, loadQuotes: { _ in [decomposed] })
    XCTAssertEqual(Array(try XCTUnwrap(next.quote).text.utf16), Array(decomposed.text.utf16))
    XCTAssertEqual(Array(next.session.prompt.utf16), Array(decomposed.text.utf16))
  }
  func testIncompatibleLiveLanguageNeverFallsIntoOfflineFactory() async throws {
    for name in ["wikipedia", "poetry"] {
      let value = try draft("{\"mode\":\"words\",\"words\":3,\"language\":\"code_swift\",\"funbox\":[\"\(name)\"]}")
      XCTAssertFalse(value.generators.requestedModifiers.isEmpty, "Fixture must retain the requested source")
      do {
        _ = try await WebsiteConfigSessionBuilder.prepare(draft: value, scope: .init(), loadExternal: { _, _ in
          XCTFail("An incompatible transport must not be activated")
          throw WebsiteConfigSessionBuildError.invalidExternalSource
        })
        XCTFail("Unsupported live language silently practiced an offline substitute")
      } catch WebsiteConfigSessionBuildError.unrepresentableConfiguration {}
    }
  }
}
