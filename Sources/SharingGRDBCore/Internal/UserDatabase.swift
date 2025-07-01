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

  func write<T: Sendable>(
    _ updates: @escaping @Sendable (Database) throws -> T
  ) async throws -> T {
    try await withEscapedDependencies { dependencies in
      try await database.write { db in
        try SyncEngine.$isUpdatingWithServerRecord.withValue(true) {
          try dependencies.yield {
            try updates(db)
          }
        }
      }
    }
  }

  func read<T: Sendable>(
    _ updates: @escaping @Sendable (Database) throws -> T
  ) async throws -> T {
    try await withEscapedDependencies { dependencies in
      try await database.read { db in
        try SyncEngine.$isUpdatingWithServerRecord.withValue(true) {
          try dependencies.yield {
            try updates(db)
          }
        }
      }
    }
  }

  @_disfavoredOverload
  func write<T>(
    _ updates: (Database) throws -> T
  ) throws -> T {
    try withEscapedDependencies { dependencies in
      try database.write { db in
        try SyncEngine.$isUpdatingWithServerRecord.withValue(true) {
          try dependencies.yield {
            try updates(db)
          }
        }
      }
    }
  }

  @_disfavoredOverload
  func read<T>(
    _ updates: (Database) throws -> T
  ) throws -> T {
    try withEscapedDependencies { dependencies in
      try database.read { db in
        try SyncEngine.$isUpdatingWithServerRecord.withValue(true) {
          try dependencies.yield {
            try updates(db)
          }
        }
      }
    }
  }

  package func userWrite<T: Sendable>(
    _ updates: @escaping @Sendable (Database) throws -> T
  ) async throws -> T {
    try await withEscapedDependencies { dependencies in
      try await database.write { db in
        try dependencies.yield {
          try updates(db)
        }
      }
    }
  }

  package func userRead<T: Sendable>(
    _ updates: @escaping @Sendable (Database) throws -> T
  ) async throws -> T {
    try await withEscapedDependencies { dependencies in
      try await database.read { db in
        try dependencies.yield {
          try updates(db)
        }
      }
    }
  }

  @_disfavoredOverload
  package func userWrite<T>(
    _ updates: (Database) throws -> T
  ) throws -> T {
    try withEscapedDependencies { dependencies in
      try database.write { db in
        try dependencies.yield {
          try updates(db)
        }
      }
    }
  }

  @_disfavoredOverload
  package func userRead<T>(
    _ updates: (Database) throws -> T
  ) throws -> T {
    try withEscapedDependencies { dependencies in
      try database.read { db in
        try dependencies.yield {
          try updates(db)
        }
      }
    }
  }
}
