import Dependencies
import Dispatch
import GRDB
import Sharing
import StructuredQueriesCore
import StructuredQueriesGRDBCore

#if canImport(SwiftUI)
  import SwiftUI
#endif

// MARK: Basics

extension SharedReaderKey {
  /// A key that can query for a collection of data in a SQLite database.
  ///
  /// This key takes a query built using the StructuredQueries library.
  ///
  /// ```swift
  /// @SharedReader(.fetchAll(Item.order(by: \.name))) var items
  /// ```
  ///
  /// - Parameters:
  ///   - statement: A structured query describing the data to be fetched.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  public static func fetchAll<S: SelectStatement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil
  ) -> Self
  where
  S.QueryValue == (),
  S.Joins == (),
  Self == FetchKey<[S.From.QueryOutput]>.Default
  {
    let statement = statement.selectStar()
    return fetchAll(statement, database: database)
  }

  /// A key that can query for a collection of data in a SQLite database.
  ///
  /// This key takes a query built using the StructuredQueries library.
  ///
  /// ```swift
  /// @SharedReader(.fetchAll(Item.order(by: \.name))) var items
  /// ```
  ///
  /// - Parameters:
  ///   - statement: A structured query describing the data to be fetched.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  public static func fetchAll<S: StructuredQueriesCore.Statement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil
  ) -> Self
  where S.QueryValue: QueryRepresentable, Self == FetchKey<[S.QueryValue.QueryOutput]>.Default {
    fetch(FetchAllStatementValueRequest(statement: statement), database: database)
  }

  /// A key that can query for a value in a SQLite database.
  ///
  /// This key takes a query built using the StructuredQueries library.
  ///
  /// - Parameters:
  ///   - statement: A structured query describing the data to be fetched.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  public static func fetchOne<S: SelectStatement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil
  ) -> Self
  where
  S.QueryValue == (),
  S.Joins == (),
  Self == FetchKey<S.From.QueryOutput>
  {
    let statement = statement.selectStar()
    return fetchOne(statement, database: database)
  }

  /// A key that can query for a value in a SQLite database.
  ///
  /// This key takes a query built using the StructuredQueries library.
  ///
  /// ```swift
  /// @SharedReader(.fetchOne(Item.count())) var itemCount = 0
  /// ```
  ///
  /// - Parameters:
  ///   - statement: A structured query describing the data to be fetched.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  public static func fetchOne<Value: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<Value>,
    database: (any DatabaseReader)? = nil
  ) -> Self
  where Self == FetchKey<Value.QueryOutput> {
    fetch(FetchOneStatementValueRequest(statement: statement), database: database)
  }
}

// MARK: Parameter pack overloads

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SharedReaderKey {
  /// A key that can query for a collection of data in a SQLite database.
  ///
  /// This key takes a query built using the StructuredQueries library.
  ///
  /// ```swift
  /// @SharedReader(.fetchAll(Item.order(by: \.name))) var items
  /// ```
  ///
  /// - Parameters:
  ///   - statement: A structured query describing the data to be fetched.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  @_disfavoredOverload
  public static func fetchAll<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    _ statement: S,
    database: (any DatabaseReader)? = nil
  ) -> Self
  where
    S.QueryValue == (),
    S.Joins == (repeat each J),
    Self == FetchKey<[(S.From.QueryOutput, repeat (each J).QueryOutput)]>.Default
  {
    fetchAll(statement.selectStar(), database: database)
  }

  /// A key that can query for a collection of data in a SQLite database.
  ///
  /// This key takes a query built using the StructuredQueries library.
  ///
  /// ```swift
  /// @SharedReader(.fetchAll(Item.order(by: \.name))) var items
  /// ```
  ///
  /// - Parameters:
  ///   - statement: A structured query describing the data to be fetched.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  @_disfavoredOverload
  public static func fetchAll<
    S: StructuredQueriesCore.Statement,
    V1: QueryRepresentable,
    each V2: QueryRepresentable
  >(
    _ statement: S,
    database: (any DatabaseReader)? = nil
  ) -> Self
  where
    S.QueryValue == (V1, repeat each V2),
    Self == FetchKey<[(V1.QueryOutput, repeat (each V2).QueryOutput)]>.Default
  {
    fetch(FetchAllStatementPackRequest(statement: statement), database: database)
  }

  /// A key that can query for a value in a SQLite database.
  ///
  /// This key takes a query built using the StructuredQueries library.
  ///
  /// ```swift
  /// @SharedReader(.fetchAll(Item.order(by: \.name))) var items
  /// ```
  ///
  /// - Parameters:
  ///   - statement: A structured query describing the data to be fetched.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  @_disfavoredOverload
  public static func fetchOne<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    _ statement: S,
    database: (any DatabaseReader)? = nil
  ) -> Self
  where
    S.QueryValue == (),
    S.Joins == (repeat each J),
    Self == FetchKey<(S.From.QueryOutput, repeat (each J).QueryOutput)>
  {
    fetchOne(statement.selectStar(), database: database)
  }

  /// A key that can query for a value in a SQLite database.
  ///
  /// This key takes a query built using the StructuredQueries library.
  ///
  /// ```swift
  /// @SharedReader(.fetchOne(Item.count())) var itemCount = 0
  /// ```
  ///
  /// - Parameters:
  ///   - statement: A structured query describing the data to be fetched.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  @_disfavoredOverload
  public static func fetchOne<each Value: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<(repeat each Value)>,
    database: (any DatabaseReader)? = nil
  ) -> Self
  where Self == FetchKey<(repeat (each Value).QueryOutput)> {
    fetch(FetchOneStatementPackRequest(statement: statement), database: database)
  }
}

