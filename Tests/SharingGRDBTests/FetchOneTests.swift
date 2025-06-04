import Combine
import Dependencies
import DependenciesTestSupport
import Foundation
import GRDB
import Sharing
import SharingGRDB
import StructuredQueries
import Testing

@Suite(.dependency(\.defaultDatabase, try .database()))
struct FetchOneTests {
  @Dependency(\.defaultDatabase) var database

  @Test func nonTableInit() {
    @FetchOne var value = 42
    #expect(value == 42)
    #expect($value.loadError == nil)
  }

  @Test func tableInit() async throws {
    @FetchOne var record: Record = Record(id: 0)
    try await $record.load()
    #expect(record == Record(id: 1))
    #expect($record.loadError == nil)
    try await database.write { try Record.delete().execute($0) }
    await #expect(throws: NotFound.self) {
      try await $record.load()
    }
    #expect(record == Record(id: 1))
    #expect($record.loadError is NotFound)
  }

  @Test func optionalTableInit() async throws {
    @FetchOne var record: Record?
    try await $record.load()
    #expect(record == Record(id: 1))
    #expect($record.loadError == nil)
    try await database.write { try Record.delete().execute($0) }
    try await $record.load()
    #expect(record == nil)
    #expect($record.loadError == nil)
  }

  @Test func optionalTableInit_WithDefault() async throws {
    @FetchOne var record: Record? = Record(id: 0)
    try await $record.load()
    #expect(record == Record(id: 1))
    #expect($record.loadError == nil)
    try await database.write { try Record.delete().execute($0) }
    try await $record.load()
    #expect(record == nil)
    #expect($record.loadError == nil)
  }

  @Test func selectStatementInit() async throws {
    @FetchOne(Record.order(by: \.id)) var record = Record(id: 0)
    try await $record.load()
    #expect(record == Record(id: 1))
    #expect($record.loadError == nil)
    try await database.write { try Record.delete().execute($0) }
    await #expect(throws: NotFound.self) {
      try await $record.load()
    }
    #expect(record == Record(id: 1))
    #expect($record.loadError is NotFound)
  }

  @Test func statementInit_Representable() async throws {
    @FetchOne(Record.select(\.date)) var recordDate = Date(timeIntervalSince1970: 1729)
    try await $recordDate.load()
    #expect(recordDate.timeIntervalSince1970 == 42)
    #expect($recordDate.loadError == nil)
    try await database.write { try Record.delete().execute($0) }
    await #expect(throws: NotFound.self) {
      try await $recordDate.load()
    }
    #expect(recordDate.timeIntervalSince1970 == 42)
    #expect($recordDate.loadError is NotFound)
  }

  @Test func statementInit_OptionalRepresentable() async throws {
    @FetchOne(Record.select(\.date)) var recordDate: Date?
    try await $recordDate.load()
    #expect(recordDate?.timeIntervalSince1970 == 42)
    #expect($recordDate.loadError == nil)
    var dates: [Date?] = []
    let cancellable = $recordDate.publisher.sink { dates.append($0) }
    try await database.write { try Record.delete().execute($0) }
    //    await #expect(throws: NotFound.self) {
    try await $recordDate.load()
    //    }
    #expect(recordDate?.timeIntervalSince1970 == nil)
    #expect($recordDate.loadError == nil)
  }

  @Test func statementInit_DoubleOptionalRepresentable() async throws {
    @FetchOne(Record.select(\.optionalDate)) var recordDate: Date?
    try await $recordDate.load()
    #expect(recordDate?.timeIntervalSince1970 == nil)
    #expect($recordDate.loadError == nil)
    try await database.write { try Record.delete().execute($0) }
    //    await #expect(throws: NotFound.self) {
    try await $recordDate.load()
    //    }
    #expect(recordDate?.timeIntervalSince1970 == nil)
    #expect($recordDate.loadError == nil)
  }

  @Test func statementInit() async throws {
    @FetchOne(Record.select(\.id)) var recordID = 0
    try await $recordID.load()
    #expect(recordID == 1)
    #expect($recordID.loadError == nil)
    try await database.write { try Record.delete().execute($0) }
    await #expect(throws: NotFound.self) {
      try await $recordID.load()
    }
    #expect(recordID == 1)
    #expect($recordID.loadError is NotFound)
  }
}

@Table
private struct Record: Equatable {
  let id: Int
  @Column(as: Date.UnixTimeRepresentation.self)
  var date = Date(timeIntervalSince1970: 42)
  @Column(as: Date?.UnixTimeRepresentation.self)
  var optionalDate: Date?
}
extension DatabaseWriter where Self == DatabaseQueue {
  fileprivate static func database() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "records" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT
          , "date" INTEGER NOT NULL DEFAULT 42
          , "optionalDate" INTEGER
        )
        """
      )
      .execute(db)
      for _ in 1...3 {
        _ = try Record.insert(Record.Draft()).execute(db)
      }
    }
    return database
  }
}
