import Vapor

public struct ProfileSearchQuery: Content {
    public let query: String?
    public let limit: Int?
}
