import CloudKit
import CustomDump
import InlineSnapshotTesting
import SQLiteData
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class UnattachedSyncEngineTests: @unchecked Sendable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func start() async throws {
      let database = try DatabasePool(path: "\(NSTemporaryDirectory())\(UUID())")
      _ = try await SyncEngine(
        container: MockCloudContainer(
          containerIdentifier: "iCloud.co.pointfree.Testing",
          privateCloudDatabase: MockCloudDatabase(databaseScope: .private),
          sharedCloudDatabase: MockCloudDatabase(databaseScope: .shared)
        ),
        userDatabase: UserDatabase(database: database),
        tables: []
      )
    }
  }
}
