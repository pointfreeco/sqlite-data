import Foundation
import Testing
import SharingGRDB

@Suite struct UserlandTests {
  @Test func basics() async throws {
    let database = try SharingGRDBTests.database(containerIdentifier: "tests")
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
      $0.datetime.now = Date.init(timeIntervalSince1970: 1)
    } operation: {
      @FetchAll var modelAs: [ModelA] = []
      try await database.write { db in
        try db.seed {
          ModelA.Draft()
        }
      }
      try await $modelAs.load()
      #expect(modelAs == [ModelA(id: 1, isEven: true)])
    }
  }
}