// MARK: - Scheduling

extension SharedReaderKey {
  /// A key that can query for a collection of data in a SQLite database.
  ///
  /// A version of `fetchAll` that can be configured with a scheduler.
  ///
  /// - Parameters:
  ///   - statement: A structured query describing the data to be fetched.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  public static func fetchAll<S: SelectStatement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) -> Self
  where
    S.QueryValue == (),
    S.Joins == (),
    Self == FetchKey<[S.From.QueryOutput]>.Default
  {
    let statement = statement.selectStar()
    return fetchAll(statement, database: database, scheduler: scheduler)
  }

  /// A key that can query for a collection of data in a SQLite database.
  ///
  /// A version of `fetchAll` that can be configured with a scheduler.
  ///
  /// - Parameters:
  ///   - statement: A structured query describing the data to be fetched.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  public static func fetchAll<S: StructuredQueriesCore.Statement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) -> Self
  where S.QueryValue: QueryRepresentable, Self == FetchKey<[S.QueryValue.QueryOutput]>.Default {
    fetch(
      FetchAllStatementValueRequest(statement: statement), database: database, scheduler: scheduler
    )
  }

  /// A key that can query for a value in a SQLite database.
  ///
  /// A version of `fetchOne` that can be configured with a scheduler.
  ///
  /// - Parameters:
  ///   - statement: A structured query describing the data to be fetched.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  public static func fetchOne<S: SelectStatement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) -> Self
  where
    S.QueryValue == (),
    S.Joins == (),
    Self == FetchKey<S.From.QueryOutput>
  {
    let statement = statement.selectStar()
    return fetchOne(statement, database: database, scheduler: scheduler)
  }

  /// A key that can query for a value in a SQLite database.
  ///
  /// A version of `fetchOne` that can be configured with a scheduler.
  ///
  /// - Parameters:
  ///   - statement: A structured query describing the data to be fetched.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  public static func fetchOne<Value: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<Value>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) -> Self
  where Self == FetchKey<Value.QueryOutput> {
    fetch(
      FetchOneStatementValueRequest(statement: statement), database: database, scheduler: scheduler
    )
  }
}

