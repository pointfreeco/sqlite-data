import Sharing

#if canImport(Combine)
  import Combine
#endif
#if canImport(SwiftUI)
  import SwiftUI
#endif

/// A property that can query for a collection of data in a SQLite database.
///
/// It takes a query built using the StructuredQueries library:
///
/// ```swift
/// @FetchAll(Item.order(by: \.name)) var items
/// ```
///
/// See <doc:Fetching> for more information.
@dynamicMemberLookup
@propertyWrapper
public struct FetchAll<Element: Sendable>: Sendable {
  /// The underlying shared reader powering the property wrapper.
  ///
  /// Shared readers come from the [Sharing](https://github.com/pointfreeco/swift-sharing) package,
  /// a general solution to observing and persisting changes to external data sources.
  public var sharedReader: SharedReader<[Element]> = SharedReader(value: [])

  /// A collection of data associated with the underlying query.
  public var wrappedValue: [Element] {
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
  public subscript<Member>(
    dynamicMember keyPath: KeyPath<[Element], Member>
  ) -> SharedReader<Member> {
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
    public var publisher: some Publisher<[Element], Never> {
      sharedReader.publisher
    }
  #endif

  /// Initializes this property with a query that fetches every row from a table.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init(
    wrappedValue: [Element] = [],
    database: (any DatabaseReader)? = nil
  )
  where Element: StructuredQueriesCore.Table, Element.QueryOutput == Element {
    let statement = Element.all.selectStar().asSelect()
    self.init(wrappedValue: wrappedValue, statement, database: database)
  }

  /// Initializes this property with a default value.
  @_disfavoredOverload
  public init(wrappedValue: [Element] = []) {
    sharedReader = SharedReader(value: wrappedValue)
  }

  /// Initializes this property with a default value.
  public init(wrappedValue: [Element] = [])
  where Element: StructuredQueriesCore._Selection, Element.QueryOutput == Element {
    sharedReader = SharedReader(value: wrappedValue)
  }

  /// Initializes this property with a query associated with the wrapped value.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init<S: SelectStatement>(
    wrappedValue: [Element] = [],
    _ statement: S,
    database: (any DatabaseReader)? = nil
  )
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    let statement = statement.selectStar()
    self.init(wrappedValue: wrappedValue, statement, database: database)
  }

  /// Initializes this property with a query associated with the wrapped value.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init<V: QueryRepresentable>(
    wrappedValue: [Element] = [],
    _ statement: some StructuredQueriesCore.Statement<V>,
    database: (any DatabaseReader)? = nil
  )
  where
    Element == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetch(
        FetchAllStatementValueRequest(statement: statement),
        database: database
      )
    )
  }

  /// Initializes this property with a query associated with the wrapped value.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init<S: StructuredQueriesCore.Statement<Element>>(
    wrappedValue: [Element] = [],
    _ statement: S,
    database: (any DatabaseReader)? = nil
  )
  where
    Element: QueryRepresentable,
    Element == S.QueryValue.QueryOutput
  {
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetch(
        FetchAllStatementValueRequest(statement: statement),
        database: database
      )
    )
  }

  /// Replaces the wrapped value with data from the given query.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  /// - Returns: A subscription associated with the observation.
  @discardableResult
  public func load<S: SelectStatement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil
  ) async throws -> FetchSubscription
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    let statement = statement.selectStar()
    return try await load(statement, database: database)
  }

  /// Replaces the wrapped value with data from the given query.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  /// - Returns: A subscription associated with the observation.
  @discardableResult
  public func load<V: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<V>,
    database: (any DatabaseReader)? = nil
  ) async throws -> FetchSubscription
  where
    Element == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    try await sharedReader.load(
      .fetch(
        FetchAllStatementValueRequest(statement: statement),
        database: database
      )
    )
    return FetchSubscription(sharedReader: sharedReader)
  }
}

extension FetchAll {
  /// Initializes this property with a query that fetches every row from a table.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init(
    wrappedValue: [Element] = [],
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where Element: StructuredQueriesCore.Table, Element.QueryOutput == Element {
    let statement = Element.all.selectStar().asSelect()
    self.init(wrappedValue: wrappedValue, statement, database: database, scheduler: scheduler)
  }

