import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class SyncEngineTests: BaseCloudKitTests, @unchecked Sendable {
    #if os(macOS) && compiler(>=6.2)
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func foreignKeysDisabled() throws {
        let result = #expect(
          processExitsWith: .failure,
          observing: [\.standardErrorContent]
        ) {
          // TODO: finish in Xcode 26
          //  _ = try SyncEngine(
          //    syncEngine.private: MockSyncEngine(scope: .private, state: MockSyncEngineState()),
          //    syncEngine.shared: MockSyncEngine(scope: .shared, state: MockSyncEngineState()),
          //    database: databaseWithForeignKeys(),
          //    tables: []
          //  )
        }
        #expect(
          String(decoding: try #require(result).standardOutputContent, as: UTF8.self)
            == "Foreign key support must be disabled to synchronize with CloudKit."
        )
      }
    #endif

    @Test func inMemory() throws {
      #expect(URL(string: "")?.isInMemory == nil)
      #expect(URL(string: ":memory:")?.isInMemory == true)
      #expect(URL(string: ":memory:?cache=shared")?.isInMemory == true)
      #expect(URL(string: "file::memory:")?.isInMemory == true)
      #expect(URL(string: "file:memdb1?mode=memory&cache=shared")?.isInMemory == true)
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
