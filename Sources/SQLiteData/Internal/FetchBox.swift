#if canImport(SwiftUI)
  import Combine
  import Sharing
  import SwiftUI

  final class FetchBox<Value: Sendable>: @unchecked Sendable {
    var sharedReader: SharedReader<Value>
    var fetchKeyID: FetchKeyID?
    private var swiftUICancellable: AnyCancellable?

    init(sharedReader: SharedReader<Value>) {
      self.sharedReader = sharedReader
    }

    func update(from other: FetchBox) {
      guard
        let otherFetchKeyID = other.fetchKeyID,
        otherFetchKeyID != fetchKeyID
      else { return }
      sharedReader = other.sharedReader
      fetchKeyID = other.fetchKeyID
    }

    func subscribe(generation: SwiftUI.State<Int>) {
      guard #unavailable(iOS 17, macOS 14, tvOS 17, watchOS 10) else { return }
      _ = generation.wrappedValue
      swiftUICancellable = sharedReader.publisher
        .dropFirst()
        .sink { _ in generation.wrappedValue &+= 1 }
    }
  }
#endif
