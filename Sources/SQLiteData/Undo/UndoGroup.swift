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

  package init(
    id: UUID = UUID(),
    description: String,
    origin: Origin,
    date: Date
  ) {
    self.id = id
    self.description = description
    self.origin = origin
    self.date = date
  }
}
