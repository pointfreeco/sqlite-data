#if canImport(Combine)
  import Combine
#endif
#if canImport(SwiftUI)
  import SwiftUI
#endif

/// A property that can query for a value in a SQLite database.
///
/// It takes a query built using the StructuredQueries library:
///
/// ```swift
/// @FetchOne(Item.count) var itemsCount = 0
/// ```
///
/// See <doc:Fetching> for more information.
@dynamicMemberLookup
@propertyWrapper
public struct FetchOne<Value: Sendable>: Sendable {
  /// The underlying shared reader powering the property wrapper.
  ///
  /// Shared readers come from the [Sharing](https://github.com/pointfreeco/swift-sharing) package,
  /// a general solution to observing and persisting changes to external data sources.
  public var sharedReader: SharedReader<Value>

  /// A value associated with the underlying query.
  public var wrappedValue: Value {
    sharedReader.wrappedValue
  }

  /// Returns this property wrapper.
  ///
  /// Useful if you want to access various property wrapper state, like ``loadError``,
  /// ``isLoading``, and ``publisher``.
  public var projectedValue: Self {
    get { self }
    nonmutating set { sharedReader.projectedValue = newValue.sharedReader.projectedValue }
  }

  /// Returns a ``sharedReader`` for the given key path.
  ///
  /// You do not invoke this subscript directly. Instead, Swift calls it for you when chaining into
  /// a member of the underlying data type.
  public subscript<Member>(dynamicMember keyPath: KeyPath<Value, Member>) -> SharedReader<Member> {
    sharedReader[dynamicMember: keyPath]
  }

  /// An error encountered during the most recent attempt to load data.
  public var loadError: (any Error)? {
    sharedReader.loadError
  }

  /// Whether or not data is loading from the database.
  public var isLoading: Bool {
    sharedReader.isLoading
  }

  /// Reloads data from the database.
  public func load() async throws {
    try await sharedReader.load()
  }

  #if canImport(Combine)
    /// A publisher that emits events when the database observes changes to the query.
    public var publisher: some Publisher<Value, Never> {
      sharedReader.publisher
    }
  #endif

  /// Initializes this property with a wrapped value.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to associate with this property.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init(
    wrappedValue: sending Value,
    database: (any DatabaseReader)? = nil
  ) {
    sharedReader = SharedReader(value: wrappedValue)
  }

  /// Initializes this property with a wrapped value.
  ///
  /// - Parameters database: The database to read from. A value of `nil` will use the default
  ///   database (`@Dependency(\.defaultDatabase)`).
  public init<Wrapped>(
    database: (any DatabaseReader)? = nil
  ) where Value == Wrapped? {
    self.init(wrappedValue: nil, database: database)
  }

  /// Initializes this property with a query associated with the wrapped value.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init<S: SelectStatement>(
    wrappedValue: S.From.QueryOutput,
    _ statement: S,
    database: (any DatabaseReader)? = nil
  )
  where
    Value == S.From.QueryOutput,
    S.QueryValue == (),
    S.Joins == ()
  {
    let statement = statement.selectStar().asSelect().limit(1)
    self.init(wrappedValue: wrappedValue, statement, database: database)
  }

  /// Initializes this property with a query associated with the wrapped value.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init<V: QueryRepresentable>(
    wrappedValue: V.QueryOutput,
    _ statement: some StructuredQueriesCore.Statement<V>,
    database: (any DatabaseReader)? = nil
  )
  where
    Value == V.QueryOutput
  {
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetch(
        FetchOneStatementValueRequest(statement: statement),
        database: database
      )
    )
  }

  /// Initializes this property with a query associated with the wrapped value.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init<S: StructuredQueriesCore.Statement<Value>>(
    wrappedValue: Value,
    _ statement: S,
    database: (any DatabaseReader)? = nil
  )
  where
    Value: QueryRepresentable,
    Value == S.QueryValue.QueryOutput
  {
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetch(
        FetchOneStatementValueRequest(statement: statement),
        database: database
      )
    )
  }

  /// Initializes this property with a query associated with an optional value.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init<S: SelectStatement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil
  )
  where
  Value == S.From.QueryOutput?,
  S.QueryValue == (),
  S.Joins == ()
  {
    let statement = statement.selectStar().asSelect().limit(1)
    self.init(statement, database: database)
  }

  /// Initializes this property with a query associated with an optional value.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init<S: StructuredQueriesCore.Statement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil
  )
  where
  S.QueryValue: QueryRepresentable,
  Value == S.QueryValue.QueryOutput?
  {
    self.init(
      wrappedValue: nil,
      SQLQueryExpression(statement.query, as: S.QueryValue?.self),
      database: database
    )
  }

  /// Replaces the wrapped value with data from the given query.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public func load<S: SelectStatement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil
  ) async throws
  where
    Value == S.From.QueryOutput,
    S.QueryValue == (),
    S.Joins == ()
  {
    let statement = statement.selectStar().asSelect().limit(1)
    try await load(statement, database: database)
  }

  /// Replaces the wrapped value with data from the given query.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public func load<V: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<V>,
    database: (any DatabaseReader)? = nil
  ) async throws
  where
    Value == V.QueryOutput
  {
    try await sharedReader.load(
      .fetch(
        FetchOneStatementValueRequest(statement: statement),
        database: database
      )
    )
  }
}

