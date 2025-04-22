#if canImport(Combine)
  import Combine
#endif
#if canImport(SwiftUI)
  import SwiftUI
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
@propertyWrapper
public struct Fetch<Value: Sendable>: Sendable {
  private var sharedReader: SharedReader<Value>

  public var wrappedValue: Value {
    sharedReader.wrappedValue
  }

  public var projectedValue: Self {
    self
  }

  public var loadError: (any Error)? {
    sharedReader.loadError
  }

  public var isLoading: Bool {
    sharedReader.isLoading
  }

  #if canImport(Combine)
    public var publisher: some Publisher<Value, Never> {
      sharedReader.publisher
    }
  #endif

  public init(wrappedValue: sending Value) {
    sharedReader = SharedReader(value: wrappedValue)
  }

  public init(
    wrappedValue: Value,
    _ request: some FetchKeyRequest<Value>,
    database: (any DatabaseReader)? = nil
  ) {
    sharedReader = SharedReader(wrappedValue: wrappedValue, .fetch(request, database: database))
  }

  public init(
    _ request: some FetchKeyRequest<Value>,
    database: (any DatabaseReader)? = nil
  ) where Value: RangeReplaceableCollection {
    sharedReader = SharedReader(.fetch(request, database: database))
  }
}

extension Fetch {
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
  }

  public init(
    _ request: some FetchKeyRequest<Value>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) where Value: RangeReplaceableCollection {
    sharedReader = SharedReader(.fetch(request, database: database, scheduler: scheduler))
  }
}

#if canImport(SwiftUI)
  extension Fetch {
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
    }

    public init(
      _ request: some FetchKeyRequest<Value>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) where Value: RangeReplaceableCollection {
      sharedReader = SharedReader(.fetch(request, database: database, animation: animation))
    }
  }
#endif
