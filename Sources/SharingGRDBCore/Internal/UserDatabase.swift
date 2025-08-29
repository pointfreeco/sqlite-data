import Dependencies
import GRDB

package struct UserDatabase {
  private let database: any DatabaseWriter
  package init(database: any DatabaseWriter) {
    self.database = database
  }

  var path: String {
    database.path
  }

  var configuration: Configuration {
    database.configuration
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  package func write<T: Sendable>(
    _ updates: @Sendable (Database) throws -> T
  ) async throws -> T {
    try await database.write { db in
      try SyncEngine.$_isSynchronizingChanges.withValue(true) {
        try updates(db)
      }
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  package func read<T: Sendable>(
    _ updates: @Sendable (Database) throws -> T
  ) async throws -> T {
    try await database.read { db in
      try SyncEngine.$_isSynchronizingChanges.withValue(true) {
        try updates(db)
      }
    }
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  package func write<T>(
    _ updates: (Database) throws -> T
  ) throws -> T {
    try database.write { db in
      try SyncEngine.$_isSynchronizingChanges.withValue(true) {
        try updates(db)
      }
    }
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  package func read<T>(
    _ updates: (Database) throws -> T
  ) throws -> T {
    try database.read { db in
      try SyncEngine.$_isSynchronizingChanges.withValue(true) {
        try updates(db)
      }
    }
  }
}
