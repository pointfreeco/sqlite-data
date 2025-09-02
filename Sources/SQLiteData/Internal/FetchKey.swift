import Dependencies
import Dispatch
import Foundation
import GRDB
import Sharing

#if canImport(Combine)
  @preconcurrency import Combine
#endif

extension SharedReaderKey {
  static func fetch<Value>(
    _ request: some FetchKeyRequest<Value>,
    database: (any DatabaseReader)? = nil
  ) -> Self
  where Self == FetchKey<Value> {
    FetchKey(request: request, database: database, scheduler: nil)
  }

  static func fetch<Records: RangeReplaceableCollection>(
    _ request: some FetchKeyRequest<Records>,
    database: (any DatabaseReader)? = nil
  ) -> Self
  where Self == FetchKey<Records>.Default {
    Self[.fetch(request, database: database), default: Value()]
  }
}

extension SharedReaderKey {
  static func fetch<Value>(
    _ request: some FetchKeyRequest<Value>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) -> Self
  where Self == FetchKey<Value> {
    FetchKey(request: request, database: database, scheduler: scheduler)
  }

  static func fetch<Records: RangeReplaceableCollection>(
    _ request: some FetchKeyRequest<Records>,
    database: (any DatabaseReader)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) -> Self
  where Self == FetchKey<Records>.Default {
    Self[.fetch(request, database: database, scheduler: scheduler), default: Value()]
  }
}

struct FetchKey<Value: Sendable>: SharedReaderKey {
  let database: any DatabaseReader
  let request: any FetchKeyRequest<Value>
  let scheduler: (any ValueObservationScheduler & Hashable)?
  #if DEBUG
    let isDefaultDatabase: Bool
  #endif

  public typealias ID = FetchKeyID

  public var id: ID {
    ID(database: database, request: request, scheduler: scheduler)
  }

  init(
    request: some FetchKeyRequest<Value>,
    database: (any DatabaseReader)? = nil,
    scheduler: (any ValueObservationScheduler & Hashable)?
  ) {
    @Dependency(\.defaultDatabase) var defaultDatabase
    self.scheduler = scheduler
    self.database = database ?? defaultDatabase
    self.request = request
    #if DEBUG
      self.isDefaultDatabase = self.database.configuration.label == .defaultDatabaseLabel
    #endif
  }

  public func load(context: LoadContext<Value>, continuation: LoadContinuation<Value>) {
    #if DEBUG
      guard !isDefaultDatabase else {
        continuation.resumeReturningInitialValue()
        return
      }
    #endif
    guard case .userInitiated = context else {
      continuation.resumeReturningInitialValue()
      return
    }
    let scheduler: any ValueObservationScheduler = scheduler ?? ImmediateScheduler()
    database.asyncRead { dbResult in
      let result = dbResult.flatMap { db in
        Result {
          try request.fetch(db)
        }
      }
      scheduler.schedule {
        switch result {
        case let .success(value):
          continuation.resume(returning: value)
        case let .failure(error):
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func subscribe(
    context: LoadContext<Value>, subscriber: SharedSubscriber<Value>
  ) -> SharedSubscription {
    #if DEBUG
      guard !isDefaultDatabase else {
        return SharedSubscription {}
      }
    #endif
    let observation = ValueObservation.tracking { db in
      Result { try request.fetch(db) }
    }

    let scheduler: any ValueObservationScheduler = scheduler ?? ImmediateScheduler()
    #if canImport(Combine)
      let dropFirst =
        switch context {
        case .initialValue: false
        case .userInitiated: true
        }
      let cancellable = observation.publisher(in: database, scheduling: scheduler)
        .dropFirst(dropFirst ? 1 : 0)
        .sink { completion in
          switch completion {
          case let .failure(error):
            subscriber.yield(throwing: error)
          case .finished:
            break
          }
        } receiveValue: { newValue in
          switch newValue {
          case let .success(value):
            subscriber.yield(value)
          case let .failure(error):
            subscriber.yield(throwing: error)
          }
        }
      return SharedSubscription {
        cancellable.cancel()
      }
    #else
      let cancellable = observation.start(in: database, scheduling: scheduler) { error in
        subscriber.yield(throwing: error)
      } onChange: { newValue in
        switch newValue {
        case let .success(value):
          subscriber.yield(value)
        case let .failure(error):
          subscriber.yield(throwing: error)
        }
      }
      return SharedSubscription {
        cancellable.cancel()
      }
    #endif
  }
}

struct FetchKeyID: Hashable {
  fileprivate let databaseID: ObjectIdentifier
  fileprivate let request: AnyHashableSendable
  fileprivate let requestTypeID: ObjectIdentifier
  fileprivate let scheduler: AnyHashableSendable?

  fileprivate init(
    database: any DatabaseReader,
    request: some FetchKeyRequest,
    scheduler: (any ValueObservationScheduler & Hashable)?
  ) {
    self.databaseID = ObjectIdentifier(database)
    self.request = AnyHashableSendable(request)
    self.requestTypeID = ObjectIdentifier(type(of: request))
    self.scheduler = scheduler.map { AnyHashableSendable($0) }
  }
}

public struct NotFound: Error {
  public init() {}
}

private struct ImmediateScheduler: ValueObservationScheduler, Hashable {
  func immediateInitialValue() -> Bool { true }
  func schedule(_ action: @escaping @Sendable () -> Void) {
    action()
  }
}
