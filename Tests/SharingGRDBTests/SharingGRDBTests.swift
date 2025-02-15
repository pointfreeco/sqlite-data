import Dependencies
import GRDB
import Sharing
import SharingGRDB
import Testing

@Suite struct GRDBSharingTests {
  @Test
  func fetchOne() async throws {
    try await withDependencies {
      $0.defaultDatabase = try DatabaseQueue()
    } operation: {
      @SharedReader(.fetchOne(sql: "SELECT 1")) var bool = false
      try await Task.sleep(nanoseconds: 10_000_000)
      #expect(bool)
      #expect($bool.loadError == nil)
    }
  }

  @Test
  func fetchOneOptional() async throws {
    try withDependencies {
      $0.defaultDatabase = try DatabaseQueue()
    } operation: {
      @SharedReader(.fetchOne(sql: "SELECT NULL")) var bool: Bool?
      #expect(bool == nil)
    }
  }

  @Test func fetchSyntaxError() async throws {
    try await withDependencies {
      $0.defaultDatabase = try DatabaseQueue()
    } operation: {
      @SharedReader(.fetchOne(sql: "SELEC 1")) var bool = false
      #expect(bool == false)
      try await Task.sleep(nanoseconds: 10_000_000)
      #expect($bool.loadError is DatabaseError?)
      let error = try #require($bool.loadError as? DatabaseError)
      #expect(error.message == #"near "SELEC": syntax error"#)
    }
  }
}
