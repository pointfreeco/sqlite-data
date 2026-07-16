public import GRDB
public import Sharing
import StructuredQueriesCore

#if canImport(Combine)
  public import Combine
#endif
#if canImport(SwiftUI)
  public import SwiftUI
#endif

/// A property that can query for data in a SQLite database.
///
/// It takes a ``FetchKeyRequest`` that describes how to fetch data from a database:
///
/// ```swift
/// @Fetch(Items()) var items = Items.Value()
/// ```
///
/// See <doc:Fetching> for more information.
@dynamicMemberLookup
@propertyWrapper
public struct Fetch<Value: Sendable>: Sendable {
  #if canImport(SwiftUI)
    /// The underlying shared reader powering the property wrapper.
    ///
    /// Shared readers come from the [Sharing](https://github.com/pointfreeco/swift-sharing)
    /// package, a general solution to observing and persisting changes to external data sources.
    public private(set) var sharedReader: SharedReader<Value> {
      @storageRestrictions(initializes: box, state)
      init(initialValue) {
        let box = FetchBox(sharedReader: initialValue)
        self.box = box
        state = SwiftUI.State(wrappedValue: box)
      }
      get { state.wrappedValue.sharedReader }
      nonmutating set { state.wrappedValue.sharedReader = newValue }
    }

    private let box: FetchBox<Value>
    private let state: SwiftUI.State<FetchBox<Value>>
    private let generation = SwiftUI.State(wrappedValue: 0)
  #else
    /// The underlying shared reader powering the property wrapper.
    ///
    /// Shared readers come from the [Sharing](https://github.com/pointfreeco/swift-sharing)
    /// package, a general solution to observing and persisting changes to external data sources.
    public private(set) var sharedReader: SharedReader<Value>
  #endif

  /// Data associated with the underlying query.
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

  /// Initializes this property with an initial value.
  ///
  /// - Parameter wrappedValue: A default value to associate with this property.
  @_disfavoredOverload
  public init(wrappedValue: sending Value) {
    sharedReader = SharedReader(value: wrappedValue)
  }

  /// Initializes this property with a request associated with the wrapped value.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to associate with this property.
  ///   - request: A request describing the data to fetch.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  public init(
    wrappedValue: Value,
    _ request: some FetchKeyRequest<Value>,
    database: (any DatabaseReader)? = nil
  ) {
    sharedReader = SharedReader(wrappedValue: wrappedValue, .fetch(request, database: database))
    setFetchKeyID(for: request, database: database, scheduler: nil)
  }

  /// Replaces the wrapped value with data from the given request.
  ///
  /// - Parameters:
  ///   - request: A request describing the data to fetch.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  /// - Returns: A subscription associated with the observation.
  @discardableResult
  public func load(
    _ request: some FetchKeyRequest<Value>,
    database: (any DatabaseReader)? = nil
  ) async throws -> FetchSubscription {
    try await sharedReader.load(.fetch(request, database: database))
    return FetchSubscription(sharedReader: sharedReader)
  }

  #if !canImport(SwiftUI)
    @_transparent
  #endif
  private func setFetchKeyID<V: Sendable>(
    for request: some FetchKeyRequest<V>,
    database: (any DatabaseReader)?,
    scheduler: (any ValueObservationScheduler & Hashable)?
  ) {
    #if canImport(SwiftUI)
      box.fetchKeyID = FetchKey(request: request, database: database, scheduler: scheduler).id
    #endif
  }
}

extension Fetch {
  /// Initializes this property with a request associated with the wrapped value.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to associate with this property.
  ///   - request: A request describing the data to fetch.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  public init(
    wrappedValue: Value,
    _ request: some FetchKeyRequest<Value>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) {
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetch(request, database: database, scheduler: scheduler)
    )
    setFetchKeyID(for: request, database: database, scheduler: scheduler)
  }

  /// Replaces the wrapped value with data from the given request.
  ///
  /// - Parameters:
  ///   - request: A request describing the data to fetch.
  ///   - database: The database to read from. A value of `nil` will use the default database
  ///     (`@Dependency(\.defaultDatabase)`).
  ///   - scheduler: The scheduler to observe from. By default, database observation is performed
  ///     asynchronously on the main queue.
  /// - Returns: A subscription associated with the observation.
  @discardableResult
  public func load(
    _ request: some FetchKeyRequest<Value>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) async throws -> FetchSubscription {
    try await sharedReader.load(.fetch(request, database: database, scheduler: scheduler))
    return FetchSubscription(sharedReader: sharedReader)
  }
}

extension Fetch: CustomReflectable {
  public var customMirror: Mirror {
    Mirror(reflecting: wrappedValue)
  }
}

extension Fetch: Equatable where Value: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sharedReader == rhs.sharedReader
  }
}

#if canImport(SwiftUI)
  extension Fetch: DynamicProperty {
    public func update() {
      let persisted = state.wrappedValue
      if persisted !== box {
        persisted.update(from: box)
      }
      persisted.subscribe(generation: generation)
    }

    /// Initializes this property with a request associated with the wrapped value.
    ///
    /// - Parameters:
    ///   - wrappedValue: A default value to associate with this property.
    ///   - request: A request describing the data to fetch.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public init(
      wrappedValue: Value,
      _ request: some FetchKeyRequest<Value>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) {
      sharedReader = SharedReader(
        wrappedValue: wrappedValue,
        .fetch(request, database: database, animation: animation)
      )
      setFetchKeyID(for: request, database: database, scheduler: .animation(animation))
    }

    /// Replaces the wrapped value with data from the given request.
    ///
    /// - Parameters:
    ///   - request: A request describing the data to fetch.
    ///   - database: The database to read from. A value of `nil` will use the default database
    ///     (`@Dependency(\.defaultDatabase)`).
    ///   - animation: The animation to use for user interface changes that result from changes to
    ///     the fetched results.
    /// - Returns: A subscription associated with the observation.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @discardableResult
    public func load(
      _ request: some FetchKeyRequest<Value>,
      database: (any DatabaseReader)? = nil,
      animation: Animation?
    ) async throws -> FetchSubscription {
      try await sharedReader.load(.fetch(request, database: database, animation: animation))
      return FetchSubscription(sharedReader: sharedReader)
    }
  }
#endif
