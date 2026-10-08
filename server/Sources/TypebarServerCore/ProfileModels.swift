import Vapor

public struct ProfileSearchQuery: Content {
    public let query: String?
    public let limit: Int?
}

public struct ProfileNameLookupQuery: Content { public let name: String }

public struct ProfileNameLookupResponse: Content {
    public let version: Int
    public let profile: PublicProfileResponse?
}
