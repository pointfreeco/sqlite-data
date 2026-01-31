#if canImport(CloudKit)
  import CloudKit
  import CustomDump
  import Foundation
  import OrderedCollections
  import SQLiteData
  import SnapshotTestingCustomDump
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    @Suite(.attachMetadatabase)
    final class SyncMetadataTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func root() async throws {
        let modelA = ModelA(id: 1, count: 1, isEven: false)
        let modelB = ModelB(id: 1, isOn: true, modelAID: 1)
        let modelC = ModelC(id: 1, title: "Hello", modelBID: 1)
        try await userDatabase.userWrite { db in
          try db.seed {
            modelA
            ModelA(id: 2, isEven: true)
            modelB
            ModelB(id: 2, modelAID: 2)
            modelC
            ModelC(id: 2, modelBID: 2)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await userDatabase.read { db in
          let rootAs = try SyncMetadata.findRoot(for: modelA.syncMetadataID).fetchAll(db)
          let rootBs = try SyncMetadata.findRoot(for: modelB.syncMetadataID).fetchAll(db)
          let rootCs = try SyncMetadata.findRoot(for: modelC.syncMetadataID).fetchAll(db)
          #expect(rootAs.count == 1)
          #expect(rootAs.map(\.id) == rootBs.map(\.id))
          #expect(rootBs.map(\.id) == rootCs.map(\.id))
        }
      }
    }
  }
#endif
