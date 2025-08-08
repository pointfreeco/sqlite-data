#if canImport(Combine)
  import Combine
#endif
#if canImport(SwiftUI)
  import SwiftUI
#endif

// NB: Deprecated after 0.2.2

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
@available(
  *,
  deprecated,
  message: "Use the '@Selection' macro to bundle multiple values into a value."
)
extension FetchAll {
  @_disfavoredOverload
  public init<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    wrappedValue: [Element] = [],
    _ statement: S,
    database: (any DatabaseReader)? = nil
  )
  where
    Element == (S.From.QueryOutput, repeat (each J).QueryOutput),
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == (repeat each J),
    repeat (each J).QueryOutput: Sendable
  {
    let statement = statement.selectStar()
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetch(FetchAllStatementPackRequest(statement: statement), database: database)
    )
  }

  @_disfavoredOverload
  public init<V1: QueryRepresentable, each V2: QueryRepresentable>(
    wrappedValue: [Element] = [],
    _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
    database: (any DatabaseReader)? = nil
  )
  where
    Element == (V1.QueryOutput, repeat (each V2).QueryOutput),
    V1.QueryOutput: Sendable,
    repeat (each V2).QueryOutput: Sendable
  {
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetch(
        FetchAllStatementPackRequest(statement: statement),
        database: database
      )
    )
  }

  @_disfavoredOverload
  public func load<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    _ statement: S,
    database: (any DatabaseReader)? = nil
  ) async throws
  where
    Element == (S.From.QueryOutput, repeat (each J).QueryOutput),
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == (repeat each J),
    repeat (each J).QueryOutput: Sendable
  {
    let statement = statement.selectStar()
    try await sharedReader.load(
      .fetch(
        FetchAllStatementPackRequest(statement: statement),
        database: database
      )
    )
  }

  @_disfavoredOverload
  public func load<V1: QueryRepresentable, each V2: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
    database: (any DatabaseReader)? = nil
  ) async throws
  where
    Element == (V1.QueryOutput, repeat (each V2).QueryOutput),
    V1.QueryOutput: Sendable,
    repeat (each V2).QueryOutput: Sendable
  {
    try await sharedReader.load(
      .fetch(
        FetchAllStatementPackRequest(statement: statement),
        database: database
      )
    )
  }

  @_disfavoredOverload
  public init<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    wrappedValue: [Element] = [],
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Element == (S.From.QueryOutput, repeat (each J).QueryOutput),
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == (repeat each J),
    repeat (each J).QueryOutput: Sendable
  {
    let statement = statement.selectStar()
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetch(
        FetchAllStatementPackRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
    )
  }

  @_disfavoredOverload
  public init<V1: QueryRepresentable, each V2: QueryRepresentable>(
    wrappedValue: [Element] = [],
    _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Element == (V1.QueryOutput, repeat (each V2).QueryOutput),
    V1.QueryOutput: Sendable,
    repeat (each V2).QueryOutput: Sendable
  {
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetch(
        FetchAllStatementPackRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
    )
  }

  @_disfavoredOverload
  public func load<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws
  where
    Element == (S.From.QueryOutput, repeat (each J).QueryOutput),
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == (repeat each J),
    repeat (each J).QueryOutput: Sendable
  {
    let statement = statement.selectStar()
    try await sharedReader.load(
      .fetch(
        FetchAllStatementPackRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
    )
  }

  @_disfavoredOverload
  public func load<V1: QueryRepresentable, each V2: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws
  where
    Element == (V1.QueryOutput, repeat (each V2).QueryOutput),
    V1.QueryOutput: Sendable,
    repeat (each V2).QueryOutput: Sendable
  {
    try await sharedReader.load(
      .fetch(
        FetchAllStatementPackRequest(statement: statement),
        database: database
      )
    )
  }

  #if canImport(SwiftUI)
    @_disfavoredOverload
    public init<S: SelectStatement, each J: StructuredQueriesCore.Table>(
      wrappedValue: [Element] = [],
      _ statement: S,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
      Element == (S.From.QueryOutput, repeat (each J).QueryOutput),
      S.QueryValue == (),
      S.From.QueryOutput: Sendable,
      S.Joins == (repeat each J),
      repeat (each J).QueryOutput: Sendable
    {
      let statement = statement.selectStar()
      sharedReader = SharedReader(
        wrappedValue: wrappedValue,
        .fetch(
          FetchAllStatementPackRequest(statement: statement),
          database: database,
          animation: animation
        )
      )
    }

    @_disfavoredOverload
    public init<V1: QueryRepresentable, each V2: QueryRepresentable>(
      wrappedValue: [Element] = [],
      _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
      Element == (V1.QueryOutput, repeat (each V2).QueryOutput),
      V1.QueryOutput: Sendable,
      repeat (each V2).QueryOutput: Sendable
    {
      sharedReader = SharedReader(
        wrappedValue: wrappedValue,
        .fetch(
          FetchAllStatementPackRequest(statement: statement),
          database: database,
          animation: animation
        )
      )
    }

    @_disfavoredOverload
    public func load<S: SelectStatement, each J: StructuredQueriesCore.Table>(
      _ statement: S,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) async throws
    where
      Element == (S.From.QueryOutput, repeat (each J).QueryOutput),
      S.QueryValue == (),
      S.From.QueryOutput: Sendable,
      S.Joins == (repeat each J),
      repeat (each J).QueryOutput: Sendable
    {
      let statement = statement.selectStar()
      try await sharedReader.load(
        .fetch(
          FetchAllStatementPackRequest(statement: statement),
          database: database,
          animation: animation
        )
      )
    }

    @_disfavoredOverload
    public func load<V1: QueryRepresentable, each V2: QueryRepresentable>(
      _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) async throws
    where
      Element == (V1.QueryOutput, repeat (each V2).QueryOutput),
      V1.QueryOutput: Sendable,
      repeat (each V2).QueryOutput: Sendable
    {
      try await sharedReader.load(
        .fetch(
          FetchAllStatementPackRequest(statement: statement),
          database: database,
          animation: animation
        )
      )
    }
  #endif
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
private struct FetchAllStatementPackRequest<each Value: QueryRepresentable>: StatementKeyRequest {
  let statement: SQLQueryExpression<(repeat each Value)>
  init(statement: some StructuredQueriesCore.Statement<(repeat each Value)>) {
    self.statement = SQLQueryExpression(statement)
  }
  func fetch(_ db: Database) throws -> [(repeat (each Value).QueryOutput)] {
    try statement.fetchAll(db)
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
@available(
  *,
  deprecated,
  message: "Use the '@Selection' macro to bundle multiple values into a value."
)
extension FetchOne {
  @_disfavoredOverload
  public init<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    wrappedValue: (S.From.QueryOutput, repeat (each J).QueryOutput),
    _ statement: S,
    database: (any DatabaseReader)? = nil
  )
  where
    Value == (S.From.QueryOutput, repeat (each J).QueryOutput),
    S.QueryValue == (),
    S.Joins == (repeat each J)
  {
    let statement = statement.selectStar()
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetch(
        FetchOneStatementPackRequest(statement: statement),
        database: database
      )
    )
  }

  @_disfavoredOverload
  public init<V1: QueryRepresentable, each V2: QueryRepresentable>(
    wrappedValue: (V1.QueryOutput, repeat (each V2).QueryOutput),
    _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
    database: (any DatabaseReader)? = nil
  )
  where
    Value == (V1.QueryOutput, repeat (each V2).QueryOutput)
  {
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetch(
        FetchOneStatementPackRequest(statement: statement),
        database: database
      )
    )
  }

  @_disfavoredOverload
  public func load<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    _ statement: S,
    database: (any DatabaseReader)? = nil
  ) async throws
  where
    Value == (S.From.QueryOutput, repeat (each J).QueryOutput),
    S.QueryValue == (),
    S.Joins == (repeat each J)
  {
    let statement = statement.selectStar()
    try await sharedReader.load(
      .fetch(
        FetchOneStatementPackRequest(statement: statement),
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
  @_disfavoredOverload
  public func load<V1: QueryRepresentable, each V2: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
    database: (any DatabaseReader)? = nil
  ) async throws
  where
    Value == (V1.QueryOutput, repeat (each V2).QueryOutput)
  {
    try await sharedReader.load(
      .fetch(
        FetchOneStatementPackRequest(statement: statement),
        database: database
      )
    )
  }

  @_disfavoredOverload
  public init<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    wrappedValue: (S.From.QueryOutput, repeat (each J).QueryOutput),
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Value == (S.From.QueryOutput, repeat (each J).QueryOutput),
    S.QueryValue == (),
    S.Joins == (repeat each J)
  {
    let statement = statement.selectStar()
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetch(
        FetchOneStatementPackRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
    )
  }

  @_disfavoredOverload
  public init<V1: QueryRepresentable, each V2: QueryRepresentable>(
    wrappedValue: (V1.QueryOutput, repeat (each V2).QueryOutput),
    _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Value == (V1.QueryOutput, repeat (each V2).QueryOutput)
  {
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetch(
        FetchOneStatementPackRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
    )
  }

  @_disfavoredOverload
  public func load<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws
  where
    Value == (S.From.QueryOutput, repeat (each J).QueryOutput),
    S.QueryValue == (),
    S.Joins == (repeat each J)
  {
    let statement = statement.selectStar()
    try await sharedReader.load(
      .fetch(
        FetchOneStatementPackRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
    )
  }

  @_disfavoredOverload
  public func load<V1: QueryRepresentable, each V2: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws
  where
    Value == (V1.QueryOutput, repeat (each V2).QueryOutput)
  {
    try await sharedReader.load(
      .fetch(
        FetchOneStatementPackRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
    )
  }

  #if canImport(SwiftUI)
    @_disfavoredOverload
    public init<S: SelectStatement, each J: StructuredQueriesCore.Table>(
      wrappedValue: (S.From.QueryOutput, repeat (each J).QueryOutput),
      _ statement: S,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
      Value == (S.From.QueryOutput, repeat (each J).QueryOutput),
      S.QueryValue == (),
      S.Joins == (repeat each J)
    {
      let statement = statement.selectStar()
      sharedReader = SharedReader(
        wrappedValue: wrappedValue,
        .fetch(
          FetchOneStatementPackRequest(statement: statement),
          database: database,
          animation: animation
        )
      )
    }

    @_disfavoredOverload
    public init<V1: QueryRepresentable, each V2: QueryRepresentable>(
      wrappedValue: (V1.QueryOutput, repeat (each V2).QueryOutput),
      _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
      Value == (V1.QueryOutput, repeat (each V2).QueryOutput)
    {
      sharedReader = SharedReader(
        wrappedValue: wrappedValue,
        .fetch(
          FetchOneStatementPackRequest(statement: statement),
          database: database,
          animation: animation
        )
      )
    }

    @_disfavoredOverload
    public func load<S: SelectStatement, each J: StructuredQueriesCore.Table>(
      _ statement: S,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) async throws
    where
      Value == (S.From.QueryOutput, repeat (each J).QueryOutput),
      S.QueryValue == (),
      S.Joins == (repeat each J)
    {
      let statement = statement.selectStar()
      try await sharedReader.load(
        .fetch(
          FetchOneStatementPackRequest(statement: statement),
          database: database,
          animation: animation
        )
      )
    }

    @_disfavoredOverload
    public func load<V1: QueryRepresentable, each V2: QueryRepresentable>(
      _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) async throws
    where
      Value == (V1.QueryOutput, repeat (each V2).QueryOutput)
    {
      try await sharedReader.load(
        .fetch(
          FetchOneStatementPackRequest(statement: statement),
          database: database,
          animation: animation
        )
      )
    }

  #endif
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
private struct FetchOneStatementPackRequest<each Value: QueryRepresentable>: StatementKeyRequest {
  let statement: SQLQueryExpression<(repeat each Value)>
  init(statement: some StructuredQueriesCore.Statement<(repeat each Value)>) {
    self.statement = SQLQueryExpression(statement)
  }
  func fetch(_ db: Database) throws -> (repeat (each Value).QueryOutput) {
    guard let result = try statement.fetchOne(db)
    else { throw NotFound() }
    return result
  }
}
