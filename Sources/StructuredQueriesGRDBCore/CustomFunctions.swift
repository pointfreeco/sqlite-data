import GRDB
import GRDBSQLite
import Foundation

extension ScalarDatabaseFunction {
  /// Adds a user-defined `@DatabaseFunction` to a connection.
  ///
  /// - Parameter db: A database connection.
  public func install(db: Database) {
    let db = db.sqliteConnection
    let box = Unmanaged.passRetained(ScalarDatabaseFunctionBox(self)).toOpaque()
    sqlite3_create_function_v2(
      db,
      name,
      argumentCount,
      textEncoding,
      box,
      { context, argumentCount, arguments in
        Unmanaged<ScalarDatabaseFunctionBox>
          .fromOpaque(sqlite3_user_data(context))
          .takeUnretainedValue()
          .function
          .invoke([QueryBinding](argumentCount: argumentCount, arguments: arguments))
          .result(db: context)
      },
      nil,
      nil,
      { context in
        guard let context else { return }
        Unmanaged<ScalarDatabaseFunctionBox>.fromOpaque(context).release()
      }
    )
  }

  /// Deletes a user-defined `@DatabaseFunction` from a connection.
  ///
  /// - Parameter db: A database connection.
  public func uninstall(db: Database) {
    let db = db.sqliteConnection
    sqlite3_create_function_v2(
      db,
      name,
      argumentCount,
      textEncoding,
      nil,
      nil,
      nil,
      nil,
      nil
    )
  }

  private var argumentCount: Int32 {
    Int32(argumentCount ?? -1)
  }

  private var textEncoding: Int32 {
    SQLITE_UTF8 | (isDeterministic ? SQLITE_DETERMINISTIC : 0)
  }
}

private final class ScalarDatabaseFunctionBox {
  let function: any ScalarDatabaseFunction
  init(_ function: some ScalarDatabaseFunction) {
    self.function = function
  }
}

extension [QueryBinding] {
  fileprivate init(argumentCount: Int32, arguments: UnsafeMutablePointer<OpaquePointer?>?) {
    self = (0..<argumentCount).map { offset in
      let value = arguments?[Int(offset)]
      switch sqlite3_value_type(value) {
      case SQLITE_BLOB:
        if let blob = sqlite3_value_blob(value) {
          let count = Int(sqlite3_value_bytes(value))
          let buffer = UnsafeRawBufferPointer(start: blob, count: count)
          return .blob([UInt8](buffer))
        } else {
          return .blob([])
        }
      case SQLITE_FLOAT:
        return .double(sqlite3_value_double(value))
      case SQLITE_INTEGER:
        return .int(sqlite3_value_int64(value))
      case SQLITE_NULL:
        return .null
      case SQLITE_TEXT:
        return .text(String(cString: UnsafePointer(sqlite3_value_text(value))))
      default:
        return .invalid(UnknownType())
      }
    }
  }

  private struct UnknownType: Error {}
}

extension QueryBinding {
  fileprivate func result(db: OpaquePointer?) {
    switch self {
    case .blob(let value):
      sqlite3_result_blob(db, Array(value), Int32(value.count), SQLITE_TRANSIENT)
    case .double(let value):
      sqlite3_result_double(db, value)
    case .date(let value):
      sqlite3_result_text(db, value.iso8601String, -1, SQLITE_TRANSIENT)
    case .int(let value):
      sqlite3_result_int64(db, value)
    case .null:
      sqlite3_result_null(db)
    case .text(let value):
      sqlite3_result_text(db, value, -1, SQLITE_TRANSIENT)
    case .uuid(let value):
      sqlite3_result_text(db, value.uuidString.lowercased(), -1, SQLITE_TRANSIENT)
    case .invalid(let error):
      sqlite3_result_error(db, error.underlyingError.localizedDescription, -1)
    }
  }
}

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
