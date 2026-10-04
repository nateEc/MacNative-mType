enum CompletedResultRepeatOrigin: CaseIterable {
  case button
  case command
}

/// Entry-point policy, not a restriction on the engine's repeatedAttempt API.
enum CompletedResultRepeatPolicy {
  static func perform(
    mode: TestMode,
    origin: CompletedResultRepeatOrigin,
    showNotice: (String) -> Void,
    repeatAttempt: () -> Void
  ) {
    // The pinned source guards the result button, but not repeatTest commands.
    if mode == .zen, origin == .button {
      showNotice("禅模式的结果按钮不支持重复测试。")
      return
    }
    repeatAttempt()
  }
}
