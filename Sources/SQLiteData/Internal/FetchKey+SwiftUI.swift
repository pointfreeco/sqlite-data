#if canImport(SwiftUI)
  import Sharing
  import SwiftUI

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SharedReaderKey {
    static func fetch<Value>(
      _ request: some FetchKeyRequest<Value>,
      database: (any DatabaseWriter)? = nil,
      animation: Animation
    ) -> Self
    where Self == FetchKey<Value> {
      .fetch(request, database: database, scheduler: .animation(animation))
    }

    static func fetch<Records: RangeReplaceableCollection>(
      _ request: some FetchKeyRequest<Records>,
      database: (any DatabaseWriter)? = nil,
      animation: Animation
    ) -> Self
    where Self == FetchKey<Records>.Default {
      .fetch(request, database: database, scheduler: .animation(animation))
    }
  }

  package struct AnimatedScheduler: ValueObservationScheduler, Equatable {
    let animation: Animation
    package func immediateInitialValue() -> Bool { true }
    package func schedule(_ action: @escaping @Sendable () -> Void) {
      DispatchQueue.main.async {
        withAnimation(animation) {
          action()
        }
      }
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension AnimatedScheduler: Hashable {}

  extension ValueObservationScheduler where Self == AnimatedScheduler {
    package static func animation(_ animation: Animation) -> Self {
      AnimatedScheduler(animation: animation)
    }
  }
#endif
