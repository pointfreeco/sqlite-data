import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@Suite(.dependency(\.defaultDatabase, try DatabaseQueue()))
struct UUIDTests {
  @Dependency(\.defaultDatabase) var database

  @Test func `decode matches Foundation parsing`() throws {
    try database.read { db in
      for text in [
        "deadbeef-dead-beef-dead-beefdeadbeef",
        "DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF",
        "A1b2C3d4-E5f6-7890-aB12-Cd34eF567890",
        "00000000-0000-0000-0000-000000000000",
      ] {
        let decoded = try #sql("SELECT \(bind: text)", as: UUID.self).fetchOne(db)
        #expect(decoded == UUID(uuidString: text), "\(text)")
      }
    }
  }

  @Test func roundtrip() throws {
    let uuid = UUID()
    try database.read { db in
      let decoded = try #sql("SELECT \(bind: uuid)", as: UUID.self).fetchOne(db)
      #expect(decoded == uuid)
    }
  }
}
