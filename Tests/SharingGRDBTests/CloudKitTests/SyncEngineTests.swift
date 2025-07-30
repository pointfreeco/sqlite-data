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
  }
}

private func databaseWithForeignKeys() throws -> any DatabaseWriter {
  try DatabaseQueue()
}
