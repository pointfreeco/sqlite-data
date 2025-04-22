#if canImport(Combine)
  import Combine
#endif
#if canImport(SwiftUI)
  import SwiftUI
#endif

@propertyWrapper
public struct Fetch<Value: Sendable>: Sendable {
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

  public init(
    wrappedValue: Value,
    _ request: some FetchKeyRequest<Value>,
    database: (any DatabaseReader)? = nil
  ) {
    _sharedReader = SharedReader(wrappedValue: wrappedValue, .fetch(request, database: database))
  }

  public init(
    _ request: some FetchKeyRequest<Value>,
    database: (any DatabaseReader)? = nil
  ) where Value: RangeReplaceableCollection {
    _sharedReader = SharedReader(.fetch(request, database: database))
  }
}

extension Fetch {
  public init(
    wrappedValue: Value,
    _ request: some FetchKeyRequest<Value>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) {
    _sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetch(request, database: database, scheduler: scheduler)
    )
  }

  public init(
    _ request: some FetchKeyRequest<Value>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) where Value: RangeReplaceableCollection {
    _sharedReader = SharedReader(.fetch(request, database: database, scheduler: scheduler))
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
      _sharedReader = SharedReader(
        wrappedValue: wrappedValue,
        .fetch(request, database: database, animation: animation)
      )
    }

    public init(
      _ request: some FetchKeyRequest<Value>,
      database: (any DatabaseReader)? = nil,
      animation: Animation
    ) where Value: RangeReplaceableCollection {
      _sharedReader = SharedReader(.fetch(request, database: database, animation: animation))
    }
  }
#endif
