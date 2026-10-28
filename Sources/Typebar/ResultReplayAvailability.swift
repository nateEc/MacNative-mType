enum ResultReplayAvailability {
  static func duration(events: [TypingReplayEvent], fieldPlan: FieldReplayPlan?) -> Double {
    if let fieldPlan { return fieldPlan.actions.last?.offset ?? 0 }
    return TypingReplay.actions(events: events).last?.primitives.last?.offset ?? 0
  }

  static func isAvailable(prompt: String, events: [TypingReplayEvent],
    configuration: TestConfiguration?) -> Bool {
    !events.isEmpty && (!prompt.isEmpty || configuration?.mode == .zen)
  }

  static func canPlay(events: [TypingReplayEvent], fieldPlan: FieldReplayPlan?) -> Bool {
    !(fieldPlan?.actions.isEmpty ?? TypingReplay.actions(events: events).isEmpty)
  }
}
