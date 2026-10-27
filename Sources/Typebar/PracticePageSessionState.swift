import Foundation

enum PracticePageSessionStateError: Error { case wrongOwner, stale, incomplete, invalidAttempt, locked }

/// The real page's attempt and resource presentation change as one value.
/// A resource-only publication remains display-only and never owns a session.
@MainActor struct PracticePageSessionState {
  var session = TestSessionFactory.make(configuration: TypebarInitialTestSelection.configuration).withElapsedClock()
  var presentation: WebsiteConfigPublishedPresentation?
  private(set) var practice: WebsiteConfigSessionBuilder.Prepared?
  var priorAttemptLedger = PriorAttemptLedger()
  /// Accepted departure, including an init failure. Clears on a new attempt.
  var restartDepartureAttemptID: UUID?
  var configurationDeparture: WebsiteConfigCommitCoordinator.ConfigurationDeparture?
  var savedApplication: WebsiteConfigCommitCoordinator.SavedApplication?
  var sharedReceipt: WebsiteConfigCommitCoordinator.SharedReceipt?
  struct QuoteInitializationCheckpoint {
    let id = UUID()
    let publication: UUID
    let configurationDeparture: UUID?
    let progress: WebsiteConfigSessionBuilder.QuoteInitialization
  }
  var quoteInitialization: QuoteInitializationCheckpoint?
  var currentQuoteInitialization: WebsiteConfigSessionBuilder.QuoteInitialization? {
    guard let checkpoint = quoteInitialization,
      checkpoint.publication == presentation?.publication.applicationID,
      checkpoint.configurationDeparture == configurationDeparture?.id else { return nil }
    return checkpoint.progress
  }

  mutating func retainingSharedScope(_ scope: WebsiteConfigSessionBuilder.Scope) {
    guard let previous = practice else { return }
    practice = .init(session: previous.session, scope: scope, quote: previous.quote,
      external: previous.external, repetition: previous.repetition)
  }

  func applying(_ presentation: WebsiteConfigPublishedPresentation, owner: UUID,
    router: PreferenceConfigurationSaveRouter) throws -> Self {
    let publication = presentation.publication
    guard publication.owner == owner else { throw PracticePageSessionStateError.wrongOwner }
    guard publication.isCurrentDelivery(owner: owner, router: router) else { throw PracticePageSessionStateError.stale }
    if self.presentation?.publication.applicationID == publication.applicationID, self.practice != nil { return self }
    guard !session.hasStarted || session.isFinished || !session.configuration.modifiers.contains(.noQuit) else {
      throw PracticePageSessionStateError.locked
    }
    guard let practice = publication.practice, let seed = publication.session,
      publication.font != nil, publication.background != nil else { throw PracticePageSessionStateError.incomplete }
    guard !seed.hasStarted, !seed.isFinished,
      seed.automaticInputAttemptID == practice.session.automaticInputAttemptID,
      seed.configuration == practice.session.configuration,
      seed.prompt.utf16.elementsEqual(practice.session.prompt.utf16) else { throw PracticePageSessionStateError.invalidAttempt }
    var result = self
    result.session = seed.withElapsedClock()
    result.presentation = presentation
    result.practice = practice
    result.restartDepartureAttemptID = nil
    result.configurationDeparture = nil
    result.quoteInitialization = nil
    return result
  }
}
