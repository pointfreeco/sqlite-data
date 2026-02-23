/// A delegate that an ``UndoManager`` calls before performing an undo or redo operation.
///
/// The delegate can present a confirmation prompt, or perform any async work, before calling
/// `performAction` to commit the operation.  If `performAction` is not called, the operation is
/// cancelled and the undo/redo stacks remain unchanged.
///
/// The default implementation performs the action immediately without any confirmation.
public protocol UndoManagerDelegate: AnyObject, Sendable {
  /// Called before the undo manager performs an undo or redo operation.
  ///
  /// - Parameters:
  ///   - undoManager: The undo manager requesting the action.
  ///   - action: Whether this is an undo or redo.
  ///   - group: The group of changes that will be undone or redone.
  ///   - performAction: Call this to commit the operation.  Omitting this call cancels it.
  @MainActor
  func undoManager(
    _ undoManager: SQLiteData.UndoManager,
    willPerform action: UndoAction,
    for group: UndoGroup,
    performAction: @Sendable () async throws -> Void
  ) async throws
}

extension UndoManagerDelegate {
  /// Default implementation: immediately performs the action without confirmation.
  @MainActor
  public func undoManager(
    _ undoManager: SQLiteData.UndoManager,
    willPerform action: UndoAction,
    for group: UndoGroup,
    performAction: @Sendable () async throws -> Void
  ) async throws {
    try await performAction()
  }
}