  /// Initializes this property with a query associated with the wrapped value.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init<S: SelectStatement>(
    wrappedValue: [Element] = [],
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    let statement = statement.selectStar()
    self.init(wrappedValue: wrappedValue, statement, database: database, scheduler: scheduler)
  }

  /// Initializes this property with a query associated with the wrapped value.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init<V: QueryRepresentable>(
    wrappedValue: [Element] = [],
    _ statement: some StructuredQueriesCore.Statement<V>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Element == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetch(
        FetchAllStatementValueRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
    )
  }

  /// Initializes this property with a query associated with the wrapped value.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init<S: StructuredQueriesCore.Statement<Element>>(
    wrappedValue: [Element] = [],
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Element: QueryRepresentable,
    Element == S.QueryValue.QueryOutput
  {
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetch(
        FetchAllStatementValueRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
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
  /// - Returns: A subscription associated with the observation.
  @discardableResult
  public func load<S: SelectStatement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws -> FetchSubscription
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    let statement = statement.selectStar()
    return try await load(statement, database: database, scheduler: scheduler)
  }

  /// Replaces the wrapped value with data from the given query.
  ///
  /// - Parameters:
  ///   - statement: A query associated with the wrapped value.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A subscription associated with the observation.
  @discardableResult
  public func load<V: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<V>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws -> FetchSubscription
  where
    Element == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    try await sharedReader.load(
      .fetch(
        FetchAllStatementValueRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
    )
    return FetchSubscription(sharedReader: sharedReader)
  }
}

extension FetchAll: CustomReflectable {
  public var customMirror: Mirror {
    Mirror(reflecting: wrappedValue)
  }
}

extension FetchAll: Equatable where Element: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sharedReader == rhs.sharedReader
  }
}

#if canImport(SwiftUI)
  extension FetchAll: DynamicProperty {
    public func update() {
      sharedReader.update()
    }

    /// Initializes this property with a query that fetches every row from a table.
    ///
    /// - Parameters:
    ///   - wrappedValue: A default collection to associate with this property.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public init(
      wrappedValue: [Element] = [],
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where Element: StructuredQueriesCore.Table, Element.QueryOutput == Element {
      self.init(wrappedValue: wrappedValue, database: database, scheduler: .animation(animation))
    }

    /// Initializes this property with a query associated with the wrapped value.
    ///
    /// - Parameters:
    ///   - wrappedValue: A default collection to associate with this property.
    ///   - statement: A query associated with the wrapped value.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public init<S: SelectStatement>(
      wrappedValue: [Element] = [],
      _ statement: S,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
      Element == S.From.QueryOutput,
      S.QueryValue == (),
      S.From.QueryOutput: Sendable,
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
    ///   - wrappedValue: A default collection to associate with this property.
    ///   - statement: A query associated with the wrapped value.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public init<V: QueryRepresentable>(
      wrappedValue: [Element] = [],
      _ statement: some StructuredQueriesCore.Statement<V>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
      Element == V.QueryOutput,
      V.QueryOutput: Sendable
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
    ///   - wrappedValue: A default collection to associate with this property.
    ///   - statement: A query associated with the wrapped value.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public init<S: StructuredQueriesCore.Statement<Element>>(
      wrappedValue: [Element] = [],
      _ statement: S,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
      Element: QueryRepresentable,
      Element == S.QueryValue.QueryOutput
    {
      self.init(
        wrappedValue: wrappedValue,
        statement,
        database: database,
        scheduler: .animation(animation)
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
    /// - Returns: A subscription associated with the observation.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @discardableResult
    public func load<S: SelectStatement>(
      _ statement: S,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) async throws -> FetchSubscription
    where
      Element == S.From.QueryOutput,
      S.QueryValue == (),
      S.From.QueryOutput: Sendable,
      S.Joins == ()
    {
      let statement = statement.selectStar()
      return try await load(statement, database: database, animation: animation)
    }

    /// Replaces the wrapped value with data from the given query.
    ///
    /// - Parameters:
    ///   - statement: A query associated with the wrapped value.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A subscription associated with the observation.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @discardableResult
    public func load<V: QueryRepresentable>(
      _ statement: some StructuredQueriesCore.Statement<V>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) async throws -> FetchSubscription
    where
      Element == V.QueryOutput,
      V.QueryOutput: Sendable
    {
      try await sharedReader.load(
        .fetch(
          FetchAllStatementValueRequest(statement: statement),
          database: database,
          animation: animation
        )
      )
      return FetchSubscription(sharedReader: sharedReader)
    }
  }
#endif

private struct FetchAllStatementValueRequest<Value: QueryRepresentable>: StatementKeyRequest {
  let statement: SQLQueryExpression<Value>
  init(statement: some StructuredQueriesCore.Statement<Value>) {
    self.statement = SQLQueryExpression(statement)
  }
  func fetch(_ db: Database) throws -> [Value.QueryOutput] {
    try statement.fetchAll(db)
  }
}
