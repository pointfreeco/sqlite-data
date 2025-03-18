import SQLite3
import StructuredQueriesCore

final class SQLiteQueryDecoder: QueryDecoder {
  private let database: OpaquePointer?
  private let statement: OpaquePointer
  private var currentIndex: Int32 = 0

  init(database: OpaquePointer?, statement: OpaquePointer) {
    self.database = database
    self.statement = statement
  }

  @inlinable
  @inline(__always)
  func next() {
    currentIndex = 0
  }

  @inlinable
  @inline(__always)
  func decode(_ type: Bool.Type) throws -> Bool {
    try decode(Int.self) != 0
  }

  @inlinable
  @inline(__always)
  func decode(_ type: ContiguousArray<UInt8>.Type) throws -> ContiguousArray<UInt8> {
    defer { currentIndex += 1 }
    return ContiguousArray<UInt8>(
      UnsafeRawBufferPointer(
        start: sqlite3_column_blob(statement, currentIndex),
        count: Int(sqlite3_column_bytes(statement, currentIndex))
      )
    )
  }

  @inlinable
  @inline(__always)
  func decode(_ type: Double.Type) throws -> Double {
    defer { currentIndex += 1 }
    return sqlite3_column_double(statement, currentIndex)
  }

  @inlinable
  @inline(__always)
  func decode(_ type: Float.Type) throws -> Float {
    try Float(decode(Double.self))
  }

  @inlinable
  @inline(__always)
  func decode(_ type: Int.Type) throws -> Int {
    try Int(decode(Int64.self))
  }

  @inlinable
  @inline(__always)
  func decode(_ type: Int8.Type) throws -> Int8 {
    try Int8(decode(Int32.self))
  }

  @inlinable
  @inline(__always)
  func decode(_ type: Int16.Type) throws -> Int16 {
    try Int16(decode(Int32.self))
  }

  @inlinable
  @inline(__always)
  func decode(_ type: Int32.Type) throws -> Int32 {
    defer { currentIndex += 1 }
    return sqlite3_column_int(statement, currentIndex)
  }

  @inlinable
  @inline(__always)
  func decode(_ type: Int64.Type) throws -> Int64 {
    defer { currentIndex += 1 }
    return sqlite3_column_int64(statement, currentIndex)
  }

  @inlinable
  @inline(__always)
  func decode(_ type: String.Type) throws -> String {
    defer { currentIndex += 1 }
    return String(cString: sqlite3_column_text(statement, currentIndex))
  }

  @inlinable
  @inline(__always)
  func decode(_ type: UInt.Type) throws -> UInt {
    try UInt(decode(UInt64.self))
  }

  @inlinable
  @inline(__always)
  func decode(_ type: UInt8.Type) throws -> UInt8 {
    try UInt8(decode(Int32.self))
  }

  @inlinable
  @inline(__always)
  func decode(_ type: UInt16.Type) throws -> UInt16 {
    try UInt16(decode(Int32.self))
  }

  @inlinable
  @inline(__always)
  func decode(_ type: UInt32.Type) throws -> UInt32 {
    try UInt32(decode(Int64.self))
  }

  @inlinable
  @inline(__always)
  func decode(_ type: UInt64.Type) throws -> UInt64 {
    try UInt64(decode(Int64.self))
  }

  @inlinable
  @inline(__always)
  public func decodeColumns<T: Table>(_ type: T.Type = T.self) throws -> T {
    try T(decoder: self)
  }

  @inlinable
  @inline(__always)
  func decodeNil() throws -> Bool {
    let isNil = sqlite3_column_type(statement, currentIndex) == SQLITE_NULL
    if isNil { currentIndex += 1 }
    return isNil
  }

  @inlinable
  @inline(__always)
  func decode(_ type: Bool?.Type) throws -> Bool? {
    try decode(Int?.self).map { $0 != 0 }
  }

  @inlinable
  @inline(__always)
  func decode(_ type: ContiguousArray<UInt8>?.Type) throws -> ContiguousArray<UInt8>? {
    defer { currentIndex += 1 }
    guard sqlite3_column_type(statement, currentIndex) != SQLITE_NULL else { return nil }
    return ContiguousArray<UInt8>(
      UnsafeRawBufferPointer(
        start: sqlite3_column_blob(statement, currentIndex),
        count: Int(sqlite3_column_bytes(statement, currentIndex))
      )
    )
  }

  @inlinable
  @inline(__always)
  func decode(_ type: Float?.Type) throws -> Float? {
    try decode(Double?.self).map(Float.init)
  }

  @inlinable
  @inline(__always)
  func decode(_ type: Double?.Type) throws -> Double? {
    defer { currentIndex += 1 }
    guard sqlite3_column_type(statement, currentIndex) != SQLITE_NULL else { return nil }
    return sqlite3_column_double(statement, currentIndex)
  }

  @inlinable
  @inline(__always)
  func decode(_ type: Int?.Type) throws -> Int? {
    try decode(Int64?.self).map(Int.init)
  }

  @inlinable
  @inline(__always)
  func decode(_ type: Int8?.Type) throws -> Int8? {
    try decode(Int32?.self).map(Int8.init)
  }

  @inlinable
  @inline(__always)
  func decode(_ type: Int16?.Type) throws -> Int16? {
    try decode(Int32?.self).map(Int16.init)
  }

  @inlinable
  @inline(__always)
  func decode(_ type: Int32?.Type) throws -> Int32? {
    defer { currentIndex += 1 }
    guard sqlite3_column_type(statement, currentIndex) != SQLITE_NULL else { return nil }
    return sqlite3_column_int(statement, currentIndex)
  }

  @inlinable
  @inline(__always)
  func decode(_ type: Int64?.Type) throws -> Int64? {
    defer { currentIndex += 1 }
    guard sqlite3_column_type(statement, currentIndex) != SQLITE_NULL else { return nil }
    return sqlite3_column_int64(statement, currentIndex)
  }

  @inlinable
  @inline(__always)
  func decode(_ type: String?.Type) throws -> String? {
    defer { currentIndex += 1 }
    guard sqlite3_column_type(statement, currentIndex) != SQLITE_NULL else { return nil }
    return String(cString: sqlite3_column_text(statement, currentIndex))
  }

  @inlinable
  @inline(__always)
  func decode(_ type: UInt?.Type) throws -> UInt? {
    try decode(UInt64?.self).map(UInt.init)
  }

  @inlinable
  @inline(__always)
  func decode(_ type: UInt8?.Type) throws -> UInt8? {
    try decode(UInt32?.self).map(UInt8.init)
  }

  @inlinable
  @inline(__always)
  func decode(_ type: UInt16?.Type) throws -> UInt16? {
    try decode(UInt32?.self).map(UInt16.init)
  }

  @inlinable
  @inline(__always)
  func decode(_ type: UInt32?.Type) throws -> UInt32? {
    try decode(Int64?.self).map(UInt32.init)
  }

  @inlinable
  @inline(__always)
  func decode(_ type: UInt64?.Type) throws -> UInt64? {
    try decode(Int64?.self).map(UInt64.init)
  }

  @inlinable
  @inline(__always)
  public func decodeColumns<T: Table>(_ type: T?.Type = T?.self) throws -> T? {
    let index = currentIndex
    let result = try T?(decoder: self)
    currentIndex = index.advanced(by: T.Columns.count)
    return result
  }
}
