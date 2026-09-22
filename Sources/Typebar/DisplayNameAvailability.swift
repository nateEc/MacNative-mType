struct DisplayNameAvailabilityCheck: Hashable {
  let endpoint: String
  let name: String
}

enum DisplayNameAvailabilityState: Equatable {
  case idle
  case checking
  case available
  case unavailable
  case unavailableToCheck

  init(available: Bool?) {
    switch available {
    case .some(true):
      self = .available
    case .some(false):
      self = .unavailable
    case .none:
      self = .unavailableToCheck
    }
  }

  /// Only a definitive negative preflight may block a mutation. A missing
  /// response keeps the authoritative server-side registration or update path
  /// usable for older services and transient network failures.
  var preventsSubmission: Bool {
    switch self {
    case .checking, .unavailable:
      true
    case .idle, .available, .unavailableToCheck:
      false
    }
  }
}
