import Foundation
import Observation

enum QuoteRating: Int, CaseIterable, Codable {
    case down = -1
    case neutral = 0
    case up = 1
}

@Observable
final class QuoteRatingStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "typebar.quoteRatings.v1"
    private(set) var ratings: [String: QuoteRating]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.dictionary(forKey: storageKey) as? [String: Int] ?? [:]
        ratings = raw.compactMapValues(QuoteRating.init(rawValue:))
    }

    func rating(for quoteID: String) -> QuoteRating {
        ratings[quoteID] ?? .neutral
    }

    func set(_ rating: QuoteRating, for quoteID: String) {
        if rating == .neutral { ratings.removeValue(forKey: quoteID) }
        else { ratings[quoteID] = rating }
        defaults.set(ratings.mapValues(\.rawValue), forKey: storageKey)
    }
}
