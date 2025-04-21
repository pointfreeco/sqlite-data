#if canImport(Combine)
import Combine
#endif
#if canImport(SwiftUI)
  import SwiftUI
#endif

@propertyWrapper
public struct FetchAll<Element>: Sendable {
  public var _sharedReader: SharedReader<[Element]> = SharedReader(value: [])

  public var wrappedValue: [Element] {
    _sharedReader.wrappedValue
  }

  public var projectedValue: Self {
    self
  }

  public var loadError: (any Error)? {
    _sharedReader.loadError
  }

  public var isLoading: Bool {
    _sharedReader.isLoading
  }

  #if canImport(Combine)
    public var publisher: some Publisher<[Element], Never> {
      _sharedReader.publisher
    }
  #endif

  public init() {
    _sharedReader = SharedReader(value: [])
  }

  public init<S: SelectStatement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil
  )
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    let statement = statement.selectStar().asSelect()
    _sharedReader = SharedReader(
      .fetch(
        FetchAllStatementValueRequest(statement: statement),
        database: database
      )
    )
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public init<S: SelectStatement, each J: StructuredQueriesCore.Table>(
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
    let statement = statement.selectStar().asSelect()
    _sharedReader = SharedReader(
      .fetch(FetchAllStatementPackRequest(statement: statement), database: database)
    )
  }

  public init<V: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<V>,
    database: (any DatabaseReader)? = nil
  )
  where
    Element == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    _sharedReader = SharedReader(
      .fetch(
        FetchAllStatementValueRequest(statement: statement),
        database: database
      )
    )
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public init<V1: QueryRepresentable, each V2: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
    database: (any DatabaseReader)? = nil
  )
  where
    Element == (V1.QueryOutput, repeat (each V2).QueryOutput),
    V1.QueryOutput: Sendable,
    repeat (each V2).QueryOutput: Sendable
  {
    _sharedReader = SharedReader(
      .fetch(
        FetchAllStatementPackRequest(statement: statement),
        database: database
      )
    )
  }

  public func load<S: SelectStatement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil
  ) async throws
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    let statement = statement.selectStar().asSelect()
    try await _sharedReader.load(
      .fetch(
        FetchAllStatementValueRequest(statement: statement),
        database: database
      )
    )
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
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
    let statement = statement.selectStar().asSelect()
    try await _sharedReader.load(
      .fetch(
        FetchAllStatementPackRequest(statement: statement),
        database: database
      )
    )
  }

  public func load<V: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<V>,
    database: (any DatabaseReader)? = nil
  ) async throws
  where
    Element == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    try await _sharedReader.load(
      .fetch(
        FetchAllStatementValueRequest(statement: statement),
        database: database
      )
    )
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public func load<V1: QueryRepresentable, each V2: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
    database: (any DatabaseReader)? = nil
  ) async throws
  where
    Element == (V1.QueryOutput, repeat (each V2).QueryOutput),
    V1.QueryOutput: Sendable,
    repeat (each V2).QueryOutput: Sendable
  {
    try await _sharedReader.load(
      .fetch(
        FetchAllStatementPackRequest(statement: statement),
        database: database
      )
    )
  }
}

extension FetchAll {
  public init<S: SelectStatement>(
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
    let statement = statement.selectStar().asSelect()
    _sharedReader = SharedReader(
      .fetch(
        FetchAllStatementValueRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
    )
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public init<S: SelectStatement, each J: StructuredQueriesCore.Table>(
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
    let statement = statement.selectStar().asSelect()
    _sharedReader = SharedReader(
      .fetch(
        FetchAllStatementPackRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
    )
  }

  public init<V: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<V>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Element == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    _sharedReader = SharedReader(
      .fetch(
        FetchAllStatementValueRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
    )
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public init<V1: QueryRepresentable, each V2: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Element == (V1.QueryOutput, repeat (each V2).QueryOutput),
    V1.QueryOutput: Sendable,
    repeat (each V2).QueryOutput: Sendable
  {
    _sharedReader = SharedReader(
      .fetch(
        FetchAllStatementPackRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
    )
  }

  public func load<S: SelectStatement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    let statement = statement.selectStar().asSelect()
    try await _sharedReader.load(
      .fetch(
        FetchAllStatementValueRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
    )
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
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
    let statement = statement.selectStar().asSelect()
    try await _sharedReader.load(
      .fetch(
        FetchAllStatementPackRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
    )
  }

  public func load<V: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<V>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws
  where
    Element == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    try await _sharedReader.load(
      .fetch(
        FetchAllStatementValueRequest(statement: statement),
        database: database,
        scheduler: scheduler
      )
    )
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
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
    try await _sharedReader.load(
      .fetch(
        FetchAllStatementPackRequest(statement: statement),
        database: database
      )
    )
  }
}

#if canImport(SwiftUI)
  extension FetchAll {
    public init<S: SelectStatement>(
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
      let statement = statement.selectStar().asSelect()
      _sharedReader = SharedReader(
        .fetch(
          FetchAllStatementValueRequest(statement: statement),
          database: database,
          animation: animation
        )
      )
    }

    @_disfavoredOverload
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public init<S: SelectStatement, each J: StructuredQueriesCore.Table>(
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
      let statement = statement.selectStar().asSelect()
      _sharedReader = SharedReader(
        .fetch(
          FetchAllStatementPackRequest(statement: statement),
          database: database,
          animation: animation
        )
      )
    }

    public init<V: QueryRepresentable>(
      _ statement: some StructuredQueriesCore.Statement<V>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
      Element == V.QueryOutput,
      V.QueryOutput: Sendable
    {
      _sharedReader = SharedReader(
        .fetch(
          FetchAllStatementValueRequest(statement: statement),
          database: database,
          animation: animation
        )
      )
    }

    @_disfavoredOverload
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public init<V1: QueryRepresentable, each V2: QueryRepresentable>(
      _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    )
    where
      Element == (V1.QueryOutput, repeat (each V2).QueryOutput),
      V1.QueryOutput: Sendable,
      repeat (each V2).QueryOutput: Sendable
    {
      _sharedReader = SharedReader(
        .fetch(
          FetchAllStatementPackRequest(statement: statement),
          database: database,
          animation: animation
        )
      )
    }

    public func load<S: SelectStatement>(
      _ statement: S,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) async throws
    where
      Element == S.From.QueryOutput,
      S.QueryValue == (),
      S.From.QueryOutput: Sendable,
      S.Joins == ()
    {
      let statement = statement.selectStar().asSelect()
      try await _sharedReader.load(
        .fetch(
          FetchAllStatementValueRequest(statement: statement),
          database: database,
          animation: animation
        )
      )
    }

    @_disfavoredOverload
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
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
      let statement = statement.selectStar().asSelect()
      try await _sharedReader.load(
        .fetch(
          FetchAllStatementPackRequest(statement: statement),
          database: database,
          animation: animation
        )
      )
    }

    public func load<V: QueryRepresentable>(
      _ statement: some StructuredQueriesCore.Statement<V>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) async throws
    where
      Element == V.QueryOutput,
      V.QueryOutput: Sendable
    {
      try await _sharedReader.load(
        .fetch(
          FetchAllStatementValueRequest(statement: statement),
          database: database,
          animation: animation
        )
      )
    }

    @_disfavoredOverload
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
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
      try await _sharedReader.load(
        .fetch(
          FetchAllStatementPackRequest(statement: statement),
          database: database,
          animation: animation
        )
      )
    }
  }
#endif

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
