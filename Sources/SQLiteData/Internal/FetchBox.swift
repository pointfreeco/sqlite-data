#if canImport(SwiftUI)
  import Combine
  import ConcurrencyExtras
  import Sharing
  import SwiftUI

  final class FetchBox<Value: Sendable>: Sendable {
    let sharedReader: SharedReader<Value>
    private let storage = LockIsolated(Storage())

    var fetchKeyID: FetchKeyID? {
      get { storage.withValue { $0.fetchKeyID } }
      set { storage.withValue { $0.fetchKeyID = newValue } }
    }

    init(sharedReader: SharedReader<Value>) {
      self.sharedReader = sharedReader
    }

    func update(from other: FetchBox) {
      guard let otherFetchKeyID = other.fetchKeyID else { return }
      let isAdopted = storage.withValue {
        guard otherFetchKeyID != $0.fetchKeyID else { return false }
        $0.fetchKeyID = otherFetchKeyID
        return true
      }
      guard isAdopted else { return }
      sharedReader.projectedValue = other.sharedReader.projectedValue
    }

    func subscribe(generation: SwiftUI.State<Int>) {
      guard #unavailable(iOS 17, macOS 14, tvOS 17, watchOS 10) else { return }
      _ = generation.wrappedValue
      storage.withValue {
        $0.swiftUICancellable = sharedReader.publisher
          .dropFirst()
          .sink { _ in generation.wrappedValue &+= 1 }
      }
    }

    private struct Storage {
      var fetchKeyID: FetchKeyID?
      var swiftUICancellable: AnyCancellable?
    }
  }

  final class FetchAllBox<Element: Sendable>: Sendable {
    let sharedReader: SharedReader<[Element]>
    let sectionedReader: SharedReader<ResultsSectionCollection<Element, String?>>
    let sectioning = LockIsolated<_Sectioning?>(nil)
    private let storage = LockIsolated(Storage())

    var fetchKeyID: FetchKeyID? {
      get { storage.withValue { $0.fetchKeyID } }
      set { storage.withValue { $0.fetchKeyID = newValue } }
    }

    init(sharedReader: SharedReader<[Element]>) {
      self.sharedReader = sharedReader
      self.sectionedReader = SharedReader(value: ResultsSectionCollection())
    }

    func update(from other: FetchAllBox) {
      guard let otherFetchKeyID = other.fetchKeyID else { return }
      let isAdopted = storage.withValue {
        guard otherFetchKeyID != $0.fetchKeyID else { return false }
        $0.fetchKeyID = otherFetchKeyID
        return true
      }
      guard isAdopted else { return }
      sharedReader.projectedValue = other.sharedReader.projectedValue
      sectionedReader.projectedValue = other.sectionedReader.projectedValue
      sectioning.setValue(other.sectioning.value)
    }

    func subscribe(generation: SwiftUI.State<Int>) {
      guard #unavailable(iOS 17, macOS 14, tvOS 17, watchOS 10) else { return }
      _ = generation.wrappedValue
      storage.withValue {
        $0.swiftUICancellables = [
          sharedReader.publisher
            .dropFirst()
            .sink { _ in generation.wrappedValue &+= 1 },
          sectionedReader.publisher
            .dropFirst()
            .sink { _ in generation.wrappedValue &+= 1 },
        ]
      }
    }

    private struct Storage {
      var fetchKeyID: FetchKeyID?
      var swiftUICancellables: [AnyCancellable] = []
    }
  }
#endif
