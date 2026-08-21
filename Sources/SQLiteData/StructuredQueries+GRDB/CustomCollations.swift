import GRDBSQLite
public import StructuredQueriesSQLiteCore

#if EXCLUDE_EXPORTS
  // NB: This 'public import' breaks the '@_exported import'.
  public import class GRDB.Database
#endif

extension Database {
  /// Adds a user-defined `@DatabaseCollation` to a connection.
  ///
  /// - Parameter collation: A database collation to add.
  public func add(collation: some DatabaseCollation) {
    sqlite3_create_collation_v2(
      sqliteConnection,
      collation.name,
      SQLITE_UTF8,
      Unmanaged.passRetained(DatabaseCollationDefinition(collation)).toOpaque(),
      { context, lhsCount, lhs, rhsCount, rhs in
        switch Unmanaged<DatabaseCollationDefinition>
          .fromOpaque(context!)
          .takeUnretainedValue()
          .collation
          .compare(
            UnsafeRawBufferPointer(start: lhs, count: Int(lhsCount)),
            UnsafeRawBufferPointer(start: rhs, count: Int(rhsCount))
          )
        {
        case .ascending: return -1
        case .same: return 0
        case .descending: return 1
        }
      },
      { context in
        guard let context else { return }
        Unmanaged<DatabaseCollationDefinition>.fromOpaque(context).release()
      }
    )
  }

  /// Deletes a user-defined `@DatabaseCollation` from a connection.
  ///
  /// - Parameter collation: A database collation to delete.
  public func remove(collation: some DatabaseCollation) {
    sqlite3_create_collation_v2(
      sqliteConnection,
      collation.name,
      SQLITE_UTF8,
      nil,
      nil,
      nil
    )
  }
}

private final class DatabaseCollationDefinition {
  let collation: any DatabaseCollation
  init(_ collation: some DatabaseCollation) {
    self.collation = collation
  }
}
