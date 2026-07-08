public import Foundation
public import GRDBSQLite
public import StructuredQueriesCore

#if !StrictDecoding
  import ConcurrencyExtras
  import IssueReporting
#endif

@usableFromInline
struct SQLiteQueryDecoder: QueryDecoder {
  @usableFromInline
  let statement: OpaquePointer

  @usableFromInline
  var currentIndex: Int32 = 0

  @usableFromInline
  init(statement: OpaquePointer) {
    self.statement = statement
  }

  @inlinable
  mutating func next() {
    currentIndex = 0
  }

  @inlinable
  mutating func decode(_ columnType: [UInt8].Type) throws -> [UInt8]? {
    switch sqlite3_column_type(statement, currentIndex) {
    case SQLITE_NULL:
      currentIndex += 1
      return nil
    case SQLITE_BLOB:
      break
    default:
      try reportTypeMismatch([UInt8].self)
    }
    defer { currentIndex += 1 }
    return [UInt8](
      UnsafeRawBufferPointer(
        start: sqlite3_column_blob(statement, currentIndex),
        count: Int(sqlite3_column_bytes(statement, currentIndex))
      )
    )
  }

  @inlinable
  mutating func decode(_ columnType: Bool.Type) throws -> Bool? {
    try decode(Int64.self).map { $0 != 0 }
  }

  @inlinable
  mutating func decode(_ columnType: Date.Type) throws -> Date? {
    try decode(String.self).map { try Date(iso8601String: $0) }
  }

  @inlinable
  mutating func decode(_ columnType: Double.Type) throws -> Double? {
    switch sqlite3_column_type(statement, currentIndex) {
    case SQLITE_NULL:
      currentIndex += 1
      return nil
    case SQLITE_FLOAT:
      break
    default:
      try reportTypeMismatch(Double.self)
    }
    defer { currentIndex += 1 }
    return sqlite3_column_double(statement, currentIndex)
  }

  @inlinable
  mutating func decode(_ columnType: Int.Type) throws -> Int? {
    try decode(Int64.self).map(Int.init)
  }

  @inlinable
  mutating func decode(_ columnType: Int64.Type) throws -> Int64? {
    switch sqlite3_column_type(statement, currentIndex) {
    case SQLITE_NULL:
      currentIndex += 1
      return nil
    case SQLITE_INTEGER:
      break
    default:
      try reportTypeMismatch(Int64.self)
    }
    defer { currentIndex += 1 }
    return sqlite3_column_int64(statement, currentIndex)
  }

  @inlinable
  mutating func decode(_ columnType: String.Type) throws -> String? {
    switch sqlite3_column_type(statement, currentIndex) {
    case SQLITE_NULL:
      currentIndex += 1
      return nil
    case SQLITE_TEXT:
      break
    default:
      try reportTypeMismatch(String.self)
    }
    defer { currentIndex += 1 }
    return String(cString: sqlite3_column_text(statement, currentIndex))
  }

  @inlinable
  mutating func decode(_ columnType: UInt64.Type) throws -> UInt64? {
    guard let n = try decode(Int64.self) else { return nil }
    guard n >= 0 else { throw UInt64OverflowError(signedInteger: n) }
    return UInt64(n)
  }

  @inlinable
  mutating func decode(_ columnType: UUID.Type) throws -> UUID? {
    guard let uuidString = try decode(String.self) else { return nil }
    guard let uuid = UUID(uuidString: uuidString) else { throw InvalidUUID() }
    return uuid
  }

  @usableFromInline
  func reportTypeMismatch(_ columnType: Any.Type) throws {
    #if StrictDecoding
      throw QueryDecodingError.typeMismatch(columnType)
    #else
      let sql = sqlite3_sql(statement).map { String(cString: $0) } ?? ""
      let key = "\(currentIndex)|\(sql)"
      guard reportedTypeMismatches.withValue({ $0.insert(key).inserted })
      else { return }
      let columnName = sqlite3_column_name(statement, currentIndex).map { String(cString: $0) }
      reportIssue(
        """
        Expected column \(currentIndex) (\((columnName ?? "").debugDescription)) to decode \
        \(columnType), but found \
        \(storageClassName(sqlite3_column_type(statement, currentIndex))): ...

        \(sql)
        """
      )
    #endif
  }
}

@usableFromInline
struct InvalidUUID: Error {
  @usableFromInline
  init() {}
}

@usableFromInline
struct UInt64OverflowError: Error {
  let signedInteger: Int64

  @usableFromInline
  init(signedInteger: Int64) {
    self.signedInteger = signedInteger
  }
}
