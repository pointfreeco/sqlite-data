/// Executes work while undo trigger recording is disabled.
///
/// Use this to perform writes that should not become undoable entries.
@discardableResult
public func withoutUndo<T>(
  _ operation: () throws -> T
) rethrows -> T {
  try $_isUndoRecordingDisabled.withValue(true) {
    try operation()
  }
}

/// Executes async work while undo trigger recording is disabled.
///
/// Use this to perform writes that should not become undoable entries.
@discardableResult
public func withoutUndo<T: Sendable>(
  _ operation: @Sendable () async throws -> T
) async rethrows -> T {
  try await $_isUndoRecordingDisabled.withValue(true) {
    try await operation()
  }
}
