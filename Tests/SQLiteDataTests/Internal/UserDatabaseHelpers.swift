#if canImport(CloudKit)
  import SQLiteData

  extension UserDatabase {
    func userWrite<T: Sendable>(
      _ updates: @Sendable (Database) throws -> T
    ) async throws -> T {
      try await write { db in
        try $_isSynchronizingChanges.withValue(false) {
          try updates(db)
        }
      }
    }

    @_disfavoredOverload
    func userWrite<T>(
      _ updates: (Database) throws -> T
    ) throws -> T {
      try write { db in
        try $_isSynchronizingChanges.withValue(false) {
          try updates(db)
        }
      }
    }
  }
#endif
