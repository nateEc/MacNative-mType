import Foundation
import Vapor

public struct SyncChangeRequest: Content, Equatable {
    public let id: UUID
    public let type: String
    public let version: Int
    public let payload: String?
    public let isDeleted: Bool
}

public struct SyncPushRequest: Content, Equatable {
    public let changes: [SyncChangeRequest]
}

public struct SyncChangeResponse: Content, Equatable, Identifiable {
    public let id: UUID
    public let type: String
    public let version: Int
    public let payload: String?
    public let isDeleted: Bool
    public let cursor: Int
    public let updatedAt: Date
}

public enum SyncChangeStatus: String, Content, Equatable {
    case accepted
    case conflict
}

public struct SyncPushResult: Content, Equatable {
    public let id: UUID
    public let status: SyncChangeStatus
    public let serverVersion: Int
}

public struct SyncPushResponse: Content, Equatable {
    public let results: [SyncPushResult]
    public let nextCursor: Int
}

public struct SyncPullResponse: Content, Equatable {
    public let changes: [SyncChangeResponse]
    public let nextCursor: Int
}

public struct SyncCursorQuery: Content {
    public let cursor: Int?
}
