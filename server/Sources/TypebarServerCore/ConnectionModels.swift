import Foundation
import Vapor

public struct ConnectionRequest: Content, Equatable {
    public let recipientID: UUID
}

public enum ConnectionRelation: String, Content, Equatable {
    case outgoingRequest
    case incomingRequest
    case friend
}

public struct ConnectionResponse: Content, Equatable, Identifiable {
    public let id: UUID
    public let profile: PublicProfileResponse
    public let relation: ConnectionRelation
    public let updatedAt: Date
}

public struct ConnectionsResponse: Content, Equatable {
    public let connections: [ConnectionResponse]
}

public struct ConnectionRemovalResponse: Content, Equatable {
    public let removed: Bool
}

public struct BlockedUsersResponse: Content, Equatable {
    public let profiles: [PublicProfileResponse]
}
