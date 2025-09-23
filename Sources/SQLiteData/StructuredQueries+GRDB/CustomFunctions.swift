import Foundation
import GRDBSQLite

extension Database {
  /// Adds a user-defined `@DatabaseFunction` to a connection.
  ///
  /// - Parameter function: A database function to add.
  public func add(function: some ScalarDatabaseFunction) {
    sqlite3_create_function_v2(
      sqliteConnection,
      function.name,
      function.argumentCount,
      function.textEncoding,
      Unmanaged.passRetained(ScalarDatabaseFunctionBox(function)).toOpaque(),
      { context, argumentCount, arguments in
        do {
          var decoder = SQLiteFunctionDecoder(argumentCount: argumentCount, arguments: arguments)
          try Unmanaged<ScalarDatabaseFunctionBox>
            .fromOpaque(sqlite3_user_data(context))
            .takeUnretainedValue()
            .function
            .invoke(&decoder)
            .result(db: context)
        } catch {
          QueryBinding.invalid(error).result(db: context)
        }
      },
      nil,
      nil,
      { box in
        guard let box else { return }
        Unmanaged<ScalarDatabaseFunctionBox>.fromOpaque(box).release()
      }
    )
  }

  /// Deletes a user-defined `@DatabaseFunction` from a connection.
  ///
  /// - Parameter function: A database function to delete.
  public func remove(function: some ScalarDatabaseFunction) {
    sqlite3_create_function_v2(
      sqliteConnection,
      function.name,
      function.argumentCount,
      function.textEncoding,
      nil,
      nil,
      nil,
      nil,
      nil
    )
  }
}

extension ScalarDatabaseFunction {
  fileprivate var argumentCount: Int32 {
    Int32(argumentCount ?? -1)
  }

  fileprivate var textEncoding: Int32 {
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
    case .blob(let blob):
      sqlite3_result_blob(db, Array(blob), Int32(blob.count), SQLITE_TRANSIENT)
    case .bool(let bool):
      sqlite3_result_int64(db, bool ? 1 : 0)
    case .double(let double):
      sqlite3_result_double(db, double)
    case .date(let date):
      sqlite3_result_text(db, date.iso8601String, -1, SQLITE_TRANSIENT)
    case .int(let int):
      sqlite3_result_int64(db, int)
    case .null:
      sqlite3_result_null(db)
    case .text(let text):
      sqlite3_result_text(db, text, -1, SQLITE_TRANSIENT)
    case .uint(let uint) where uint <= UInt64(Int64.max):
      sqlite3_result_int64(db, Int64(uint))
    case .uint(let uint):
      sqlite3_result_error(db, "Unsigned integer \(uint) overflows Int64.max", -1)
    case .uuid(let uuid):
      sqlite3_result_text(db, uuid.uuidString.lowercased(), -1, SQLITE_TRANSIENT)
    case .invalid(let error):
      sqlite3_result_error(db, error.underlyingError.localizedDescription, -1)
    }
  }
}

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
