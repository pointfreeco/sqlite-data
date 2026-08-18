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
  var argumentCount: Int32 = 0

  @usableFromInline
  var arguments: UnsafeMutablePointer<OpaquePointer?>?

  @usableFromInline
  var currentIndex: Int32 = 0

  #if !StrictDecoding
    @usableFromInline
    var reportedTypeMismatches: Set<Int32> = []
  #endif

  @usableFromInline
  init(name: String) {
    self.name = name
  }

  @usableFromInline
  mutating func reset(argumentCount: Int32, arguments: UnsafeMutablePointer<OpaquePointer?>?) {
    self.argumentCount = argumentCount
    self.arguments = arguments
    self.currentIndex = 0
  }

  @inlinable
  mutating func next() {
    currentIndex = 0
  }

  @inlinable
  mutating func decode(_ columnType: [UInt8].Type) throws(QueryDecodingError) -> [UInt8]? {
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
  mutating func decode(_ columnType: Bool.Type) throws(QueryDecodingError) -> Bool? {
    try decode(Int64.self).map { $0 != 0 }
  }

  @usableFromInline
  mutating func decode(_ columnType: Date.Type) throws(QueryDecodingError) -> Date? {
    guard let iso8601String = try decode(String.self) else { return nil }
    do {
      return try Date(iso8601String: iso8601String)
    } catch {
      throw .other(error)
    }
  }

  @inlinable
  mutating func decode(_ columnType: Double.Type) throws(QueryDecodingError) -> Double? {
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
  mutating func decode(_ columnType: Int.Type) throws(QueryDecodingError) -> Int? {
    try decode(Int64.self).map(Int.init)
  }

  @inlinable
  mutating func decode(_ columnType: Int64.Type) throws(QueryDecodingError) -> Int64? {
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
  mutating func decode(_ columnType: String.Type) throws(QueryDecodingError) -> String? {
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
    let text = sqlite3_value_text(value)
    let byteCount = Int(sqlite3_value_bytes(value))
    return String(decoding: UnsafeBufferPointer(start: text, count: byteCount), as: UTF8.self)
  }

  @inlinable
  mutating func decode(_ columnType: UInt64.Type) throws(QueryDecodingError) -> UInt64? {
    guard let n = try decode(Int64.self) else { return nil }
    guard n >= 0 else { throw .other(UInt64OverflowError(signedInteger: n)) }
    return UInt64(n)
  }

  @usableFromInline
  mutating func decode(_ columnType: UUID.Type) throws(QueryDecodingError) -> UUID? {
    guard let uuidString = try decode(String.self) else { return nil }
    return UUID(uuidString: uuidString)
  }

  @usableFromInline
  mutating func reportTypeMismatch(_ columnType: Any.Type) throws(QueryDecodingError) {
    #if StrictDecoding
      throw QueryDecodingError.typeMismatch(columnType)
    #else
      guard reportedTypeMismatches.insert(currentIndex).inserted
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
