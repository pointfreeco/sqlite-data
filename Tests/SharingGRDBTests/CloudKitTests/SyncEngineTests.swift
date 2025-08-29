import CloudKit
import CustomDump
import DependenciesTestSupport
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class SyncEngineTests {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func inMemory() throws {
      #expect(URL(string: "")?.isInMemory == nil)
      #expect(URL(string: ":memory:")?.isInMemory == true)
      #expect(URL(string: ":memory:?cache=shared")?.isInMemory == true)
      #expect(URL(string: "file::memory:")?.isInMemory == true)
      #expect(URL(string: "file:memdb1?mode=memory&cache=shared")?.isInMemory == true)
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func inMemoryUserDatabase() async throws {
      let syncEngine = try await SyncEngine(
        container: MockCloudContainer(
          containerIdentifier: "test",
          privateCloudDatabase: MockCloudDatabase(databaseScope: .private),
          sharedCloudDatabase: MockCloudDatabase(databaseScope: .shared)
        ),
        userDatabase: UserDatabase(database: DatabaseQueue()),
        tables: []
      )

      try await syncEngine.userDatabase.read { db in
        try SQLQueryExpression(
          """
          SELECT 1 FROM "sqlitedata_icloud_metadata"
          """
        )
        .execute(db)
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test(.dependency(\.context, .live))
    func inMemoryUserDatabase_LiveContext() async throws {
      let error = await #expect(throws: (any Error).self) {
        try await SyncEngine(
          container: MockCloudContainer(
            containerIdentifier: "test",
            privateCloudDatabase: MockCloudDatabase(databaseScope: .private),
            sharedCloudDatabase: MockCloudDatabase(databaseScope: .shared)
          ),
          userDatabase: UserDatabase(database: DatabaseQueue()),
          tables: []
        )
      }
      assertInlineSnapshot(of: error, as: .customDump) {
        """
        InMemoryDatabase()
        """
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func metadatabaseMismatch() async throws {
      let error = await #expect(throws: (any Error).self) {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
          try db.attachMetadatabase(containerIdentifier: "iCloud.co.pointfree")
        }
        let database = try DatabasePool(
          path: "/tmp/db.sqlite",
          configuration: configuration
        )
        _ = try await SyncEngine(
          container: MockCloudContainer(
            containerIdentifier: "iCloud.co.point-free",
            privateCloudDatabase: MockCloudDatabase(databaseScope: .private),
            sharedCloudDatabase: MockCloudDatabase(databaseScope: .shared)
          ),
          userDatabase: UserDatabase(database: database),
          tables: []
        )
      }
      assertInlineSnapshot(of: error, as: .customDump) {
        #"""
        SyncEngine.SchemaError(
          reason: .metadatabaseMismatch(
            attachedPath: "/private/tmp/.db.metadata-iCloud.co.pointfree.sqlite",
            syncEngineConfiguredPath: "/tmp/.db.metadata-iCloud.co.point-free.sqlite"
          ),
          debugDescription: "Metadatabase attached in \'prepareDatabase\' does not match metadatabase prepared in \'SyncEngine.init\'. Are different CloudKit container identifiers being provided?"
        )
        """#
      }
    }
  }
}

private func databaseWithForeignKeys() throws -> any DatabaseWriter {
  try DatabaseQueue()
}
