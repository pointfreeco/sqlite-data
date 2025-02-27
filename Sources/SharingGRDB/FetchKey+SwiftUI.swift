#if canImport(SwiftUI)
  import GRDB
  import Sharing
  import SwiftUI

  extension SharedReaderKey {
    /// A key that can query for data in a SQLite database.
    ///
    /// A version of ``Sharing/SharedReaderKey/fetch(_:database:)-3qcpd`` that can be configured
    /// with a SwiftUI animation. See ``Sharing/SharedReaderKey/fetch(_:database:)-3qcpd`` for more
    /// info on how to use this API.
    ///
    /// - Parameters:
    ///   - request: A request describing the data to fetch.
    ///   - database: The database to read from. A value of `nil` will use the default database.
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
    public static func fetch<Value>(
      _ request: some FetchKeyRequest<Value>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where Self == FetchKey<Value> {
      .fetch(request, database: database, scheduler: .animation(animation))
    }

    /// A key that can query for a collection of data in a SQLite database.
    ///
    /// A version of ``Sharing/SharedReaderKey/fetch(_:database:)-3qcpd`` that can be configured
    /// with a SwiftUI animation. See ``Sharing/SharedReaderKey/fetch(_:database:)-3qcpd`` for more
    /// info on how to use this API.
    ///
    /// - Parameters:
    ///   - request: A request describing the data to fetch.
    ///   - database: The database to read from. A value of `nil` will use the default database.
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
    public static func fetch<Records: RangeReplaceableCollection>(
      _ request: some FetchKeyRequest<Records>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where Self == FetchKey<Records>.Default {
      .fetch(request, database: database, scheduler: .animation(animation))
    }

    /// A key that can query for a collection of data in a SQLite database.
    ///
    /// A version of ``Sharing/SharedReaderKey/fetchAll(sql:arguments:database:)`` that can be
    /// configured with a SwiftUI animation. See
    /// ``Sharing/SharedReaderKey/fetchAll(sql:arguments:database:)`` for more information on how to
    /// use this API.
    ///
    /// - Parameters:
    ///   - sql: A raw SQL string describing the data to fetch.
    ///   - arguments: Arguments to bind to the SQL statement.
    ///   - database: The database to read from. A value of `nil` will use the default database.
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
    public static func fetchAll<Record: FetchableRecord>(
      sql: String,
      arguments: StatementArguments = StatementArguments(),
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where Self == FetchKey<[Record]>.Default {
      .fetchAll(
        sql: sql,
        arguments: arguments,
        database: database,
        scheduler: .animation(animation)
      )
    }

    /// A key that can query for a value in a SQLite database.
    ///
    /// A version of ``Sharing/SharedReaderKey/fetchOne(sql:arguments:database:)`` that can be
    /// configured with a SwiftUI animation. See
    /// ``Sharing/SharedReaderKey/fetchAll(sql:arguments:database:)`` for more information on how to
    /// use this API.
    ///
    /// - Parameters:
    ///   - sql: A raw SQL string describing the data to fetch.
    ///   - arguments: Arguments to bind to the SQL statement.
    ///   - database: The database to read from. A value of `nil` will use the default database.
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
    public static func fetchOne<Value: DatabaseValueConvertible>(
      sql: String,
      arguments: StatementArguments = StatementArguments(),
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) -> Self
    where Self == FetchKey<Value> {
      .fetchOne(
        sql: sql,
        arguments: arguments,
        database: database,
        scheduler: .animation(animation)
      )
    }
  }

  private struct AnimatedScheduler: ValueObservationScheduler, Hashable {
    let animation: Animation
    func immediateInitialValue() -> Bool { true }
    func schedule(_ action: @escaping @Sendable () -> Void) {
      DispatchQueue.main.async {
        withAnimation(animation) {
          action()
        }
      }
    }
  }

  extension ValueObservationScheduler where Self == AnimatedScheduler {
    fileprivate static func animation(_ animation: Animation) -> Self {
      AnimatedScheduler(animation: animation)
    }
  }
#endif
