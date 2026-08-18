import Foundation
public import GRDB
import GRDBSQLite
public import StructuredQueriesCore

/// A cursor of a structured query.
///
/// Iterates over and decodes all of the rows of a structured query.
public class QueryCursor<Element>: DatabaseCursor {
  public var _isDone = false
  public let _statement: GRDB.Statement

  @usableFromInline
  var decoder: SQLiteQueryDecoder

  @usableFromInline
  init(db: Database, prepared: PreparedQuery, cached: Bool) throws {
    (_statement, decoder) = try db.prepare(prepared, cached: cached)
  }

  @usableFromInline
  convenience init(db: Database, query: QueryFragment, cached: Bool) throws {
    try self.init(db: db, prepared: PreparedQuery(query), cached: cached)
  }

  deinit {
    sqlite3_reset(_statement.sqliteStatement)
    sqlite3_clear_bindings(_statement.sqliteStatement)
  }

  public func _element(sqliteStatement _: SQLiteStatement) throws -> Element {
    fatalError("Abstract method should be overridden in subclass")
  }

  @usableFromInline
  struct DecodingError: Error, CustomStringConvertible {
    let columnIndex: Int
    let columnName: String
    let reason: String
    let sql: String

    @usableFromInline
    init(columnIndex: Int, columnName: String, reason: String, sql: String) {
      self.columnIndex = columnIndex
      self.columnName = columnName
      self.reason = reason
      self.sql = sql
    }

    @usableFromInline
    var description: String {
      """
      Expected column \(columnIndex) (\(columnName.debugDescription)) \(reason): ...

      \(sql)
      """
    }
  }

  @usableFromInline
  func missingRequiredColumnError() -> DecodingError {
    let columnIndex = Int(decoder.currentIndex) - 1
    return DecodingError(
      columnIndex: columnIndex,
      columnName: _statement.columnNames[columnIndex],
      reason: "to not be NULL",
      sql: _statement.sql
    )
  }

  @usableFromInline
  func typeMismatchError(_ columnType: Any.Type) -> DecodingError {
    let columnIndex = Int(decoder.currentIndex)
    let storageClass = storageClassName(
      sqlite3_column_type(_statement.sqliteStatement, Int32(columnIndex))
    )
    return DecodingError(
      columnIndex: columnIndex,
      columnName: _statement.columnNames[columnIndex],
      reason: "to decode \(columnType), but found \(storageClass)",
      sql: _statement.sql
    )
  }
}

@usableFromInline
final class QueryValueCursor<QueryValue: QueryRepresentable>: QueryCursor<QueryValue.QueryOutput> {
  public typealias Element = QueryValue.QueryOutput

  // NB: Required to workaround a "Legacy previews execution" bug
  //     https://github.com/pointfreeco/sqlite-data/pull/60
  @usableFromInline
  override init(db: Database, prepared: PreparedQuery, cached: Bool) throws {
    try super.init(db: db, prepared: prepared, cached: cached)
  }

  @inlinable
  public override func _element(sqliteStatement _: SQLiteStatement) throws -> Element {
    do {
      let element = try QueryValue(decoder: &decoder).queryOutput
      decoder.next()
      return element
    } catch QueryDecodingError.missingRequiredColumn {
      throw missingRequiredColumnError()
    } catch QueryDecodingError.typeMismatch(let columnType) {
      throw typeMismatchError(columnType)
    }
  }
}

@usableFromInline
final class QuerySectionedCursor<
  Element: QueryRepresentable,
  SectionName: QueryRepresentable
