import SQLiteData
import Testing

@Suite struct DefaultDatabaseTests {
  @Test func dependenciesWorkTogether() throws {
    let db1 = try DatabaseQueue(named: "db1")
    withDependencies {
      $0.getDefaultDatabase = { db1 }
    } operation: {
      @Dependency(\.defaultDatabase) var defaultDatabase
      #expect(defaultDatabase === db1)
    }

    let db2 = try DatabaseQueue(named: "db2")
    withDependencies {
      $0.defaultDatabase = db2
    } operation: {
      @Dependency(\.getDefaultDatabase) var getDefaultDatabase
      #expect(getDefaultDatabase() === db2)
    }
  }

  @Test func getDefaultIsNotCached() throws {
    let useDB2 = LockIsolated(false)
    let db1 = try DatabaseQueue(named: "db1")
    let db2 = try DatabaseQueue(named: "db2")

    withDependencies {
      $0.getDefaultDatabase = { useDB2.value ? db2 : db1 }
    } operation: {
      @Dependency(\.defaultDatabase) var defaultDatabase
      #expect(defaultDatabase === db1)
      useDB2.setValue(true)
      #expect(defaultDatabase === db2)
    }
  }

  @Test func getDefaultIsLazy() throws {
    let hasEvaluated = LockIsolated(false)
    let db = try DatabaseQueue()

    withDependencies {
      $0.getDefaultDatabase = {
        hasEvaluated.setValue(true)
        return db
      }
    } operation: {
      @Dependency(\.defaultDatabase) var defaultDatabase
      #expect(!hasEvaluated.value)
      _ = defaultDatabase
      #expect(hasEvaluated.value)
    }
  }
}
