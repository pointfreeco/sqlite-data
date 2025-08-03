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
    @Test func inMemory() throws {
      #expect(URL(string: "")?.isInMemory == nil)
      #expect(URL(string: ":memory:")?.isInMemory == true)
      #expect(URL(string: ":memory:?cache=shared")?.isInMemory == true)
      #expect(URL(string: "file::memory:")?.isInMemory == true)
      #expect(URL(string: "file:memdb1?mode=memory&cache=shared")?.isInMemory == true)
    }

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

    @Test func metadatabaseMismatch() async throws {
      let error = await #expect(throws: (any Error).self) {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
          try db.attachMetadatabase(containerIdentifier: "iCloud.co.pointfree")
        }
        let database = try DatabasePool(
          path: NSTemporaryDirectory() + UUID().uuidString,
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
            attachedPath: "/private/var/folders/vj/bzr5j4ld7cz6jgpphc5kbs8m0000gn/T/.C1938F73-8A6E-40BA-BCF5-A10C07CA1EB6.metadata-iCloud.co.pointfree.sqlite",
            syncEngineConfiguredPath: "/var/folders/vj/bzr5j4ld7cz6jgpphc5kbs8m0000gn/T/.C1938F73-8A6E-40BA-BCF5-A10C07CA1EB6.metadata-iCloud.co.point-free.sqlite"
          ),
          debugDescription: "Metadatabase attached in \'prepareDatabase\' does not match metadatabase prepared in \'SyncEngine.init\'. Are the CloudKit container identifiers different?"
        )
        """#
      }
    }
  }
}

private func databaseWithForeignKeys() throws -> any DatabaseWriter {
  try DatabaseQueue()
}