>: QueryCursor<(Element.QueryOutput, SectionName.QueryOutput)> {
  // NB: Required to workaround a "Legacy previews execution" bug
  //     https://github.com/pointfreeco/sqlite-data/pull/60
  @usableFromInline
  override init(db: Database, prepared: PreparedQuery, cached: Bool) throws {
    try super.init(db: db, prepared: prepared, cached: cached)
  }

  @inlinable
  public override func _element(
    sqliteStatement _: SQLiteStatement
  ) throws -> (Element.QueryOutput, SectionName.QueryOutput) {
    do {
      let element = try Element(decoder: &decoder).queryOutput
      let sectionName = try SectionName(decoder: &decoder).queryOutput
      decoder.next()
      return (element, sectionName)
    } catch QueryDecodingError.missingRequiredColumn {
      throw missingRequiredColumnError()
    }
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
@usableFromInline
final class QueryPackCursor<
  each QueryValue: QueryRepresentable
>: QueryCursor<(repeat (each QueryValue).QueryOutput)> {
  public typealias Element = (repeat (each QueryValue).QueryOutput)

  // NB: Required to workaround a "Legacy previews execution" bug
  //     https://github.com/pointfreeco/sqlite-data/pull/60
  @usableFromInline
  override init(db: Database, prepared: PreparedQuery, cached: Bool) throws {
    try super.init(db: db, prepared: prepared, cached: cached)
  }

  @inlinable
  public override func _element(sqliteStatement _: SQLiteStatement) throws -> Element {
    do {
      let element = try decoder.decodeColumns((repeat each QueryValue).self)
      decoder.next()
      return element
    } catch QueryDecodingError.missingRequiredColumn {
      throw missingRequiredColumnError()
    } catch QueryDecodingError.typeMismatch(let columnType) {
      throw typeMismatchError(columnType)
    }
  }
}

@usableFromInline
final class QueryVoidCursor: QueryCursor<Void> {
  typealias Element = ()

  // NB: Required to workaround a "Legacy previews execution" bug
  //     https://github.com/pointfreeco/sqlite-data/pull/60
  @usableFromInline
  override init(db: Database, prepared: PreparedQuery, cached: Bool) throws {
    try super.init(db: db, prepared: prepared, cached: cached)
  }

  @inlinable
  override func _element(sqliteStatement _: SQLiteStatement) throws {
    try decoder.decodeColumns(Void.self)
    decoder.next()
  }
}

@usableFromInline
struct PreparedQuery: Hashable, Sendable {
  @usableFromInline
  let sql: String

  @usableFromInline
  let bindings: [QueryBinding]

  @usableFromInline
  init(_ query: QueryFragment) {
    var (sql, bindings) = query.prepare { _ in "?" }
    if sql.isEmpty {
      sql = "SELECT 1 WHERE 0 -- Empty query generated by StructuredQueries"
    }
    self.sql = sql
    self.bindings = bindings
  }
}

extension Database {
  @usableFromInline
  func prepare(
    _ prepared: PreparedQuery, cached: Bool
  ) throws -> (GRDB.Statement, SQLiteQueryDecoder) {
    let statement: GRDB.Statement
    if cached {
      statement = try cachedStatement(sql: prepared.sql)
      sqlite3_reset(statement.sqliteStatement)
    } else {
      statement = try makeStatement(sql: prepared.sql)
    }
    for (index, binding) in zip(Int32(1)..., prepared.bindings) {
      try binding.bind(to: statement.sqliteStatement, at: index)
    }
    return (
      statement,
      SQLiteQueryDecoder(statement: statement.sqliteStatement)
    )
  }
}

extension QueryBinding {
  @usableFromInline
  func bind(to statement: SQLiteStatement, at index: Int32) throws {
    let result: Int32
    switch self {
    case .blob(let blob):
      result =
        blob.isEmpty
        ? sqlite3_bind_zeroblob(statement, index, 0)
        : sqlite3_bind_blob(statement, index, blob, Int32(blob.count), SQLITE_TRANSIENT)
    case .bool(let bool):
      result = sqlite3_bind_int64(statement, index, bool ? 1 : 0)
    case .date(let date):
      result = date.iso8601String.withUTF8Text {
        sqlite3_bind_text(statement, index, $0, $1, SQLITE_TRANSIENT)
      }
    case .double(let double):
      result = sqlite3_bind_double(statement, index, double)
    case .int(let int):
      result = sqlite3_bind_int64(statement, index, int)
    case .null:
      result = sqlite3_bind_null(statement, index)
    case .text(let text):
      result = text.withUTF8Text {
        sqlite3_bind_text(statement, index, $0, $1, SQLITE_TRANSIENT)
      }
    case .uint(let uint) where uint <= UInt64(Int64.max):
      result = sqlite3_bind_int64(statement, index, Int64(uint))
    case .uint(let uint):
      throw Int64OverflowError(unsignedInteger: uint)
    case .uuid(let uuid):
      result = uuid.withLowercasedUTF8Text {
        sqlite3_bind_text(statement, index, $0, $1, SQLITE_TRANSIENT)
      }
    case .invalid(let error):
      throw error
    }
    guard result == SQLITE_OK
    else { throw DatabaseError(resultCode: ResultCode(rawValue: result)) }
  }
}

extension String {
  func withUTF8Text<R>(_ body: (UnsafePointer<CChar>, Int32) -> R) -> R {
    var text = self
    return text.withUTF8 { utf8 in
      guard let base = utf8.baseAddress
      else { return withUnsafePointer(to: 0 as CChar) { body($0, 0) } }
      return base.withMemoryRebound(to: CChar.self, capacity: utf8.count) {
        body($0, Int32(utf8.count))
      }
    }
  }
}

extension UUID {
  func withLowercasedUTF8Text<R>(_ body: (UnsafePointer<CChar>, Int32) -> R) -> R {
    withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 36) { utf8 in
      withUnsafeBytes(of: uuid) { bytes in
        var offset = 0
        for (byteIndex, byte) in bytes.enumerated() {
          if byteIndex == 4 || byteIndex == 6 || byteIndex == 8 || byteIndex == 10 {
            utf8[offset] = UInt8(ascii: "-")
            offset += 1
          }
          utf8[offset] = hexDigits[Int(byte >> 4)]
          utf8[offset + 1] = hexDigits[Int(byte & 0xF)]
          offset += 2
        }
      }
      return utf8.baseAddress!.withMemoryRebound(to: CChar.self, capacity: 36) {
        body($0, 36)
      }
    }
  }
}

private let hexDigits = Array("0123456789abcdef".utf8)

@usableFromInline
struct Int64OverflowError: Error {
  let unsignedInteger: UInt64
  @usableFromInline
  init(unsignedInteger: UInt64) {
    self.unsignedInteger = unsignedInteger
  }
}
