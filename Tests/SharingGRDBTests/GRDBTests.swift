import GRDB
import Testing

@TaskLocal private var count = 0

@Suite
struct GRDBTaskLocalTests {
  @Test func taskLocalInRead() throws {
    let dbQueue = try DatabaseQueue()
    try $count.withValue(99) {
      try dbQueue.read { db in
        #expect(count == 99)
      }
    }
  }
  @Test func taskLocalInAsyncRead() async throws {
    let dbQueue = try DatabaseQueue()
    try await $count.withValue(99) {
      #expect(count == 99)
      try await dbQueue.read { db in
        #expect(count == 99)
      }
    }
  }
  @Test func taskLocalInWrite() throws {
    let dbQueue = try DatabaseQueue()
    try $count.withValue(99) {
      try dbQueue.write { db in
        #expect(count == 99)
      }
    }
  }
  @Test func taskLocalInAsyncWrite() async throws {
    let dbQueue = try DatabaseQueue()
    try await $count.withValue(99) {
      #expect(count == 99)
      try await dbQueue.write { db in
        #expect(count == 99)
      }
    }
  }
}
