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
    database: (any DatabaseWriter)? = nil
  ) -> Self
  where Self == FetchKey<Value> {
    FetchKey(request: request, database: database, scheduler: nil)
  }

  static func fetch<Records: RangeReplaceableCollection>(
    _ request: some FetchKeyRequest<Records>,
    database: (any DatabaseWriter)? = nil
  ) -> Self
  where Self == FetchKey<Records>.Default {
    Self[.fetch(request, database: database), default: Value()]
  }
}

extension SharedReaderKey {
  static func fetch<Value>(
    _ request: some FetchKeyRequest<Value>,
    database: (any DatabaseWriter)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) -> Self
  where Self == FetchKey<Value> {
    FetchKey(request: request, database: database, scheduler: scheduler)
  }

  static func fetch<Records: RangeReplaceableCollection>(
    _ request: some FetchKeyRequest<Records>,
    database: (any DatabaseWriter)? = nil,
    scheduler: some ValueObservationScheduler & Hashable
  ) -> Self
  where Self == FetchKey<Records>.Default {
    Self[.fetch(request, database: database, scheduler: scheduler), default: Value()]
  }
}

/*
 @FetchAll var as
 @FetchAll var bs
 @FetchAll var cs

 write {
 insert a
 insert b
 }
 */

final class Observer: TransactionObserver, Sendable {
  let didCommit: @Sendable () -> Void
  init(didCommit: @Sendable @escaping () -> Void) {
    self.didCommit = didCommit
  }
  func observes(eventsOfKind eventKind: GRDB.DatabaseEventKind) -> Bool {
    true
  }
  func databaseDidCommit(_ db: GRDB.Database) {
    //didCommit()
  }
  func databaseDidRollback(_ db: GRDB.Database) {}
  func databaseDidChange(with event: GRDB.DatabaseEvent) {}
}

struct FetchKey<Value: Sendable>: SharedReaderKey {
  let database: any DatabaseWriter
  let request: any FetchKeyRequest<Value>
  let scheduler: (any ValueObservationScheduler & Hashable)?

  #if DEBUG
    let isDefaultDatabase: Bool
  #endif
  @Dependency(\.self) var dependencies

  public typealias ID = FetchKeyID

  public var id: ID {
    ID(database: database, request: request, scheduler: scheduler)
  }

  init(
    request: some FetchKeyRequest<Value>,
    database: (any DatabaseWriter)? = nil,
    scheduler: (any ValueObservationScheduler & Hashable)?
  ) {
    @Dependency(\.defaultDatabase) var defaultDatabase
    self.scheduler = scheduler
    if database == nil {
      // self.isDefaultDatabase = true
    }
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
    withEscapedDependencies { dependencies in
      database.asyncRead { dbResult in
        let result = dbResult.flatMap { db in
          Result {
            try dependencies.yield {
              try request.fetch(db)
            }
          }
        }
        scheduler.schedule {
          switch result {
          case .success(let value):
            continuation.resume(returning: value)
          case .failure(let error):
            continuation.resume(throwing: error)
          }
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

    /*
     write {
     }
     if rows.isEmpty {
       store.send(…)
     }
     */


    @Dependency(\.context) var dependencyContext
    guard dependencyContext != .test
    else {
      let observer = Observer { [weak database] in
        guard let database else { return }
        subscriber.yield(
          with: Result {
            try database.read { db in
              try request.fetch(db)
            }
          }
        )
      }
      database.add(transactionObserver: observer)
      return SharedSubscription {
        _ = observer
      }
    }

    let observation = withEscapedDependencies { dependencies in
      ValueObservation.tracking { db in
        dependencies.yield {
          Result { try request.fetch(db) }
        }
      }
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
          case .failure(let error):
            subscriber.yield(throwing: error)
          case .finished:
            break
          }
        } receiveValue: { newValue in
          switch newValue {
          case .success(let value):
            subscriber.yield(value)
          case .failure(let error):
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
        case .success(let value):
          subscriber.yield(value)
        case .failure(let error):
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
