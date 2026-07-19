/// Whether an undo manager operation is an undo or a redo.
public enum UndoAction: Sendable {
  /// An undo operation that reverts the most-recently-recorded change.
  case undo
  /// A redo operation that re-applies the most-recently-undone change.
  case redo
}
