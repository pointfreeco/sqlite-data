import Foundation
import GRDBSQLite

extension Database {
  /// Adds a user-defined scalar `@DatabaseFunction` to a connection.
  ///
  /// - Parameter function: A scalar database function to add.
  public func add(function: some ScalarDatabaseFunction) {
    sqlite3_create_function_v2(
      sqliteConnection,
      function.name,
      function.argumentCount,
      function.textEncoding,
      Unmanaged.passRetained(ScalarDatabaseFunctionDefinition(function)).toOpaque(),
      { context, argumentCount, arguments in
        do {
          var decoder = SQLiteFunctionDecoder(argumentCount: argumentCount, arguments: arguments)
          try Unmanaged<ScalarDatabaseFunctionDefinition>
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
      { context in
        guard let context else { return }
        Unmanaged<ScalarDatabaseFunctionDefinition>.fromOpaque(context).release()
      }
    )
  }

  /// Adds a user-defined aggregate `@DatabaseFunction` to a connection.
  ///
  /// - Parameter function: An aggregate database function to add.
  public func add(function: some AggregateDatabaseFunction) {
    let body = Unmanaged.passRetained(AggregateDatabaseFunctionDefinition(function)).toOpaque()
    sqlite3_create_function_v2(
      sqliteConnection,
      function.name,
      function.argumentCount,
      function.textEncoding,
      body,
      nil,
      { context, argumentCount, arguments in
        var decoder = SQLiteFunctionDecoder(argumentCount: argumentCount, arguments: arguments)
        let function = AggregateDatabaseFunctionContext[context].takeUnretainedValue()
        do {
          try function.iterator.step(&decoder)
        } catch {
          sqlite3_result_error(context, error.localizedDescription, -1)
        }
      },
      { context in
        let unmanagedFunction = AggregateDatabaseFunctionContext[context]
        let function = unmanagedFunction.takeUnretainedValue()
        unmanagedFunction.release()
        function.iterator.finish()
        do {
          try function.iterator.result.result(db: context)
        } catch {
          sqlite3_result_error(context, error.localizedDescription, -1)
        }
      },
      { context in
        guard let context else { return }
        Unmanaged<AggregateDatabaseFunctionContext>.fromOpaque(context).release()
      }
    )
  }

  /// Deletes a user-defined `@DatabaseFunction` from a connection.
  ///
  /// - Parameter function: A database function to delete.
  public func remove(function: some DatabaseFunction) {
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

extension DatabaseFunction {
  fileprivate var argumentCount: Int32 {
    Int32(argumentCount ?? -1)
  }

  fileprivate var textEncoding: Int32 {
    SQLITE_UTF8 | (isDeterministic ? SQLITE_DETERMINISTIC : 0)
  }
}

private final class ScalarDatabaseFunctionDefinition {
  let function: any ScalarDatabaseFunction
  init(_ function: some ScalarDatabaseFunction) {
    self.function = function
  }
}

private final class AggregateDatabaseFunctionDefinition {
  let function: any AggregateDatabaseFunction
  init(_ function: some AggregateDatabaseFunction) {
    self.function = function
  }
}

private final class AggregateDatabaseFunctionContext {
  static subscript(context: OpaquePointer?) -> Unmanaged<AggregateDatabaseFunctionContext> {
    let size = MemoryLayout<Unmanaged<AggregateDatabaseFunctionContext>>.size
    let pointer = sqlite3_aggregate_context(context, Int32(size))!
    if pointer.load(as: Int.self) == 0 {
      let definition = Unmanaged<AggregateDatabaseFunctionDefinition>
        .fromOpaque(sqlite3_user_data(context))
        .takeUnretainedValue()
      let context = AggregateDatabaseFunctionContext(definition.function)
      let unmanagedContext = Unmanaged.passRetained(context)
      pointer
        .assumingMemoryBound(to: Unmanaged<AggregateDatabaseFunctionContext>.self)
        .pointee = unmanagedContext
      return unmanagedContext
    } else {
      return
        pointer
        .assumingMemoryBound(to: Unmanaged<AggregateDatabaseFunctionContext>.self)
        .pointee
    }
  }
  let iterator: any AggregateDatabaseFunctionIteratorProtocol
  init(_ body: some AggregateDatabaseFunction) {
    self.iterator = AggregateDatabaseFunctionIterator(body)
  }
}

private protocol AggregateDatabaseFunctionIteratorProtocol<Body> {
  associatedtype Body: AggregateDatabaseFunction

  var body: Body { get }
  var stream: Stream<Body.Element> { get }
  func start()
  func step(_ decoder: inout some QueryDecoder) throws
  func finish()
  var result: QueryBinding { get throws }
}

private final class AggregateDatabaseFunctionIterator<
  Body: AggregateDatabaseFunction
>: AggregateDatabaseFunctionIteratorProtocol {
  let body: Body
  let stream = Stream<Body.Element>()
  let queue: DispatchQueue
  var _result: QueryBinding?
  init(_ body: Body) {
    self.body = body
    self.queue = DispatchQueue(
      label: "co.pointfree.StructuredQueriesSQLite.AggregateDatabaseFunction.\(body.name)"
    )
    nonisolated(unsafe) let iterator: any AggregateDatabaseFunctionIteratorProtocol = self
    queue.async {
      iterator.start()
    }
  }
  func start() {
    do {
      _result = try body.invoke(stream)
    } catch {
      _result = .invalid(error)
    }
  }
  func step(_ decoder: inout some QueryDecoder) throws {
    try stream.send(body.step(&decoder))
  }
  func finish() {
    stream.finish()
  }
  var result: QueryBinding {
    get throws {
      while true {
        if let result = queue.sync(execute: { _result }) {
          return result
        }
      }
    }
  }
}

private final class Stream<Element>: Sequence {
  let condition = NSCondition()
  private var buffer: [Element] = []
  private var isFinished = false

  func send(_ element: Element) {
    condition.withLock {
      buffer.append(element)
      condition.signal()
    }
  }

  func finish() {
    condition.withLock {
      isFinished = true
      condition.broadcast()
    }
  }

  func makeIterator() -> Iterator { Iterator(base: self) }

  struct Iterator: IteratorProtocol {
    fileprivate let base: Stream
    mutating func next() -> Element? {
      base.condition.withLock {
        while base.buffer.isEmpty && !base.isFinished {
          base.condition.wait()
        }
        guard !base.buffer.isEmpty else { return nil }
        return base.buffer.removeFirst()
      }
    }
  }
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
