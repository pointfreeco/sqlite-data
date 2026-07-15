#if canImport(SwiftUI)
  import Combine
  import Foundation
  import IssueReporting
  import Sharing
  import SwiftUI

  final class FetchBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Storage

    init(sharedReader: SharedReader<Value>) {
      storage = Storage(sharedReader: sharedReader)
    }

    var sharedReader: SharedReader<Value> {
      get { lock.withLock { storage.sharedReader } }
      set { lock.withLock { storage.sharedReader = newValue } }
    }

    var fetchKeyID: FetchKeyID? {
      get { lock.withLock { storage.fetchKeyID } }
      set { lock.withLock { storage.fetchKeyID = newValue } }
    }

    func reconcile(from fresh: FetchBox, propertyName: String) {
      let freshSnapshot = fresh.lock.withLock { fresh.storage }
      if let freshFetchKeyID = freshSnapshot.fetchKeyID {
        if freshFetchKeyID != fetchKeyID {
          update(from: freshSnapshot)
        }
      } else if fetchKeyID != nil {
        #if DEBUG
          let hasReported = lock.withLock {
            defer { storage.hasReportedIgnoredReinitialization = true }
            return storage.hasReportedIgnoredReinitialization
          }
          guard !hasReported else { return }
          reportIssue(
            """
            A '\(propertyName)' property was re-initialized without a query, but was previously \
            initialized with one; this re-initialization will be ignored, and the property \
            will continue to observe the existing query
            """
          )
        #endif
      }
    }

    private func update(from other: Storage) {
      lock.withLock {
        storage.sharedReader = other.sharedReader
        storage.fetchKeyID = other.fetchKeyID
      }
    }

    func subscribe(generation: SwiftUI.State<Int>) {
      guard #unavailable(iOS 17, macOS 14, tvOS 17, watchOS 10) else { return }
      _ = generation.wrappedValue
      let cancellable = sharedReader.publisher
        .dropFirst()
        .sink { _ in generation.wrappedValue &+= 1 }
      lock.withLock { storage.swiftUICancellable = cancellable }
    }

    private struct Storage {
      var sharedReader: SharedReader<Value>
      var fetchKeyID: FetchKeyID?
      var swiftUICancellable: AnyCancellable?
      #if DEBUG
        var hasReportedIgnoredReinitialization = false
      #endif
    }
  }
#endif
