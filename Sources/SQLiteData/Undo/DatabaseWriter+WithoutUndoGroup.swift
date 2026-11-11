public extension DatabaseWriter {
  /// Executes work while undo trigger recording is disabled.
  ///
  /// Use this to perform writes that should not become undoable entries.
  ///
  /// This differs from using `write { ... }` directly instead of
  /// `writeWithUndoGroup(...)`: a plain `write` still allows undo triggers to record inverse SQL
  /// in the undo log table, while this API suppresses trigger recording entirely.
  @discardableResult
  func writeWithoutUndoGroup<T>(
    _ operation: () throws -> T
  ) rethrows -> T {
    try $_isUndoRecordingDisabled.withValue(true) {
      try operation()
    }
  }

  /// Executes async work while undo trigger recording is disabled.
  ///
  /// Use this to perform writes that should not become undoable entries.
  ///
  /// This differs from using `write { ... }` directly instead of
  /// `writeWithUndoGroup(...)`: a plain `write` still allows undo triggers to record inverse SQL
  /// in the undo log table, while this API suppresses trigger recording entirely.
  @discardableResult
  func writeWithoutUndoGroup<T: Sendable>(
    _ operation: @Sendable () async throws -> T
  ) async rethrows -> T {
    try await $_isUndoRecordingDisabled.withValue(true) {
      try await operation()
    }
  }
}
