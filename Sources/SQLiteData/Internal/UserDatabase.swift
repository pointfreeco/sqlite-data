import Dependencies

package struct UserDatabase {
  package let database: any DatabaseWriter
  package init(database: any DatabaseWriter) {
    self.database = database
  }

  var path: String {
    database.path
  }

  var configuration: Configuration {
    database.configuration
  }

  package func write<T: Sendable>(
    _ updates: @Sendable (Database) throws -> T
  ) async throws -> T {
    try await database.write { db in
      try $_isSynchronizingChanges.withValue(true) {
        try updates(db)
      }
    }
  }

  package func read<T: Sendable>(
    _ updates: @Sendable (Database) throws -> T
  ) async throws -> T {
    try await database.read { db in
      try updates(db)
    }
  }

  @_disfavoredOverload
  package func write<T>(
    _ updates: (Database) throws -> T
  ) throws -> T {
    try database.write { db in
      try $_isSynchronizingChanges.withValue(true) {
        try updates(db)
      }
    }
  }

  @_disfavoredOverload
  package func read<T>(
    _ updates: (Database) throws -> T
  ) throws -> T {
    try database.read { db in
      try updates(db)
    }
  }
}
