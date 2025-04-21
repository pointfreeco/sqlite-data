#if canImport(Combine)
import Combine
#endif
#if canImport(SwiftUI)
  import SwiftUI
#endif

@propertyWrapper
public struct FetchOne<Value>: Sendable {
  public var _sharedReader: SharedReader<Value>

  public var wrappedValue: Value {
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
    public var publisher: some Publisher<Value, Never> {
      _sharedReader.publisher
    }
  #endif

  public init(wrappedValue: sending Value) {
    _sharedReader = SharedReader(value: wrappedValue)
  }

  public init<S: SelectStatement>(
    wrappedValue: S.From.QueryOutput,
    _ statement: S,
    database: (any DatabaseReader)? = nil
  )
  where
    Value == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    _sharedReader = SharedReader(
      wrappedValue: wrappedValue, .fetchOne(statement, database: database)
    )
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public init<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    wrappedValue: (S.From.QueryOutput, repeat (each J).QueryOutput),
    _ statement: S,
    database: (any DatabaseReader)? = nil
  )
  where
    Value == (S.From.QueryOutput, repeat (each J).QueryOutput),
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == (repeat each J),
    repeat (each J).QueryOutput: Sendable
  {
    _sharedReader = SharedReader(
      wrappedValue: wrappedValue, .fetchOne(statement, database: database)
    )
  }

  public init<V: QueryRepresentable>(
    wrappedValue: V.QueryOutput,
    _ statement: some StructuredQueriesCore.Statement<V>,
    database: (any DatabaseReader)? = nil
  )
  where
    Value == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    _sharedReader = SharedReader(
      wrappedValue: wrappedValue, .fetchOne(statement, database: database)
    )
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public init<V1: QueryRepresentable, each V2: QueryRepresentable>(
    wrappedValue: (V1.QueryOutput, repeat (each V2).QueryOutput),
    _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
    database: (any DatabaseReader)? = nil
  )
  where
    Value == (V1.QueryOutput, repeat (each V2).QueryOutput),
    V1.QueryOutput: Sendable,
    repeat (each V2).QueryOutput: Sendable
  {
    _sharedReader = SharedReader(
      wrappedValue: wrappedValue, .fetchOne(statement, database: database)
    )
  }

  public func load<S: SelectStatement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil
  ) async throws
  where
    Value == [S.From.QueryOutput],
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    try await _sharedReader.load(.fetchAll(statement, database: database))
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public func load<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    _ statement: S,
    database: (any DatabaseReader)? = nil
  ) async throws
  where
    Value == [(S.From.QueryOutput, repeat (each J).QueryOutput)],
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == (repeat each J),
    repeat (each J).QueryOutput: Sendable
  {
    try await _sharedReader.load(.fetchAll(statement, database: database))
  }

  public func load<V: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<V>,
    database: (any DatabaseReader)? = nil
  ) async throws
  where
    Value == [V.QueryOutput],
    V.QueryOutput: Sendable
  {
    try await _sharedReader.load(.fetchAll(statement, database: database))
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public func load<V1: QueryRepresentable, each V2: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
    database: (any DatabaseReader)? = nil
  ) async throws
  where
    Value == [(V1.QueryOutput, repeat (each V2).QueryOutput)],
    V1.QueryOutput: Sendable,
    repeat (each V2).QueryOutput: Sendable
  {
    try await _sharedReader.load(.fetchAll(statement, database: database))
  }
}

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
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    _sharedReader = SharedReader(
      wrappedValue: wrappedValue, .fetchOne(statement, database: database, scheduler: scheduler)
    )
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public init<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    wrappedValue: (S.From.QueryOutput, repeat (each J).QueryOutput),
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Value == (S.From.QueryOutput, repeat (each J).QueryOutput),
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == (repeat each J),
    repeat (each J).QueryOutput: Sendable
  {
    _sharedReader = SharedReader(
      wrappedValue: wrappedValue, .fetchOne(statement, database: database, scheduler: scheduler)
    )
  }

  public init<V: QueryRepresentable>(
    wrappedValue: V.QueryOutput,
    _ statement: some StructuredQueriesCore.Statement<V>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Value == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    _sharedReader = SharedReader(
      wrappedValue: wrappedValue, .fetchOne(statement, database: database, scheduler: scheduler)
    )
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public init<V1: QueryRepresentable, each V2: QueryRepresentable>(
    wrappedValue: (V1.QueryOutput, repeat (each V2).QueryOutput),
    _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  )
  where
    Value == (V1.QueryOutput, repeat (each V2).QueryOutput),
    V1.QueryOutput: Sendable,
    repeat (each V2).QueryOutput: Sendable
  {
    _sharedReader = SharedReader(
      wrappedValue: wrappedValue, .fetchOne(statement, database: database, scheduler: scheduler)
    )
  }

  public func load<S: SelectStatement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws
  where
    Value == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    try await _sharedReader.load(.fetchOne(statement, database: database, scheduler: scheduler))
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public func load<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws
  where
    Value == (S.From.QueryOutput, repeat (each J).QueryOutput),
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == (repeat each J),
    repeat (each J).QueryOutput: Sendable
  {
    try await _sharedReader.load(.fetchOne(statement, database: database, scheduler: scheduler))
  }

  public func load<V: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<V>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws
  where
    Value == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    try await _sharedReader.load(.fetchOne(statement, database: database, scheduler: scheduler))
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public func load<V1: QueryRepresentable, each V2: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws
  where
    Value == (V1.QueryOutput, repeat (each V2).QueryOutput),
    V1.QueryOutput: Sendable,
    repeat (each V2).QueryOutput: Sendable
  {
    try await _sharedReader.load(.fetchOne(statement, database: database, scheduler: scheduler))
  }
}

