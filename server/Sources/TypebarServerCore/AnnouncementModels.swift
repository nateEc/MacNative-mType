import Foundation
import Vapor

/// A small, public deployment message. Announcements never contain account,
/// practice, or device-specific data.
public enum TypebarAnnouncementLevel: String, CaseIterable, Content, Equatable {
  case notice
  case success
  case warning
}

/// Creation and deletion are guarded by the deployment moderation key at the
/// route layer. This payload remains intentionally concise so it is safe to
/// render as plain text in native clients.
public struct AnnouncementPublicationRequest: Content, Equatable {
  public let message: String
  public let level: TypebarAnnouncementLevel
  public let sticky: Bool
  public let scheduledAt: Date?

  public init(
    message: String, level: TypebarAnnouncementLevel = .notice, sticky: Bool = false,
    scheduledAt: Date? = nil
  ) {
    self.message = message
    self.level = level
    self.sticky = sticky
    self.scheduledAt = scheduledAt
  }
}

public struct PublicAnnouncementResponse: Content, Equatable, Identifiable {
  public let id: UUID
  public let message: String
  public let level: TypebarAnnouncementLevel
  public let sticky: Bool
  public let scheduledAt: Date?
  public let publishedAt: Date

  public init(
    id: UUID, message: String, level: TypebarAnnouncementLevel, sticky: Bool,
    scheduledAt: Date? = nil, publishedAt: Date
  ) {
    self.id = id
    self.message = message
    self.level = level
    self.sticky = sticky
    self.scheduledAt = scheduledAt
    self.publishedAt = publishedAt
  }
}

public struct PublicAnnouncementsResponse: Content, Equatable {
  public let announcements: [PublicAnnouncementResponse]
}