// MARK: Parameter pack overloads

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SharedReaderKey {
  /// A key that can query for a collection of data in a SQLite database.
  ///
  /// A version of `fetchAll` that can be configured with a scheduler.
  ///
  /// - Parameters:
  ///   - statement: A structured query describing the data to be fetched.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  @_disfavoredOverload
  @_documentation(visibility: private)
  public static func fetchAll<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) -> Self
  where
    S.QueryValue == (),
    S.Joins == (repeat each J),
    Self == FetchKey<[(S.From.QueryOutput, repeat (each J).QueryOutput)]>.Default
  {
    fetchAll(statement.selectStar(), database: database, scheduler: scheduler)
  }

  /// A key that can query for a collection of data in a SQLite database.
  ///
  /// A version of `fetchAll` that can be configured with a scheduler.
  ///
  /// - Parameters:
  ///   - statement: A structured query describing the data to be fetched.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  @_disfavoredOverload
  @_documentation(visibility: private)
  public static func fetchAll<
    S: StructuredQueriesCore.Statement,
    V1: QueryRepresentable,
    each V2: QueryRepresentable
  >(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) -> Self
  where
    S.QueryValue == (V1, repeat each V2),
    Self == FetchKey<[(V1.QueryOutput, repeat (each V2).QueryOutput)]>.Default
  {
    fetch(
      FetchAllStatementPackRequest(statement: statement), database: database, scheduler: scheduler
    )
  }

  /// A key that can query for a value in a SQLite database.
  ///
  /// A version of `fetchOne` that can be configured with a scheduler.
  ///
  /// - Parameters:
  ///   - statement: A structured query describing the data to be fetched.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  @_disfavoredOverload
  @_documentation(visibility: private)
  public static func fetchOne<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) -> Self
  where
    S.QueryValue == (),
    S.Joins == (repeat each J),
    Self == FetchKey<(S.From.QueryOutput, repeat (each J).QueryOutput)>
  {
    fetchOne(statement.selectStar(), database: database, scheduler: scheduler)
  }

  /// A key that can query for a value in a SQLite database.
  ///
  /// A version of `fetchOne` that can be configured with a scheduler.
  ///
  /// - Parameters:
  ///   - statement: A structured query describing the data to be fetched.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
  @_disfavoredOverload
  @_documentation(visibility: private)
  public static func fetchOne<each Value: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<(repeat each Value)>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) -> Self
  where Self == FetchKey<(repeat (each Value).QueryOutput)> {
    fetch(
      FetchOneStatementPackRequest(statement: statement), database: database, scheduler: scheduler
    )
  }
}

// MARK: - Animation

