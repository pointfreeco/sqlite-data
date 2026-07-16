#if canImport(SwiftUI)
  import Combine
  import Foundation
  import Sharing
  import SwiftUI

  final class FetchBox<Value: Sendable, Extra: Sendable>: @unchecked Sendable {
    private let storage: LockIsolated<Storage>

    init(sharedReader: SharedReader<Value>, extra: Extra) {
      storage = LockIsolated(Storage(sharedReader: sharedReader, extra: extra))
    }

    var sharedReader: SharedReader<Value> {
      get { storage.withLock { $0.sharedReader } }
      set { storage.withLock { $0.sharedReader = newValue } }
    }

    var fetchKeyID: FetchKeyID? {
      get { storage.withLock(\.fetchKeyID) }
      set { storage.withLock { $0.fetchKeyID = newValue } }
    }

    var extra: Extra {
      get { storage.withLock(\.extra) }
      set { storage.withLock { $0.extra = newValue } }
    }

    func update(from other: FetchBox) {
      guard
        let otherFetchKeyID = other.storage.withLock(\.fetchKeyID),
        otherFetchKeyID != fetchKeyID
      else { return }
      storage.withLock {
        $0.sharedReader = other.sharedReader
        $0.fetchKeyID = other.fetchKeyID
        $0.extra = other.extra
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
      var extra: Extra
      var swiftUICancellable: AnyCancellable?
    }
  }

  extension FetchBox where Extra == Void {
    convenience init(sharedReader: SharedReader<Value>) {
      self.init(sharedReader: sharedReader, extra: ())
    }
  }
#endif
