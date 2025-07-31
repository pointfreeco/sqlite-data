import GRDB
import SharingGRDBCore

extension UserDatabase {
  func userWrite<T: Sendable>(
    _ updates: @escaping @Sendable (Database) throws -> T
  ) async throws -> T {
    try await write { db in
      try SyncEngine.$_isSynchronizingChanges.withValue(false) {
        try updates(db)
      }
    }
  }

  func userRead<T: Sendable>(
    _ updates: @escaping @Sendable (Database) throws -> T
  ) async throws -> T {
    try await read { db in
      try SyncEngine.$_isSynchronizingChanges.withValue(false) {
        try updates(db)
      }
    }
  }

  @_disfavoredOverload
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
