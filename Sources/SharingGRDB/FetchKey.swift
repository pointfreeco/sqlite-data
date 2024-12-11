import Dependencies
import GRDB
import Sharing
import SwiftUI

#if canImport(Combine)
  @preconcurrency import Combine
#endif

extension SharedReaderKey {
  /// A key that can query for data in a SQLite database.
  ///
  /// This key takes a ``FetchKeyRequest`` conformance, which you define yourself. It has a single
  /// requirement that describes fetching a value from a database connection. For examples, we can
  /// define an `Items` request that uses GRDB's query builder to fetch some items:
  ///
  /// ```swift
  /// struct Items: FetchKeyRequest {
  ///   func fetch(_ db: Database) throws -> [Item] {
  ///     try Item.all()
  ///       .order(Column("timestamp").desc)
  ///       .fetchAll(db)
  ///   }
  /// }
  /// ```
  ///
  /// And one can query for this data by wrapping the request in this key and provide it to the
  /// `@SharedReader` property wrapper:
  ///
  /// ```swift
  /// @SharedReader(.fetch(Items()) var items
  /// ```
  ///
  /// For simpler querying needs, you can skip the ceremony of defining a ``FetchKeyRequest`` and
  /// use a raw SQL query with
  /// ``Sharing/SharedReaderKey/fetchAll(sql:arguments:database:scheduler:)`` or
  /// ``Sharing/SharedReaderKey/fetchOne(sql:arguments:database:scheduler:)``, instead.
  ///
  /// - Parameters:
  ///   - request: A request describing the data to fetch.
  ///   - database: The database to read from. A value of `nil` will use the
  ///     ``Dependencies/DependencyValues/defaultDatabase``.
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  public static func fetch<Value>(
    _ request: some FetchKeyRequest<Value>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler = .async(onQueue: .main)
  ) -> Self
  where Self == FetchKey<Value> {
    FetchKey(request: request, database: database, scheduler: scheduler)
  }

  /// A key that can query for a collection of data in a SQLite database.
  ///
  /// A version of ``Sharing/SharedReaderKey/fetch(_:database:scheduler:)-8kkig`` that allows you to
  /// omit the type and default from the `@SharedReader` property wrapper:
  ///
  /// ```diff
  /// -@SharedReader(.fetch(Items()) var items: [Item] = []
  /// +@SharedReader(.fetch(Items()) var items
  /// ```
  ///
  /// See ``Sharing/SharedReaderKey/fetch(_:database:scheduler:)-8kkig`` for more info on how to
  /// use this API.
  ///
  /// - Parameters:
  ///   - request: A request describing the data to fetch.
  ///   - database: The database to read from. A value of `nil` will use the
  ///     ``Dependencies/DependencyValues/defaultDatabase``.
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  public static func fetch<Records: RangeReplaceableCollection>(
    _ request: some FetchKeyRequest<Records>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler = .async(onQueue: .main)
  ) -> Self
  where Self == FetchKey<Records>.Default {
    Self[.fetch(request, database: database, scheduler: scheduler), default: Value()]
  }

  /// A key that can query for a collection of data in a SQLite database.
  ///
  /// This key gives you the ability to fetch and observe the results of a raw SQL query decoded to
  /// some `GRDB.FetchableRecord` type:
  ///
  /// ```swift
  /// @SharedReader(.fetchAll(sql: "SELECT * FROM items")) var items: [Item]
  /// ```
  ///
  /// For more complex querying needs, see
  /// ``Sharing/SharedReaderKey/fetch(_:database:scheduler:)-8kkig``.
  ///
  /// - Parameters:
  ///   - sql: A raw SQL string describing the data to fetch.
  ///   - arguments: Arguments to bind to the SQL statement.
  ///   - database: The database to read from. A value of `nil` will use the
  ///     ``Dependencies/DependencyValues/defaultDatabase``.
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  public static func fetchAll<Record: FetchableRecord>(
    sql: String,
    arguments: StatementArguments = StatementArguments(),
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler = .async(onQueue: .main)
  ) -> Self
  where Self == FetchKey<[Record]>.Default {
    Self[
      .fetch(FetchAll(sql: sql, arguments: arguments), database: database, scheduler: scheduler),
      default: []
    ]
  }

  /// A key that can query for a value in a SQLite database.
  ///
  /// This key gives you the ability to fetch and observe the result of a raw SQL query converted to
  /// some `GRDB.DatabaseValueConvertible` type:
  ///
  /// ```swift
  /// @SharedReader(.fetchOne(sql: "SELECT count(*) FROM items")) var itemsCount = 0
  /// ```
  ///
  /// For more complex querying needs, see
  /// ``Sharing/SharedReaderKey/fetch(_:database:scheduler:)-8kkig``.
  ///
  /// - Parameters:
  ///   - sql: A raw SQL string describing the data to fetch.
  ///   - arguments: Arguments to bind to the SQL statement.
  ///   - database: The database to read from. A value of `nil` will use the
  ///     ``Dependencies/DependencyValues/defaultDatabase``.
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  public static func fetchOne<Value: DatabaseValueConvertible>(
    sql: String,
    arguments: StatementArguments = StatementArguments(),
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler = .async(onQueue: .main)
  ) -> Self
  where Self == FetchKey<Value> {
    .fetch(FetchOne(sql: sql, arguments: arguments), database: database, scheduler: scheduler)
  }
}

