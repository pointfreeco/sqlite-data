import Dependencies
import Dispatch
import Foundation
import GRDB
import Sharing
import StructuredQueriesGRDBCore

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
  ///     try Item.all
  ///       .order { $0.timestamp.desc() }
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
  /// use a raw SQL query with ``Sharing/SharedReaderKey/fetchAll(sql:arguments:database:)`` or
  /// ``Sharing/SharedReaderKey/fetchOne(sql:arguments:database:)``, instead.
  ///
  /// To animate or observe changes with a custom scheduler, see
  /// ``Sharing/SharedReaderKey/fetch(_:database:animation:)`` or
  /// ``Sharing/SharedReaderKey/fetch(_:database:scheduler:)``.
  ///
  /// - Parameters:
  ///   - request: A request describing the data to fetch.
  ///   - database: The database to read from. A value of `nil` will use
  ///     `@Dependency(\.defaultDatabase)`.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  @available(iOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
  @available(macOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
  @available(tvOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
  @available(watchOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
  public static func fetch<Value>(
    _ request: some FetchKeyRequest<Value>,
    database: (any DatabaseReader)? = nil
  ) -> Self
  where Self == FetchKey<Value> {
    FetchKey(request: request, database: database, scheduler: nil)
  }

  /// A key that can query for a collection of data in a SQLite database.
  ///
  /// A version of `fetch` that allows you to omit the type and default from the `@SharedReader`
  /// property wrapper:
  ///
  /// ```diff
  /// -@SharedReader(.fetch(Items()) var items: [Item] = []
  /// +@SharedReader(.fetch(Items()) var items
  /// ```
  ///
  /// - Parameters:
  ///   - request: A request describing the data to fetch.
  ///   - database: The database to read from. A value of `nil` will use
  ///     `@Dependency(\.defaultDatabase)`.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  @available(iOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
  @available(macOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
  @available(tvOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
  @available(watchOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
  public static func fetch<Records: RangeReplaceableCollection>(
    _ request: some FetchKeyRequest<Records>,
    database: (any DatabaseReader)? = nil
  ) -> Self
  where Self == FetchKey<Records>.Default {
    Self[.fetch(request, database: database), default: Value()]
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
  /// For more complex querying needs, see ``Sharing/SharedReaderKey/fetch(_:database:)``.
  ///
  /// - Parameters:
  ///   - sql: A raw SQL string describing the data to fetch.
  ///   - arguments: Arguments to bind to the SQL statement.
  ///   - database: The database to read from. A value of `nil` will use
  ///     `@Dependency(\.defaultDatabase)`.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  @available(iOS, deprecated: 9999, message: "Use '@FetchAll' and '#sql', instead")
  @available(macOS, deprecated: 9999, message: "Use '@FetchAll' and '#sql', instead")
  @available(tvOS, deprecated: 9999, message: "Use '@FetchAll' and '#sql', instead")
  @available(watchOS, deprecated: 9999, message: "Use '@FetchAll' and '#sql', instead")
  public static func fetchAll<Record: FetchableRecord>(
    sql: String,
    arguments: StatementArguments = StatementArguments(),
    database: (any DatabaseReader)? = nil
  ) -> Self
  where Self == FetchKey<[Record]>.Default {
    Self[
      .fetch(FetchAllRequest(sql: sql, arguments: arguments), database: database),
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
  /// For more complex querying needs, see ``Sharing/SharedReaderKey/fetch(_:database:)``.
  ///
  /// - Parameters:
  ///   - sql: A raw SQL string describing the data to fetch.
  ///   - arguments: Arguments to bind to the SQL statement.
  ///   - database: The database to read from. A value of `nil` will use
  ///     `@Dependency(\.defaultDatabase)`.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  @available(iOS, deprecated: 9999, message: "Use '@FetchOne' and '#sql', instead")
  @available(macOS, deprecated: 9999, message: "Use '@FetchOne' and '#sql', instead")
  @available(tvOS, deprecated: 9999, message: "Use '@FetchOne' and '#sql', instead")
  @available(watchOS, deprecated: 9999, message: "Use '@FetchOne' and '#sql', instead")
  public static func fetchOne<Value: DatabaseValueConvertible>(
    sql: String,
    arguments: StatementArguments = StatementArguments(),
    database: (any DatabaseReader)? = nil
  ) -> Self
  where Self == FetchKey<Value> {
    .fetch(FetchOneRequest(sql: sql, arguments: arguments), database: database)
  }
}

extension SharedReaderKey {
  /// A key that can query for data in a SQLite database.
  ///
  /// A version of ``Sharing/SharedReaderKey/fetch(_:database:)`` that can be configured with a
  /// scheduler. See ``Sharing/SharedReaderKey/fetch(_:database:)`` for more info on how to use this
  /// API.
  ///
  /// - Parameters:
  ///   - request: A request describing the data to fetch.
  ///   - database: The database to read from. A value of `nil` will use
  ///     `@Dependency(\.defaultDatabase)`.
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  @available(iOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
  @available(macOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
  @available(tvOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
  @available(watchOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
  public static func fetch<Value>(
    _ request: some FetchKeyRequest<Value>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) -> Self
  where Self == FetchKey<Value> {
    FetchKey(request: request, database: database, scheduler: scheduler)
  }

  /// A key that can query for a collection of data in a SQLite database.
  ///
  /// A version of ``Sharing/SharedReaderKey/fetch(_:database:)`` that can be configured with a
  /// scheduler. See ``Sharing/SharedReaderKey/fetch(_:database:)`` for more info on how to use this
  /// API.
  ///
  /// - Parameters:
  ///   - request: A request describing the data to fetch.
  ///   - database: The database to read from. A value of `nil` will use
  ///     `@Dependency(\.defaultDatabase)`.
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  @available(iOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
  @available(macOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
  @available(tvOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
  @available(watchOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
  public static func fetch<Records: RangeReplaceableCollection>(
    _ request: some FetchKeyRequest<Records>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) -> Self
  where Self == FetchKey<Records>.Default {
    Self[.fetch(request, database: database, scheduler: scheduler), default: Value()]
  }

  /// A key that can query for a collection of data in a SQLite database.
  ///
  /// A version of ``Sharing/SharedReaderKey/fetchAll(sql:arguments:database:)`` that can be
  /// configured with a scheduler. See ``Sharing/SharedReaderKey/fetchAll(sql:arguments:database:)``
  /// for more info on how to use this API.
  ///
  /// - Parameters:
  ///   - sql: A raw SQL string describing the data to fetch.
  ///   - arguments: Arguments to bind to the SQL statement.
  ///   - database: The database to read from. A value of `nil` will use
  ///     `@Dependency(\.defaultDatabase)`.
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  @available(iOS, deprecated: 9999, message: "Use '@FetchAll' and '#sql', instead")
  @available(macOS, deprecated: 9999, message: "Use '@FetchAll' and '#sql', instead")
  @available(tvOS, deprecated: 9999, message: "Use '@FetchAll' and '#sql', instead")
  @available(watchOS, deprecated: 9999, message: "Use '@FetchAll' and '#sql', instead")
  public static func fetchAll<Record: FetchableRecord>(
    sql: String,
    arguments: StatementArguments = StatementArguments(),
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) -> Self
  where Self == FetchKey<[Record]>.Default {
    Self[
      .fetch(
        FetchAllRequest(sql: sql, arguments: arguments), database: database, scheduler: scheduler
      ),
      default: []
    ]
  }

  /// A key that can query for a value in a SQLite database.
  ///
  /// A version of ``Sharing/SharedReaderKey/fetchOne(sql:arguments:database:)`` that can be
  /// configured with a scheduler. See ``Sharing/SharedReaderKey/fetchOne(sql:arguments:database:)``
  /// for more info on how to use this API.
  ///
  /// - Parameters:
  ///   - sql: A raw SQL string describing the data to fetch.
  ///   - arguments: Arguments to bind to the SQL statement.
  ///   - database: The database to read from. A value of `nil` will use
  ///     `@Dependency(\.defaultDatabase)`.
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  @available(iOS, deprecated: 9999, message: "Use '@FetchOne' and '#sql', instead")
  @available(macOS, deprecated: 9999, message: "Use '@FetchOne' and '#sql', instead")
  @available(tvOS, deprecated: 9999, message: "Use '@FetchOne' and '#sql', instead")
  @available(watchOS, deprecated: 9999, message: "Use '@FetchOne' and '#sql', instead")
  public static func fetchOne<Value: DatabaseValueConvertible>(
    sql: String,
    arguments: StatementArguments = StatementArguments(),
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) -> Self
  where Self == FetchKey<Value> {
    .fetch(
      FetchOneRequest(sql: sql, arguments: arguments), database: database, scheduler: scheduler
    )
  }
}

/// A type defining a reader of GRDB queries.
///
/// You typically do not refer to this type directly, and will use
/// [`fetchAll`](<doc:Sharing/SharedReaderKey/fetchAll(sql:arguments:database:)>),
/// [`fetchOne`](<doc:Sharing/SharedReaderKey/fetchOne(sql:arguments:database:)>), and
/// [`fetch`](<doc:Sharing/SharedReaderKey/fetch(_:database:)>) to create instances, instead.
public struct FetchKey<Value: Sendable>: SharedReaderKey {
  let database: any DatabaseReader
  let request: any FetchKeyRequest<Value>
  let scheduler: (any ValueObservationScheduler & Hashable)?
  #if DEBUG
    let isDefaultDatabase: Bool
  #endif

  public typealias ID = FetchKeyID

  public var id: ID {
    ID(database: database, request: request, scheduler: scheduler)
  }

  init(
    request: some FetchKeyRequest<Value>,
    database: (any DatabaseReader)? = nil,
    scheduler: (any ValueObservationScheduler & Hashable)?
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
    let scheduler: any ValueObservationScheduler = scheduler ?? ImmediateScheduler()
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

    let scheduler: any ValueObservationScheduler = scheduler ?? ImmediateScheduler()
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
        switch newValue {
        case let .success(value):
          subscriber.yield(value)
        case let .failure(error):
          subscriber.yield(throwing: error)
        }
      }
      return SharedSubscription {
        cancellable.cancel()
      }
    #endif
  }
}

/// A value that uniquely identifies a fetch key.
public struct FetchKeyID: Hashable {
  fileprivate let databaseID: ObjectIdentifier
  fileprivate let request: AnyHashableSendable
  fileprivate let requestTypeID: ObjectIdentifier
  fileprivate let scheduler: AnyHashableSendable?

  fileprivate init(
    database: any DatabaseReader,
    request: some FetchKeyRequest,
    scheduler: (any ValueObservationScheduler & Hashable)?
  ) {
    self.databaseID = ObjectIdentifier(database)
    self.request = AnyHashableSendable(request)
    self.requestTypeID = ObjectIdentifier(type(of: request))
    self.scheduler = scheduler.map { AnyHashableSendable($0) }
  }
}

private struct FetchAllRequest<Element: FetchableRecord>: FetchKeyRequest {
  var sql: String
  var arguments: StatementArguments = StatementArguments()
  func fetch(_ db: Database) throws -> [Element] {
    try Element.fetchAll(db, sql: sql, arguments: arguments)
  }
}

private struct FetchOneRequest<Value: DatabaseValueConvertible>: FetchKeyRequest {
  var sql: String
  var arguments: StatementArguments = StatementArguments()
  func fetch(_ db: Database) throws -> Value {
    guard let value = try Value.fetchOne(db, sql: sql, arguments: arguments)
    else { throw NotFound() }
    return value
  }
}

public struct NotFound: Error {
  public init() {}
}

private struct ImmediateScheduler: ValueObservationScheduler, Hashable {
  func immediateInitialValue() -> Bool { true }
  func schedule(_ action: @escaping @Sendable () -> Void) {
    action()
  }
}
