import Foundation

/// A named group of database changes that can be undone or redone as a single unit.
public struct UndoGroup: Sendable, Identifiable, Equatable {
  /// A unique identifier for this group.
  public let id: UUID
  /// A human-readable description of the change, e.g. "Add reminder".
  public let description: String
  /// An identifier for the device that originated the change.
  public let deviceID: String
  /// The iCloud record name of the user who made the change, or `nil` if this is the current user
  /// or sync is not configured.
  public let userRecordName: String?
  /// The date the change was recorded.
  public let date: Date

  package init(
    id: UUID = UUID(),
    description: String,
    deviceID: String,
    userRecordName: String?,
    date: Date
  ) {
    self.id = id
    self.description = description
    self.deviceID = deviceID
    self.userRecordName = userRecordName
    self.date = date
  }
}