/// Initializes this property with a query associated with the wrapped value.
///
/// - Parameters:
///   - wrappedValue: A default value to associate with this property.
///   - statement: A query associated with the wrapped value.
///   - database: The database to read from. A value of `nil` will use the default database
///     (`@Dependency(\.defaultDatabase)`).
///   - scheduler: The scheduler to observe from. By default, database observation is performed
///     asynchronously on the main queue.
extension FetchOne {
  public init<S: SelectStatement>(
    wrappedValue: S.From.QueryOutput,
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Value == S.From.QueryOutput,
    S.QueryValue == (),
    S.Joins == ()
  {
    let statement = statement.selectStar().asSelect().limit(1)
    self.init(wrappedValue: wrappedValue, statement, database: database, scheduler: scheduler)
  }

  /// Initializes this property with a query associated with the wrapped value.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init<V: QueryRepresentable>(
    wrappedValue: V.QueryOutput,
    _ statement: some StructuredQueriesCore.Statement<V>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Value == V.QueryOutput
  {
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetch(
        FetchOneStatementValueRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
    )
  }

  /// Initializes this property with a query associated with the wrapped value.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init<S: StructuredQueriesCore.Statement<Value>>(
    wrappedValue: Value,
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Value: QueryRepresentable,
    Value == S.QueryValue.QueryOutput
  {
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetch(
        FetchOneStatementValueRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
    )
  }

  /// Initializes this property with a query associated with an optional value.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init<S: SelectStatement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
  Value == S.From.QueryOutput?,
  S.QueryValue == (),
  S.Joins == ()
  {
    let statement = statement.selectStar().asSelect().limit(1)
    self.init(statement, database: database, scheduler: scheduler)
  }

  /// Initializes this property with a query associated with an optional value.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init<S: StructuredQueriesCore.Statement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
  S.QueryValue: QueryRepresentable,
  Value == S.QueryValue.QueryOutput?
  {
    self.init(
      wrappedValue: nil,
      SQLQueryExpression(statement.query, as: S.QueryValue?.self),
      database: database,
      scheduler: scheduler
    )
  }

  /// Replaces the wrapped value with data from the given query.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public func load<S: SelectStatement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws
  where
    Value == S.From.QueryOutput,
    S.QueryValue == (),
    S.Joins == ()
  {
    let statement = statement.selectStar().asSelect().limit(1)
    try await load(statement, database: database, scheduler: scheduler)
  }

  /// Replaces the wrapped value with data from the given query.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public func load<V: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<V>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws
  where
    Value == V.QueryOutput
  {
    try await sharedReader.load(
      .fetch(
        FetchOneStatementValueRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
    )
  }
}

extension FetchOne: Equatable where Value: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sharedReader == rhs.sharedReader
  }
}