#if canImport(SwiftUI)
  extension SharedReaderKey {
    /// A key that can query for a collection of data in a SQLite database.
    ///
    /// A version of `fetchAll` that can be configured with a SwiftUI animation.
    ///
    /// - Parameters:
    ///   - statement: A structured query describing the data to be fetched.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
    public static func fetchAll<S: SelectStatement>(
      _ statement: S,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where
      S.QueryValue == (),
      S.Joins == (),
      Self == FetchKey<[S.From.QueryOutput]>.Default
    {
      let statement = statement.selectStar()
      return fetchAll(statement, database: database, animation: animation)
    }

    /// A key that can query for a collection of data in a SQLite database.
    ///
    /// A version of `fetchAll` that can be configured with a SwiftUI animation.
    ///
    /// - Parameters:
    ///   - statement: A structured query describing the data to be fetched.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
    public static func fetchAll<Value: QueryRepresentable>(
      _ statement: some StructuredQueriesCore.Statement<Value>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where Self == FetchKey<[Value.QueryOutput]>.Default {
      fetch(
        FetchAllStatementValueRequest(statement: statement),
        database: database,
        animation: animation
      )
    }

    /// A key that can query for a value in a SQLite database.
    ///
    /// A version of `fetchOne` that can be configured with a SwiftUI animation.
    ///
    /// - Parameters:
    ///   - statement: A structured query describing the data to be fetched.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
    public static func fetchOne<S: SelectStatement>(
      _ statement: S,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where
      S.QueryValue == (),
      S.Joins == (),
      Self == FetchKey<S.From.QueryOutput>
    {
      let statement = statement.selectStar()
      return fetchOne(statement, database: database, animation: animation)
    }

    /// A key that can query for a collection of value in a SQLite database.
    ///
    /// A version of `fetchOne` that can be configured with a SwiftUI animation.
    ///
    /// - Parameters:
    ///   - statement: A structured query describing the data to be fetched.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
    public static func fetchOne<Value: QueryRepresentable>(
      _ statement: some StructuredQueriesCore.Statement<Value>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where Self == FetchKey<Value.QueryOutput> {
      fetch(
        FetchOneStatementValueRequest(statement: statement),
        database: database,
        animation: animation
      )
    }
  }

  // MARK: Parameter pack overloads

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SharedReaderKey {
    /// A key that can query for a collection of data in a SQLite database.
    ///
    /// A version of ``Sharing/SharedReaderKey/fetchAll(_:database:)`` that can be configured with a
    /// SwiftUI animation.
    ///
    /// - Parameters:
    ///   - statement: A structured query describing the data to be fetched.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
    @_disfavoredOverload
    @_documentation(visibility: private)
    public static func fetchAll<S: SelectStatement, each J: StructuredQueriesCore.Table>(
      _ statement: S,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where
      S.QueryValue == (),
      S.Joins == (repeat each J),
      Self == FetchKey<[(S.From.QueryOutput, repeat (each J).QueryOutput)]>.Default
    {
      fetchAll(statement.selectStar(), database: database, animation: animation)
    }

    /// A key that can query for a collection of data in a SQLite database.
    ///
    /// A version of ``Sharing/SharedReaderKey/fetchAll(_:database:)`` that can be configured with a
    /// SwiftUI animation.
    ///
    /// - Parameters:
    ///   - statement: A structured query describing the data to be fetched.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
    @_disfavoredOverload
    @_documentation(visibility: private)
    public static func fetchAll<each Value: QueryRepresentable>(
      _ statement: some StructuredQueriesCore.Statement<(repeat each Value)>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where Self == FetchKey<[(repeat (each Value).QueryOutput)]>.Default {
      fetch(
        FetchAllStatementPackRequest(statement: statement),
        database: database,
        animation: animation
      )
    }

    /// A key that can query for a value in a SQLite database.
    ///
    /// A version of ``Sharing/SharedReaderKey/fetchOne(_:database:)`` that can be configured with a
    /// SwiftUI animation.
    ///
    /// - Parameters:
    ///   - statement: A structured query describing the data to be fetched.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
    @_disfavoredOverload
    @_documentation(visibility: private)
    public static func fetchOne<S: SelectStatement, each J: StructuredQueriesCore.Table>(
      _ statement: S,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where
      S.QueryValue == (),
      S.Joins == (repeat each J),
      Self == FetchKey<(S.From.QueryOutput, repeat (each J).QueryOutput)>
    {
      fetchOne(statement.selectStar(), database: database, animation: animation)
    }

    /// A key that can query for a value in a SQLite database.
    ///
    /// A version of ``Sharing/SharedReaderKey/fetchOne(_:database:)`` that can be configured with a
    /// SwiftUI animation.
    ///
    /// - Parameters:
    ///   - statement: A structured query describing the data to be fetched.
    ///   - database: The database to read from. A value of `nil` will use the default database.
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
    @_disfavoredOverload
    @_documentation(visibility: private)
    public static func fetchOne<each Value: QueryRepresentable>(
      _ statement: some StructuredQueriesCore.Statement<(repeat each Value)>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where Self == FetchKey<(repeat (each Value).QueryOutput)> {
      fetch(
        FetchOneStatementPackRequest(statement: statement),
        database: database,
        animation: animation
      )
    }
  }
#endif

// MARK: -

private struct FetchAllStatementValueRequest<Value: QueryRepresentable>: StatementKeyRequest {
  let statement: any StructuredQueriesCore.Statement<Value>
  func fetch(_ db: Database) throws -> [Value.QueryOutput] {
    try statement.fetchAll(db)
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
private struct FetchAllStatementPackRequest<each Value: QueryRepresentable>: StatementKeyRequest {
  let statement: any StructuredQueriesCore.Statement<(repeat each Value)>
  func fetch(_ db: Database) throws -> [(repeat (each Value).QueryOutput)] {
    try statement.fetchAll(db)
  }
}

private struct FetchOneStatementValueRequest<Value: QueryRepresentable>: StatementKeyRequest {
  let statement: any StructuredQueriesCore.Statement<Value>
  func fetch(_ db: Database) throws -> Value.QueryOutput {
    guard let result = try statement.fetchOne(db)
    else { throw NotFound() }
    return result
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
private struct FetchOneStatementPackRequest<each Value: QueryRepresentable>: StatementKeyRequest {
  let statement: any StructuredQueriesCore.Statement<(repeat each Value)>
  func fetch(_ db: Database) throws -> (repeat (each Value).QueryOutput) {
    guard let result = try statement.fetchOne(db)
    else { throw NotFound() }
    return result
  }
}

private protocol StatementKeyRequest<QueryValue>: FetchKeyRequest {
  associatedtype QueryValue
  var statement: any StructuredQueriesCore.Statement<QueryValue> { get }
}

extension StatementKeyRequest {
  static func == (lhs: Self, rhs: Self) -> Bool {
    // NB: A Swift 6.1 regression prevents this from compiling:
    //     https://github.com/swiftlang/swift/issues/79623
    // return AnyHashable(lhs.statement) == AnyHashable(rhs.statement)
    let lhs = lhs.statement
    let rhs = rhs.statement
    return AnyHashable(lhs) == AnyHashable(rhs)
  }

  func hash(into hasher: inout Hasher) {
    // NB: A Swift 6.1 regression prevents this from compiling:
    //     https://github.com/swiftlang/swift/issues/79623
    // hasher.combine(statement)
    let statement = statement
    hasher.combine(statement)
  }
}
