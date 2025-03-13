import Dependencies
import Dispatch
import GRDB
import Sharing
import StructuredQueriesCore
import StructuredQueriesGRDBCore

#if canImport(SwiftUI)
  import SwiftUI
#endif

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SharedReaderKey {
  public static func fetchAll<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler = .async(onQueue: .main)
  ) -> Self
  where
    S.QueryValue == (),
    S.Joins == (repeat each J),
    Self == FetchKey<[(S.From.QueryOutput, repeat (each J).QueryOutput)]>.Default
  {
    fetch(
      FetchAllStatementRequest(statement: statement.selectAll()),
      database: database,
      scheduler: scheduler
    )
  }

  public static func fetchAll<S: SelectStatement, V1: QueryRepresentable, each V2: QueryRepresentable>(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler = .async(onQueue: .main)
  ) -> Self
  where
    S.QueryValue == (V1, repeat each V2),
    Self == FetchKey<[(V1.QueryOutput, repeat (each V2).QueryOutput)]>.Default
  {
    fetch(FetchAllStatementRequest(statement: statement), database: database, scheduler: scheduler)
  }

  public static func fetchAll<S: SelectStatement>(
    _ statement: S,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler = .async(onQueue: .main)
  ) -> Self
  where S.QueryValue: QueryRepresentable, Self == FetchKey<[S.QueryValue.QueryOutput]>.Default {
    fetch(FetchAllStatementRequest(statement: statement), database: database, scheduler: scheduler)
  }

  public static func fetchOne<each Value: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<(repeat each Value)>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler = .async(onQueue: .main)
  ) -> Self
  where Self == FetchKey<(repeat (each Value).QueryOutput)> {
    fetch(FetchOneStatementRequest(statement: statement), database: database, scheduler: scheduler)
  }

  public static func fetchOne<Value: QueryRepresentable>(
    _ statement: some StructuredQueriesCore.Statement<Value>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler = .async(onQueue: .main)
  ) -> Self
  where Self == FetchKey<Value.QueryOutput> {
    fetch(FetchOneStatementRequest(statement: statement), database: database, scheduler: scheduler)
  }

  #if canImport(SwiftUI)
    public static func fetchAll<each Value: QueryRepresentable>(
      _ statement: some StructuredQueriesCore.Statement<(repeat each Value)>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where Self == FetchKey<[(repeat (each Value).QueryOutput)]>.Default {
      fetch(
        FetchAllStatementRequest(statement: statement), database: database, animation: animation
      )
    }

    public static func fetchAll<Value: QueryRepresentable>(
      _ statement: some StructuredQueriesCore.Statement<Value>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where Self == FetchKey<[Value.QueryOutput]>.Default {
      fetch(
        FetchAllStatementRequest(statement: statement), database: database, animation: animation
      )
    }

    public static func fetchOne<each Value: QueryRepresentable>(
      _ statement: some StructuredQueriesCore.Statement<(repeat each Value)>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where Self == FetchKey<(repeat (each Value).QueryOutput)> {
      fetch(
        FetchOneStatementRequest(statement: statement), database: database, animation: animation
      )
    }

    public static func fetchOne<Value: QueryRepresentable>(
      _ statement: some StructuredQueriesCore.Statement<Value>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where Self == FetchKey<Value.QueryOutput> {
      fetch(
        FetchOneStatementRequest(statement: statement), database: database, animation: animation
      )
    }
  #endif
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
private struct FetchAllStatementRequest<each Value: QueryRepresentable>: FetchKeyRequest {
  let statement: any StructuredQueriesCore.Statement<(repeat each Value)>

  func fetch(_ db: Database) throws -> [(repeat (each Value).QueryOutput)] {
    try statement.fetchAll(db)
  }

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

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
private struct FetchOneStatementRequest<each Value: QueryRepresentable>: FetchKeyRequest {
  let statement: any StructuredQueriesCore.Statement<(repeat each Value)>

  func fetch(_ db: Database) throws -> (repeat (each Value).QueryOutput) {
    guard let result = try statement.fetchOne(db)
    else { throw NotFound() }
    return result
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    // NB: A Swift 6.1 regression prevents this from compiling:
    //     https://github.com/swiftlang/swift/issues/79623
    // AnyHashable(lhs.statement) == AnyHashable(rhs.statement)
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

// TODO: Define in Structured Queries?
fileprivate extension SelectStatement where QueryValue == () {
  func selectAll<
    each J: StructuredQueriesCore.Table
  >() -> Select<(From, repeat each J), From, (repeat each J)>
  where Joins == (repeat each J) {
    unsafeBitCast(
      self,
      to: Select<(From, repeat each J), From, (repeat each J)>.self
    )
  }
}
