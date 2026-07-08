public import Foundation
public import GRDBSQLite
public import StructuredQueriesCore

#if !StrictDecoding
  import IssueReporting
#endif

@usableFromInline
struct SQLiteFunctionDecoder: QueryDecoder {
  @usableFromInline
  let name: String

  @usableFromInline
  let argumentCount: Int32

  @usableFromInline
  let arguments: UnsafeMutablePointer<OpaquePointer?>?

  @usableFromInline
  var currentIndex: Int32 = 0

  @usableFromInline
  init(name: String, argumentCount: Int32, arguments: UnsafeMutablePointer<OpaquePointer?>?) {
    self.name = name
    self.argumentCount = argumentCount
    self.arguments = arguments
  }

  @inlinable
  mutating func next() {
    currentIndex = 0
  }

  @inlinable
  mutating func decode(_ columnType: [UInt8].Type) throws -> [UInt8]? {
    precondition(argumentCount > currentIndex)
    let value = arguments?[Int(currentIndex)]
    switch sqlite3_value_type(value) {
    case SQLITE_NULL:
      currentIndex += 1
      return nil
    case SQLITE_BLOB:
      break
    default:
      try reportTypeMismatch([UInt8].self)
    }
    defer { currentIndex += 1 }
    if let blob = sqlite3_value_blob(value) {
      let count = Int(sqlite3_value_bytes(value))
      let buffer = UnsafeRawBufferPointer(start: blob, count: count)
      return [UInt8](buffer)
    } else {
      return []
    }
  }

  @inlinable
  mutating func decode(_ columnType: Bool.Type) throws -> Bool? {
    try decode(Int64.self).map { $0 != 0 }
  }

  @usableFromInline
  mutating func decode(_ columnType: Date.Type) throws -> Date? {
    guard let iso8601String = try decode(String.self) else { return nil }
    return try Date(iso8601String: iso8601String)
  }

  @inlinable
  mutating func decode(_ columnType: Double.Type) throws -> Double? {
    precondition(argumentCount > currentIndex)
    let value = arguments?[Int(currentIndex)]
    switch sqlite3_value_type(value) {
    case SQLITE_NULL:
      currentIndex += 1
      return nil
    case SQLITE_FLOAT:
      break
    default:
      try reportTypeMismatch(Double.self)
    }
    defer { currentIndex += 1 }
    return sqlite3_value_double(value)
  }

  @inlinable
  mutating func decode(_ columnType: Int.Type) throws -> Int? {
    try decode(Int64.self).map(Int.init)
  }

  @inlinable
  mutating func decode(_ columnType: Int64.Type) throws -> Int64? {
    precondition(argumentCount > currentIndex)
    let value = arguments?[Int(currentIndex)]
    switch sqlite3_value_type(value) {
    case SQLITE_NULL:
      currentIndex += 1
      return nil
    case SQLITE_INTEGER:
      break
    default:
      try reportTypeMismatch(Int64.self)
    }
    defer { currentIndex += 1 }
    return sqlite3_value_int64(value)
  }

  @inlinable
  mutating func decode(_ columnType: String.Type) throws -> String? {
    precondition(argumentCount > currentIndex)
    let value = arguments?[Int(currentIndex)]
    switch sqlite3_value_type(value) {
    case SQLITE_NULL:
      currentIndex += 1
      return nil
    case SQLITE_TEXT:
      break
    default:
      try reportTypeMismatch(String.self)
    }
    defer { currentIndex += 1 }
    return String(cString: sqlite3_value_text(value))
  }

  @inlinable
  mutating func decode(_ columnType: UInt64.Type) throws -> UInt64? {
    guard let n = try decode(Int64.self) else { return nil }
    guard n >= 0 else { throw UInt64OverflowError(signedInteger: n) }
    return UInt64(n)
  }

  @usableFromInline
  mutating func decode(_ columnType: UUID.Type) throws -> UUID? {
    guard let uuidString = try decode(String.self) else { return nil }
    return UUID(uuidString: uuidString)
  }

  @usableFromInline
  func reportTypeMismatch(_ columnType: Any.Type) throws {
    #if StrictDecoding
      throw QueryDecodingError.typeMismatch(columnType)
    #else
      let key = "\(currentIndex)|\(name)"
      guard reportedTypeMismatches.withValue({ $0.insert(key).inserted })
      else { return }
      let value = arguments?[Int(currentIndex)]
      reportIssue(
        """
        Expected argument \(currentIndex) of \(name.debugDescription) to decode \(columnType), \
        but found \(storageClassName(sqlite3_value_type(value)))
        """
      )
    #endif
  }
}