/// A type defining a reader of GRDB queries.
///
/// You typically do not refer to this type directly, and will use
/// [`fetchAll`](<doc:Sharing/SharedReaderKey/fetchAll(sql:arguments:database:scheduler:)>),
/// [`fetchOne`](<doc:Sharing/SharedReaderKey/fetchOne(sql:arguments:database:scheduler:)>), and
/// [`fetch`](<doc:Sharing/SharedReaderKey/fetch(_:database:scheduler:)-8m3f7>) to create instances,
/// instead.
public struct FetchKey<Value: Sendable>: SharedReaderKey {
  let database: any DatabaseReader
  let request: any FetchKeyRequest<Value>
  let scheduler: any ValueObservationScheduler
  #if DEBUG
    let isDefaultDatabase: Bool
  #endif

  public typealias ID = FetchKeyID

  public var id: ID { ID(rawValue: request) }

  init(
    request: some FetchKeyRequest<Value>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler = .async(onQueue: .main)
  ) {
    @Dependency(\.defaultDatabase) var defaultDatabase
    self.scheduler = scheduler
    self.database = database ?? defaultDatabase
    self.request = request
    #if DEBUG
      self.isDefaultDatabase = self.database.configuration.label == .defaultDatabaseLabel
    #endif
  }

  public func load(context: LoadContext<Value>, continuation: LoadContinuation<Value>) {
    #if DEBUG
      guard !isDefaultDatabase else {
        continuation.resumeReturningInitialValue()
        return
      }
    #endif
    guard case .userInitiated = context else {
      continuation.resumeReturningInitialValue()
      return
    }
    guard !isTesting else {
      continuation.resume(with: Result { try database.read(request.fetch) })
      return
    }
    database.asyncRead { dbResult in
      let result = dbResult.flatMap { db in
        Result {
          try request.fetch(db)
        }
      }
      scheduler.schedule {
        switch result {
        case let .success(value):
          continuation.resume(returning: value)
        case let .failure(error) where error is NotFound:
          continuation.resumeReturningInitialValue()
        case let .failure(error):
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func subscribe(
    context: LoadContext<Value>, subscriber: SharedSubscriber<Value>
  ) -> SharedSubscription {
    #if DEBUG
      guard !isDefaultDatabase else {
        return SharedSubscription {}
      }
    #endif
    let observation = ValueObservation.tracking { db in
      Result { try request.fetch(db) }
    }
    #if canImport(Combine)
      let dropFirst =
        switch context {
        case .initialValue: false
        case .userInitiated: true
        }
      let cancellable = observation.publisher(in: database, scheduling: scheduler)
        .dropFirst(dropFirst ? 1 : 0)
        .sink { completion in
          switch completion {
          case let .failure(error):
            subscriber.yield(throwing: error)
          case .finished:
            break
          }
        } receiveValue: { newValue in
          switch newValue {
          case let .success(value):
            subscriber.yield(value)
          case let .failure(error) where error is NotFound:
            subscriber.yieldReturningInitialValue()
          case let .failure(error):
            subscriber.yield(throwing: error)
          }
        }
      return SharedSubscription {
        cancellable.cancel()
      }
    #else
      let cancellable = observation.start(in: database, scheduling: scheduler) { error in
        subscriber.yield(throwing: error)
      } onChange: { newValue in
        subscriber.yield(newValue)
      }
      return SharedSubscription {
        cancellable.cancel()
      }
    #endif
  }
}

/// A value that uniquely identifies a fetch key.
public struct FetchKeyID: Hashable {
  fileprivate let rawValue: AnyHashableSendable
  fileprivate let typeID: ObjectIdentifier

  fileprivate init(rawValue: some FetchKeyRequest) {
    self.rawValue = AnyHashableSendable(rawValue)
    self.typeID = ObjectIdentifier(type(of: rawValue))
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(rawValue)
    hasher.combine(typeID)
  }
}

private struct FetchAll<Element: FetchableRecord>: FetchKeyRequest {
  var sql: String
  var arguments: StatementArguments = StatementArguments()
  func fetch(_ db: Database) throws -> [Element] {
    try Element.fetchAll(db, sql: sql, arguments: arguments)
  }
}

private struct FetchOne<Value: DatabaseValueConvertible>: FetchKeyRequest {
  var sql: String
  var arguments: StatementArguments = StatementArguments()
  func fetch(_ db: Database) throws -> Value {
    guard let value = try Value.fetchOne(db, sql: sql, arguments: arguments)
    else { throw NotFound() }
    return value
  }
}

private struct NotFound: Error {}
