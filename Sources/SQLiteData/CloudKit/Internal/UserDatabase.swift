#if canImport(CloudKit)
  import CloudKit
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
      @Dependency(\.defaultUndoManager) var defaultUndoManager
      let undoManager =
        (defaultUndoManager?.manages(database: database) == true ? defaultUndoManager : nil)
        ?? UndoManager.manager(for: database)
      if let undoManager {
        return try await undoManager.withGroup(
          "Sync iCloud changes",
          deviceID: UndoManager.syncDeviceID,
          userRecordName: syncUndoUserRecordName
        ) { db in
          try $_isSynchronizingChanges.withValue(true) {
            try updates(db)
          }
        }
      }
      return try await database.write { db in
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
      @Dependency(\.defaultUndoManager) var defaultUndoManager
      let undoManager =
        (defaultUndoManager?.manages(database: database) == true ? defaultUndoManager : nil)
        ?? UndoManager.manager(for: database)
      if let undoManager {
        return try undoManager.withGroup(
          "Sync iCloud changes",
          deviceID: UndoManager.syncDeviceID,
          userRecordName: syncUndoUserRecordName
        ) { db in
          try $_isSynchronizingChanges.withValue(true) {
            try updates(db)
          }
        }
      }
      return try database.write { db in
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
    
    private var syncUndoUserRecordName: String? {
      if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *) {
        return _currentZoneID?.ownerName
      } else {
        return nil
      }
    }
  }
#endif