#if canImport(SwiftUI)
  extension FetchOne: DynamicProperty {
    public func update() {
      sharedReader.update()
    }

    /// Initializes this property with a query associated with the wrapped value.
    ///
    /// - Parameters:
    ///   - wrappedValue: A default value to associate with this property.
    ///   - statement: A query associated with the wrapped value.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    public init<S: SelectStatement>(
      wrappedValue: S.From.QueryOutput,
      _ statement: S,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
      Value == S.From.QueryOutput,
      S.QueryValue == (),
      S.Joins == ()
    {
      self.init(
        wrappedValue: wrappedValue,
        statement,
        database: database,
        scheduler: .animation(animation)
      )
    }

    /// Initializes this property with a query associated with the wrapped value.
    ///
    /// - Parameters:
    ///   - wrappedValue: A default value to associate with this property.
    ///   - statement: A query associated with the wrapped value.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    public init<V: QueryRepresentable>(
      wrappedValue: V.QueryOutput,
      _ statement: some StructuredQueriesCore.Statement<V>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
      Value == V.QueryOutput
    {
      self.init(
        wrappedValue: wrappedValue,
        statement,
        database: database,
        scheduler: .animation(animation)
      )
    }

    /// Initializes this property with a query associated with the wrapped value.
    ///
    /// - Parameters:
    ///   - wrappedValue: A default value to associate with this property.
    ///   - statement: A query associated with the wrapped value.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    public init<S: StructuredQueriesCore.Statement<Value>>(
      wrappedValue: Value,
      _ statement: S,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
      Value: QueryRepresentable,
      Value == S.QueryValue.QueryOutput
    {
      self.init(
        wrappedValue: wrappedValue,
        statement,
        database: database,
        scheduler: .animation(animation)
      )
    }


    /// Initializes this property with a query associated with an optional value.
    ///
    /// - Parameters:
    ///   - statement: A query associated with the wrapped value.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    public init<S: SelectStatement>(
      _ statement: S,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
    Value == S.From.QueryOutput?,
    S.QueryValue == (),
    S.Joins == ()
    {
      let statement = statement.selectStar().asSelect().limit(1)
      self.init(statement, database: database, animation: animation)
    }

    /// Initializes this property with a query associated with an optional value.
    ///
    /// - Parameters:
    ///   - wrappedValue: A default value to associate with this property.
    ///   - statement: A query associated with the wrapped value.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    public init<S: StructuredQueriesCore.Statement>(
      _ statement: S,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
    S.QueryValue: QueryRepresentable,
    Value == S.QueryValue.QueryOutput?
    {
      self.init(
        wrappedValue: nil,
        SQLQueryExpression(statement.query, as: S.QueryValue?.self),
        database: database,
        animation: animation
      )
    }

    /// Replaces the wrapped value with data from the given query.
    ///
    /// - Parameters:
    ///   - statement: A query associated with the wrapped value.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    public func load<S: SelectStatement>(
      _ statement: S,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) async throws
    where
      Value == S.From.QueryOutput,
      S.QueryValue == (),
      S.Joins == ()
    {
      try await load(statement, database: database, scheduler: .animation(animation))
    }

    /// Replaces the wrapped value with data from the given query.
    ///
    /// - Parameters:
    ///   - statement: A query associated with the wrapped value.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    public func load<V: QueryRepresentable>(
      _ statement: some StructuredQueriesCore.Statement<V>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) async throws
    where
      Value == V.QueryOutput
    {
      try await load(statement, database: database, scheduler: .animation(animation))
    }
  }
#endif

private struct FetchOneStatementValueRequest<Value: QueryRepresentable>: StatementKeyRequest {
  let statement: any StructuredQueriesCore.Statement<Value>
  func fetch(_ db: Database) throws -> Value.QueryOutput {
    guard let result = try statement.fetchOne(db)
    else { throw NotFound() }
    return result
  }
}
