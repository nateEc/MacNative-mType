enum ResultReplayAvailability {
  static func isAvailable(prompt: String, events: [TypingReplayEvent],
    configuration: TestConfiguration?) -> Bool {
    !events.isEmpty && (!prompt.isEmpty || configuration?.mode == .zen)
  }

  static func canPlay(duration: Double, events: [TypingReplayEvent], fieldPlan: FieldReplayPlan?) -> Bool {
    duration != 0 || !(fieldPlan?.actions.isEmpty ?? TypingReplay.actions(events: events).isEmpty)
  }
}
