#if canImport(SwiftUI)
  import Combine
  import Foundation
  import IssueReporting
  import Sharing
  import SwiftUI

  final class FetchBox<Value: Sendable>: Sendable {
    private let storage: LockIsolated<Storage>

    init(sharedReader: SharedReader<Value>) {
      storage = LockIsolated(Storage(sharedReader: sharedReader))
    }

    var sharedReader: SharedReader<Value> {
      get { storage.withLock { $0.sharedReader } }
      set { storage.withLock { $0.sharedReader = newValue } }
    }

    var fetchKeyID: FetchKeyID? {
      get { storage.withLock { $0.fetchKeyID } }
      set { storage.withLock { $0.fetchKeyID = newValue } }
    }

    func reconcile(from fresh: FetchBox, propertyName: String) {
      fresh.storage.withLock { freshSnapshot in
        storage.withLock { snapshot in
          if let freshFetchKeyID = freshSnapshot.fetchKeyID {
            if freshFetchKeyID != snapshot.fetchKeyID {
              update(from: freshSnapshot)
            }
          } else if snapshot.fetchKeyID != nil {
            #if DEBUG
              defer { snapshot.hasReportedIgnoredReinitialization = true }
              guard !snapshot.hasReportedIgnoredReinitialization else { return }
              reportIssue(
                """
                A '\(propertyName)' property was re-initialized without a query, but was previously \
                initialized with one; this re-initialization will be ignored, and the property \
                will continue to observe the existing query
                """
              )
            #endif
          } else if isEqual(freshSnapshot.initialValue, snapshot.initialValue) == false {
            update(from: freshSnapshot)
          }
        }
      }
    }

    private func update(from other: Storage) {
      storage.withLock {
        $0.sharedReader = other.sharedReader
        $0.fetchKeyID = other.fetchKeyID
        $0.initialValue = other.initialValue
      }
    }

    func subscribe(generation: SwiftUI.State<Int>) {
      guard #unavailable(iOS 17, macOS 14, tvOS 17, watchOS 10) else { return }
      _ = generation.wrappedValue
      storage.withLock {
        $0.swiftUICancellable = $0.sharedReader.publisher
          .dropFirst()
          .sink { _ in generation.wrappedValue &+= 1 }
      }
    }

    private struct Storage {
      var sharedReader: SharedReader<Value>
      var fetchKeyID: FetchKeyID?
      var initialValue: Value
      var swiftUICancellable: AnyCancellable?
      #if DEBUG
        var hasReportedIgnoredReinitialization = false
      #endif

      init(sharedReader: SharedReader<Value>) {
        self.sharedReader = sharedReader
        self.initialValue = sharedReader.wrappedValue
      }
    }
  }

  private func isEqual<T>(_ lhs: T, _ rhs: T) -> Bool? {
    func open<U: Equatable>(_ lhs: U) -> Bool {
      lhs == rhs as? U
    }
    guard let lhs = lhs as? any Equatable else { return nil }
    return open(lhs)
  }
#endif
