#if canImport(CloudKit)
  import Foundation
  import GRDB
  import OSLog
  @testable import SQLiteData
  import Testing

  @Suite struct MetadatabaseTests {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func inMemoryMetadatabase() throws {
      let url = try URL.metadatabase(databasePath: ":memory:", containerIdentifier: nil)
      #expect(url.isInMemory)

      let metadatabase = try defaultMetadatabase(
        logger: Logger(subsystem: "test", category: "test"),
        url: url
      )
      let mainDatabaseFile = try metadatabase.read { db in
        try String.fetchOne(db, sql: "SELECT file FROM pragma_database_list WHERE name = 'main'")
      }
      // NB: SQLite reports an empty file path for in-memory databases. A non-empty path
      //     means the metadatabase was silently created on disk.
      #expect(mainDatabaseFile == "")
    }
  }
#endif
