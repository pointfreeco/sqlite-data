public extension DatabaseWriter {
  func writeWithUndoGroup<T>(
    _ description: String,
    _ updates: (Database) throws -> T
  ) throws -> T {
    @Dependency(\.defaultUndoManager) var defaultUndoManager
    let undoManager =
      (defaultUndoManager?.manages(database: self) == true ? defaultUndoManager : nil)
      ?? UndoManager.manager(for: self)
    if let undoManager {
      return try undoManager.withGroup(description, updates)
    }
    return try write(updates)
  }

  func writeWithUndoGroup<T: Sendable>(
    _ description: String,
    _ updates: @Sendable (Database) throws -> T
  ) async throws -> T {
    @Dependency(\.defaultUndoManager) var defaultUndoManager
    let undoManager =
      (defaultUndoManager?.manages(database: self) == true ? defaultUndoManager : nil)
      ?? UndoManager.manager(for: self)
    if let undoManager {
      return try await undoManager.withGroup(description, updates)
    }
    return try await write(updates)
  }
}
