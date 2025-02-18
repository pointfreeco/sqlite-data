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
  public static func fetchAll<each Value: QueryDecodable>(
    _ statement: some StructuredQueriesCore.Statement<[(repeat each Value)]>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler = .async(onQueue: .main)
  ) -> Self
  where Self == FetchKey<[(repeat each Value)]>.Default {
    fetch(FetchAllStatementRequest(statement: statement), database: database, scheduler: scheduler)
  }

  public static func fetchAll<Value: QueryDecodable>(
    _ statement: some StructuredQueriesCore.Statement<[Value]>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler = .async(onQueue: .main)
  ) -> Self
  where Self == FetchKey<[Value]>.Default {
    fetch(FetchAllStatementRequest(statement: statement), database: database, scheduler: scheduler)
  }

  public static func fetchOne<each Value: QueryDecodable>(
    _ statement: some StructuredQueriesCore.Statement<[(repeat each Value)]>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler = .async(onQueue: .main)
  ) -> Self
  where Self == FetchKey<(repeat each Value)> {
    fetch(FetchOneStatementRequest(statement: statement), database: database, scheduler: scheduler)
  }

  public static func fetchOne<Value: QueryDecodable>(
    _ statement: some StructuredQueriesCore.Statement<[Value]>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler = .async(onQueue: .main)
  ) -> Self
  where Self == FetchKey<Value> {
    fetch(FetchOneStatementRequest(statement: statement), database: database, scheduler: scheduler)
  }

  #if canImport(SwiftUI)
    public static func fetchAll<each Value: QueryDecodable>(
      _ statement: some StructuredQueriesCore.Statement<[(repeat each Value)]>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where Self == FetchKey<[(repeat each Value)]>.Default {
      fetch(
        FetchAllStatementRequest(statement: statement), database: database, animation: animation
      )
    }

    public static func fetchAll<Value: QueryDecodable>(
      _ statement: some StructuredQueriesCore.Statement<[Value]>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where Self == FetchKey<[Value]>.Default {
      fetch(
        FetchAllStatementRequest(statement: statement), database: database, animation: animation
      )
    }

    public static func fetchOne<each Value: QueryDecodable>(
      _ statement: some StructuredQueriesCore.Statement<[(repeat each Value)]>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where Self == FetchKey<(repeat each Value)> {
      fetch(
        FetchOneStatementRequest(statement: statement), database: database, animation: animation
      )
    }

    public static func fetchOne<Value: QueryDecodable>(
      _ statement: some StructuredQueriesCore.Statement<[Value]>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where Self == FetchKey<Value> {
      fetch(
        FetchOneStatementRequest(statement: statement), database: database, animation: animation
      )
    }
  #endif
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
private struct FetchAllStatementRequest<each Value: QueryDecodable>: FetchKeyRequest {
  let statement: any StructuredQueriesCore.Statement<[(repeat each Value)]>

  func fetch(_ db: Database) throws -> [(repeat each Value)] {
    func open(
      _ statement: any StructuredQueriesCore.Statement<[(repeat each Value)]>
    ) throws -> [(repeat each Value)] {
      try statement.fetchAll(db)
    }
    return try open(statement)
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    AnyHashable(lhs.statement) == AnyHashable(rhs.statement)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(statement)
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
private struct FetchOneStatementRequest<each Value: QueryDecodable>: FetchKeyRequest {
  let statement: any StructuredQueriesCore.Statement<[(repeat each Value)]>

  func fetch(_ db: Database) throws -> (repeat each Value) {
    func open(
      _ statement: any StructuredQueriesCore.Statement<[(repeat each Value)]>
    ) throws -> (repeat each Value) {
      guard let result = try statement.fetchOne(db)
      else { throw NotFound() }
      return result
    }
    return try open(statement)
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    AnyHashable(lhs.statement) == AnyHashable(rhs.statement)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(statement)
  }
}
