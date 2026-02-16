#if canImport(CloudKit)
  import Foundation
  import SQLiteData
  import Testing

  @Suite struct UserlandTests {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func basics() async throws {
      let database = try SQLiteDataTests.database(
        containerIdentifier: "tests",
        attachMetadatabase: false
      )
      let syncEngine = try SyncEngine(
        for: database,
        tables: ModelA.self,
        ModelB.self,
        ModelC.self,
        containerIdentifier: "tests"
      )

      try await withDependencies {
        $0.defaultDatabase = database
        $0.defaultSyncEngine = syncEngine
        $0.currentTime.now = 1
      } operation: {
        @FetchAll var modelAs: [ModelA] = []
        try await database.write { db in
          try db.seed {
            ModelA.Draft(id: 1)
          }
        }
        try await $modelAs.load()
        #expect(modelAs == [ModelA(id: 1, isEven: true)])
      }
    }
  }
#endif
