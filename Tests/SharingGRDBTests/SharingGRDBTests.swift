import Dependencies
import GRDB
import Sharing
import SharingGRDB
import Testing

struct GRDBSharingTests {
  @Test
  func fetchOne() async throws {
    try withDependencies {
      $0.defaultDatabase = try DatabaseQueue()
    } operation: {
      @SharedReader(.fetchOne(sql: "SELECT 1")) var bool = false
      #expect(bool)
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
}
