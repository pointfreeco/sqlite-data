import GRDB
import Foundation
@_exported import StructuredQueriesCore

extension StructuredQueriesCore.Statement {
  // TODO: Support try Record.find(reminder.listID)?

  public func execute(_ db: Database) throws {
    let query = self.query
    guard !query.isEmpty else { return }
    try db.execute(sql: query.string, arguments: query.arguments)
  }

  public func fetchAll<each Value: QueryRepresentable>(
    _ db: Database
  ) throws -> [(repeat (each Value).QueryOutput)]
  where QueryValue == (repeat each Value) {
    let query = self.query
    guard !query.isEmpty else { return [] }
    let cursor = try Row.fetchCursor(db, sql: query.string, arguments: query.arguments)
    var results: [(repeat (each Value).QueryOutput)] = []
    let decoder = GRDBQueryDecoder()
    while let row = try cursor.next() {
      try decoder.withRow(row) {
        try results.append((repeat (each Value)(decoder: decoder).queryOutput))
      }
    }
    return results
  }

  public func fetchAll(
    _ db: Database
  ) throws -> [QueryValue.QueryOutput]
  where QueryValue: QueryRepresentable {
    let query = self.query
    guard !query.isEmpty else { return [] }
    let cursor = try Row.fetchCursor(db, sql: query.string, arguments: query.arguments)
    var results: [QueryValue.QueryOutput] = []
    let decoder = GRDBQueryDecoder()
    while let row = try cursor.next() {
      try decoder.withRow(row) {
        try results.append(QueryValue(decoder: decoder).queryOutput)
      }
    }
    return results
  }

  public func fetchOne<each Value: QueryRepresentable>(
    _ db: Database
  ) throws -> (repeat (each Value).QueryOutput)?
  where QueryValue == (repeat each Value) {
    let query = self.query
    guard !query.isEmpty else { return nil }
    let cursor = try Row.fetchCursor(db, sql: query.string, arguments: query.arguments)
    guard let row = try cursor.next() else { return nil }
    let decoder = GRDBQueryDecoder()
    return try decoder.withRow(row) {
      try (repeat (each Value)(decoder: decoder).queryOutput)
    }
  }

  public func fetchOne(
    _ db: Database
  ) throws -> QueryValue.QueryOutput?
  where QueryValue: QueryRepresentable {
    let query = self.query
    guard !query.isEmpty else { return nil }
    let cursor = try Row.fetchCursor(db, sql: query.string, arguments: query.arguments)
    guard let row = try cursor.next() else { return nil }
    let decoder = GRDBQueryDecoder()
    return try decoder.withRow(row) {
      try QueryValue(decoder: decoder).queryOutput
    }
  }
}

extension SelectStatement where QueryValue == () {
  public func fetchAll<each J: StructuredQueriesCore.Table>(
    _ db: Database
  ) throws -> [(From.QueryOutput, repeat (each J).QueryOutput)]
  where Joins == (repeat each J) {
    let query = self.query
    guard !query.isEmpty else { return [] }
    let cursor = try Row.fetchCursor(db, sql: query.string, arguments: query.arguments)
    var results: [(From.QueryOutput, repeat (each J).QueryOutput)] = []
    let decoder = GRDBQueryDecoder()
    while let row = try cursor.next() {
      try decoder.withRow(row) {
        try results.append(
          (
            From(decoder: decoder).queryOutput,
            repeat (each J)(decoder: decoder).queryOutput
          )
        )
      }
    }
    return results
  }

  public func fetchOne<each J: StructuredQueriesCore.Table>(
    _ db: Database
  ) throws -> (From.QueryOutput, repeat (each J).QueryOutput)?
  where Joins == (repeat each J) {
    let query = self.query
    guard !query.isEmpty else { return nil }
    let cursor = try Row.fetchCursor(db, sql: query.string, arguments: query.arguments)
    guard let row = try cursor.next() else { return nil }
    let decoder = GRDBQueryDecoder()
    return try decoder.withRow(row) {
      try (
        From(decoder: decoder).queryOutput,
        repeat (each J)(decoder: decoder).queryOutput
      )
    }
  }
}

fileprivate final class GRDBQueryDecoder: QueryDecoder {
  private var statement: OpaquePointer?
  private var currentIndex: Int = 0
  private var currentRow: Row!

  public init() {}

  func withRow<R>(_ row: Row, body: () throws -> R) rethrows -> R {
    currentRow = row
    defer {
      currentIndex = 0
      currentRow = nil
    }
    return try body()
  }

  func decodeNil() throws -> Bool {
    guard currentIndex < currentRow.count else { throw DecodingError() }
    let isNil = currentRow.hasNull(atIndex: currentIndex)
    if isNil { currentIndex += 1 }
    return isNil
  }

  func decode(_ type: Double.Type) throws -> Double {
    defer { currentIndex += 1 }
    guard
      currentIndex < currentRow.count,
      let value = currentRow[currentIndex] as? Double
    else { throw DecodingError() }
    return value
  }

  func decode(_ type: Int64.Type) throws -> Int64 {
    defer { currentIndex += 1 }
    guard
      currentIndex < currentRow.count,
      let value = currentRow[currentIndex] as? Int64
    else { throw DecodingError() }
    return value
  }

  func decode(_ type: String.Type) throws -> String {
    defer { currentIndex += 1 }
    guard
      currentIndex < currentRow.count,
      let value = currentRow[currentIndex] as? String
    else { throw DecodingError() }
    return value
  }

  func decode(_ type: [UInt8].Type) throws -> [UInt8] {
    defer { currentIndex += 1 }
    guard
      currentIndex < currentRow.count,
      let value = currentRow[currentIndex] as? Data
    else { throw DecodingError() }
    return [UInt8](value)
  }

  // TODO: Better error handling/messaging
  private struct DecodingError: Error {
    init() {
      print("!!!")
    }
  }
}

fileprivate extension QueryFragment {
  var arguments: StatementArguments {
    StatementArguments(bindings.map(\.databaseValue))
  }
}

fileprivate extension QueryBinding /* : DatabaseValueConvertible */ {
  var databaseValue: DatabaseValue {
    switch self {
    case .blob(let blob):
      return Data(blob).databaseValue
    case .double(let double):
      return double.databaseValue
    case .int(let int):
      return int.databaseValue
    case .null:
      return .null
    case .text(let text):
      return text.databaseValue
    }
  }
}
