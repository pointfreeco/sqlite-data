import Dependencies
import GRDB

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
package struct UserDatabase {
  private let database: any DatabaseWriter
  package init(database: any DatabaseWriter) {
    self.database = database
  }

  var configuration: Configuration {
    database.configuration
  }

  package func write<T: Sendable>(
    _ updates: @escaping @Sendable (Database) throws -> T
  ) async throws -> T {
    try await withEscapedDependencies { dependencies in
      try await database.write { db in
        try SyncEngine.$_isSynchronizingChanges.withValue(true) {
          try dependencies.yield {
            try updates(db)
          }
        }
      }
    }
  }

  package func read<T: Sendable>(
    _ updates: @escaping @Sendable (Database) throws -> T
  ) async throws -> T {
    try await withEscapedDependencies { dependencies in
      try await database.read { db in
        try SyncEngine.$_isSynchronizingChanges.withValue(true) {
          try dependencies.yield {
            try updates(db)
          }
        }
      }
    }
  }

  @_disfavoredOverload
  package func write<T>(
    _ updates: (Database) throws -> T
  ) throws -> T {
    try withEscapedDependencies { dependencies in
      try database.write { db in
        try SyncEngine.$_isSynchronizingChanges.withValue(true) {
          try dependencies.yield {
            try updates(db)
          }
        }
      }
    }
  }

  @_disfavoredOverload
  package func read<T>(
    _ updates: (Database) throws -> T
  ) throws -> T {
    try withEscapedDependencies { dependencies in
      try database.read { db in
        try SyncEngine.$_isSynchronizingChanges.withValue(true) {
          try dependencies.yield {
            try updates(db)
          }
        }
      }
    }
  }
}
