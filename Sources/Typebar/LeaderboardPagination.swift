import Foundation

/// Keeps page navigation honest when talking to mixed versions of the
/// self-hosted service. Older servers return an entries-only payload, so the
/// client must never infer later pages from a partial first response.
enum LeaderboardPaginationPolicy {
    static let preferredPageSize = 50

    static func isAvailable(total: Int?, pageSize: Int) -> Bool {
        guard let total else { return false }
        return total >= 0 && pageSize > 0
    }

    static func lastPageIndex(total: Int, pageSize: Int) -> Int {
        guard total > 0, pageSize > 0 else { return 0 }
        return (total - 1) / pageSize
    }

    static func pageIndex(containingRank rank: Int, total: Int?, pageSize: Int) -> Int? {
        guard let total, isAvailable(total: total, pageSize: pageSize), (1...total).contains(rank) else {
            return nil
        }
        return (rank - 1) / pageSize
    }

    static func pageIndex(forDisplayPage page: Int, total: Int?, pageSize: Int) -> Int? {
        guard let total, isAvailable(total: total, pageSize: pageSize), page > 0 else {
            return nil
        }
        return min(page - 1, lastPageIndex(total: total, pageSize: pageSize))
    }
}