#if canImport(SwiftUI)
extension FetchOne {
  public init<S: SelectStatement>(
    wrappedValue: S.From.QueryOutput,
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    animation: Animation
  )
  where
    Value == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    _sharedReader = SharedReader(
      wrappedValue: wrappedValue, .fetchOne(statement, database: database, animation: animation)
    )
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public init<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    wrappedValue: (S.From.QueryOutput, repeat (each J).QueryOutput),
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    animation: Animation
  )
  where
    Value == (S.From.QueryOutput, repeat (each J).QueryOutput),
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == (repeat each J),
    repeat (each J).QueryOutput: Sendable
  {
    _sharedReader = SharedReader(
      wrappedValue: wrappedValue, .fetchOne(statement, database: database, animation: animation)
    )
  }

  public init<V: QueryRepresentable>(
    wrappedValue: V.QueryOutput,
    _ statement: some StructuredQueriesCore.Statement<V>,
    database: (any DatabaseReader)? = nil,
    animation: Animation
  )
  where
    Value == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    _sharedReader = SharedReader(
      wrappedValue: wrappedValue, .fetchOne(statement, database: database, animation: animation)
    )
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public init<V1: QueryRepresentable, each V2: QueryRepresentable>(
    wrappedValue: (V1.QueryOutput, repeat (each V2).QueryOutput),
    _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
    database: (any DatabaseReader)? = nil,
    animation: Animation
  )
  where
    Value == (V1.QueryOutput, repeat (each V2).QueryOutput),
    V1.QueryOutput: Sendable,
    repeat (each V2).QueryOutput: Sendable
  {
    _sharedReader = SharedReader(
      wrappedValue: wrappedValue, .fetchOne(statement, database: database, animation: animation)
    )
  }

  public func load<S: SelectStatement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    animation: Animation
  ) async throws
  where
    Value == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == ()
  {
    try await _sharedReader.load(.fetchOne(statement, database: database, animation: animation))
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public func load<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    animation: Animation
  ) async throws
  where
    Value == (S.From.QueryOutput, repeat (each J).QueryOutput),
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.Joins == (repeat each J),
    repeat (each J).QueryOutput: Sendable
  {
    try await _sharedReader.load(.fetchOne(statement, database: database, animation: animation))
  }

  public func load<V: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<V>,
    database: (any DatabaseReader)? = nil,
    animation: Animation
  ) async throws
  where
    Value == V.QueryOutput,
    V.QueryOutput: Sendable
  {
    try await _sharedReader.load(.fetchOne(statement, database: database, animation: animation))
  }

  @_disfavoredOverload
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public func load<V1: QueryRepresentable, each V2: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<(V1, repeat each V2)>,
    database: (any DatabaseReader)? = nil,
    animation: Animation
  ) async throws
  where
    Value ==(V1.QueryOutput, repeat (each V2).QueryOutput),
    V1.QueryOutput: Sendable,
    repeat (each V2).QueryOutput: Sendable
  {
    try await _sharedReader.load(.fetchOne(statement, database: database, animation: animation))
  }
}
#endif
