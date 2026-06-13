import Foundation

/// A named group of database changes that can be undone or redone as a single unit.
public struct UndoGroup: Sendable, Identifiable, Equatable {
  /// Indicates where the change originated.
  public enum Origin: String, Sendable, Equatable {
    /// A change originated from local edits in this app instance.
    case local
    /// A change originated from synced remote updates.
    case sync
  }

  /// A unique identifier for this group.
  public let id: UUID
  /// A human-readable description of the change, e.g. "Add reminder".
  public let description: String
  /// Whether the change came from local edits or synced updates.
  public let origin: Origin
  /// The date the change was recorded.
  public let date: Date
  /// Whether this sync change came from a zone owned by another user.
  ///
  /// Always `false` for `.local` origin groups. For `.sync` origin groups, `true` indicates the
  /// change came from a shared zone (another user's data), while `false` indicates it came from
  /// the current user's private zone (likely an echo-back of the user's own changes).
  public let isSharedZoneChange: Bool

  package init(
    id: UUID = UUID(),
    description: String,
    origin: Origin,
    date: Date,
    isSharedZoneChange: Bool = false
  ) {
    self.id = id
    self.description = description
    self.origin = origin
    self.date = date
    self.isSharedZoneChange = isSharedZoneChange
  }
}
