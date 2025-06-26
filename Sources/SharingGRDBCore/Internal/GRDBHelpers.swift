import Dependencies
import GRDB

extension DatabaseWriter {
  // NB: The asynchronous 'write' method on 'DatabaseWriter' uses an escaping closure, which means
  //     task locals are lost when execute database queries. This method propagates certain task
  //     locals across that escaping closure boundary, which are used in our database triggers.
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  package func asyncWrite<T: Sendable>(
    _ updates: @escaping @Sendable (Database) throws -> T
  ) async throws -> T {
    let currentIsUpdatingWithServerRecord = SyncEngine.isUpdatingWithServerRecord
    return try await withEscapedDependencies { dependencies in
      try await write { db in
        try SyncEngine.$isUpdatingWithServerRecord.withValue(currentIsUpdatingWithServerRecord) {
          try dependencies.yield {
            try updates(db)
          }
        }
      }
    }
  }
}
