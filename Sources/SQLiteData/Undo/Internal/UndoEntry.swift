import Foundation

/// An in-memory record of a single undo or redo group's position in the undo log.
package struct UndoEntry: Sendable {
  /// The lowest `seq` value written to `sqlitedata_undo_log` by this group.
  package let begin: Int
  /// The highest `seq` value written to `sqlitedata_undo_log` by this group.
  package let end: Int
  /// The public metadata associated with this group.
  package let group: UndoGroup
}
