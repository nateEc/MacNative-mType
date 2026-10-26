import Foundation

struct WebsiteWordNavigationEvent: Equatable {
  private let identity = UUID()
  let attemptID: UUID
  let completed: Int
  let total: Int
  let wasActive: Bool

  init(attemptID: UUID, completed: Int, total: Int, wasActive: Bool) {
    self.attemptID = attemptID; self.completed = completed; self.total = total; self.wasActive = wasActive
  }
}
