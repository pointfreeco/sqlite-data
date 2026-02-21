import Dependencies

extension DependencyValues {
  /// The default SQLiteData undo manager used by integrations when available.
  ///
  /// Configure this as early as possible in your app's lifetime, for example with
  /// `prepareDependencies`:
  ///
  /// ```swift
  /// prepareDependencies {
  ///   $0.defaultDatabase = try! appDatabase()
  ///   $0.defaultUndoManager = try! UndoManager(
  ///     for: $0.defaultDatabase,
  ///     tables: Item.self
  ///   )
  /// }
  /// ```
  ///
  /// If no default undo manager is set, SQLiteData continues to work without undo support.
  public var defaultUndoManager: UndoManager? {
    get { self[DefaultUndoManagerKey.self] }
    set { self[DefaultUndoManagerKey.self] = newValue }
  }

  private enum DefaultUndoManagerKey: DependencyKey {
    static let liveValue: UndoManager? = nil
    static let previewValue: UndoManager? = nil
    static let testValue: UndoManager? = nil
  }
}
