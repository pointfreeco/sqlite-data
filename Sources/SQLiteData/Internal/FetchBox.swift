#if canImport(SwiftUI)
  import Combine
  import Foundation
  import Sharing
  import SwiftUI

  final class FetchBox<Value: Sendable>: @unchecked Sendable {
    private let storage: LockIsolated<Storage>

    init(sharedReader: SharedReader<Value>) {
      storage = LockIsolated(Storage(sharedReader: sharedReader))
    }

    var sharedReader: SharedReader<Value> {
      get { storage.withLock { $0.sharedReader } }
      set { storage.withLock { $0.sharedReader = newValue } }
    }

    var fetchKeyID: FetchKeyID? {
      get { storage.withLock(\.fetchKeyID) }
      set { storage.withLock { $0.fetchKeyID = newValue } }
    }

    func update(from other: FetchBox) {
      guard
        let otherFetchKeyID = other.storage.withLock(\.fetchKeyID),
        otherFetchKeyID != fetchKeyID
      else { return }
      storage.withLock {
        $0.sharedReader = other.sharedReader
        $0.fetchKeyID = other.fetchKeyID
      }
    }

    func subscribe(generation: SwiftUI.State<Int>) {
      guard #unavailable(iOS 17, macOS 14, tvOS 17, watchOS 10) else { return }
      _ = generation.wrappedValue
      storage.withLock {
        $0.swiftUICancellable = sharedReader.publisher
          .dropFirst()
          .sink { _ in generation.wrappedValue &+= 1 }
      }
    }

    private struct Storage {
      var sharedReader: SharedReader<Value>
      var fetchKeyID: FetchKeyID?
      var swiftUICancellable: AnyCancellable?
    }
  }
#endif
