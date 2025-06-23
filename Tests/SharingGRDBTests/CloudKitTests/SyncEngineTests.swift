import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  final class SyncEngineTests: BaseCloudKitTests, @unchecked Sendable {
    #if os(macOS) && compiler(>=6.2)
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func foreignKeysDisabled() throws {
        let result = #expect(
          processExitsWith: .failure,
          observing: [\.standardErrorContent]
        ) {
          _ = try SyncEngine(
            privateSyncEngine: MockSyncEngine(scope: .private, state: MockSyncEngineState()),
            sharedSyncEngine: MockSyncEngine(scope: .shared, state: MockSyncEngineState()),
            database: databaseWithForeignKeys(),
            metadatabaseURL: URL.temporaryDirectory,
            tables: []
          )
        }
        #expect(
          String(decoding: try #require(result).standardOutputContent, as: UTF8.self)
            == "Foreign key support must be disabled to synchronize with CloudKit."
        )
      }
    #endif

//    @Test func 
  }
}

private func databaseWithForeignKeys() throws -> any DatabaseWriter {
  try DatabaseQueue()
}
