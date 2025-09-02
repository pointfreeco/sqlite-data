import GRDB
import SQLiteData

extension UserDatabase {
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  func userWrite<T: Sendable>(
    _ updates: @Sendable (Database) throws -> T
  ) async throws -> T {
    try await write { db in
      try SyncEngine.$_isSynchronizingChanges.withValue(false) {
        try updates(db)
      }
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  func userRead<T: Sendable>(
    _ updates: @Sendable (Database) throws -> T
  ) async throws -> T {
    try await read { db in
      try SyncEngine.$_isSynchronizingChanges.withValue(false) {
        try updates(db)
      }
    }
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  func userWrite<T>(
    _ updates: (Database) throws -> T
  ) throws -> T {
    try write { db in
      try SyncEngine.$_isSynchronizingChanges.withValue(false) {
        try updates(db)
      }
    }
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  func userRead<T>(
    _ updates: (Database) throws -> T
  ) throws -> T {
    try write { db in
      try SyncEngine.$_isSynchronizingChanges.withValue(false) {
        try updates(db)
      }
    }
  }
}
