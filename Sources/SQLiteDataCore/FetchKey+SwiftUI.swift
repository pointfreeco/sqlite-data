#if canImport(SwiftUI)
  import GRDB
  import Sharing
  import SwiftUI

  extension SharedReaderKey {
    /// A key that can query for data in a SQLite database.
    ///
    /// A version of `fetch` that can be configured with a SwiftUI animation.
    ///
    /// - Parameters:
    ///   - request: A request describing the data to fetch.
    ///   - database: The database to read from. A value of `nil` will use the default database.
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
    @available(iOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
    @available(macOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
    @available(tvOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
    @available(watchOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
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
    /// A version of `fetch` that can be configured with a SwiftUI animation.
    ///
    /// - Parameters:
    ///   - request: A request describing the data to fetch.
    ///   - database: The database to read from. A value of `nil` will use the default database.
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
    @available(iOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
    @available(macOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
    @available(tvOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
    @available(watchOS, deprecated: 9999, message: "Use the '@Fetch' property wrapper, instead")
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
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
    /// A version of `fetchAll` that can be configured with a SwiftUI animation.
    ///
    /// - Parameters:
    ///   - sql: A raw SQL string describing the data to fetch.
    ///   - arguments: Arguments to bind to the SQL statement.
    ///   - database: The database to read from. A value of `nil` will use the default database.
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
    @available(iOS, deprecated: 9999, message: "Use '@FetchAll' and '#sql', instead")
    @available(macOS, deprecated: 9999, message: "Use '@FetchAll' and '#sql', instead")
    @available(tvOS, deprecated: 9999, message: "Use '@FetchAll' and '#sql', instead")
    @available(watchOS, deprecated: 9999, message: "Use '@FetchAll' and '#sql', instead")
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
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
    /// A version of `fetchOne` that can be configured with a SwiftUI animation.
    ///
    /// - Parameters:
    ///   - sql: A raw SQL string describing the data to fetch.
    ///   - arguments: Arguments to bind to the SQL statement.
    ///   - database: The database to read from. A value of `nil` will use the default database.
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A key that can be passed to the `@SharedReader` property wrapper.
    @available(iOS, deprecated: 9999, message: "Use '@FetchOne' and '#sql', instead")
    @available(macOS, deprecated: 9999, message: "Use '@FetchOne' and '#sql', instead")
    @available(tvOS, deprecated: 9999, message: "Use '@FetchOne' and '#sql', instead")
    @available(watchOS, deprecated: 9999, message: "Use '@FetchOne' and '#sql', instead")
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
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

package struct AnimatedScheduler: ValueObservationScheduler, Equatable {
    let animation: Animation
    package func immediateInitialValue() -> Bool { true }
    package func schedule(_ action: @escaping @Sendable () -> Void) {
      DispatchQueue.main.async {
        withAnimation(animation) {
          action()
        }
      }
    }
  }

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension AnimatedScheduler: Hashable {}

  extension ValueObservationScheduler where Self == AnimatedScheduler {
    package static func animation(_ animation: Animation) -> Self {
      AnimatedScheduler(animation: animation)
    }
  }
#endif
