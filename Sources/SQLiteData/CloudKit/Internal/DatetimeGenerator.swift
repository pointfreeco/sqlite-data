import Dependencies
import Foundation

package struct CurrentTimeGenerator: DependencyKey, Sendable {
  private var generate: @Sendable () -> Int64
  package var now: Int64 {
    get { self.generate() }
    set { self.generate = { newValue } }
  }
  package func callAsFunction() -> Int64 {
    self.generate()
  }
  package static var liveValue: CurrentTimeGenerator {
    Self { Int64(clock_gettime_nsec_np(CLOCK_REALTIME)) }
  }
  package static var testValue: CurrentTimeGenerator {
    Self { Int64(clock_gettime_nsec_np(CLOCK_REALTIME)) }
  }
}

extension DependencyValues {
  package var currentTime: CurrentTimeGenerator {
    get { self[CurrentTimeGenerator.self] }
    set { self[CurrentTimeGenerator.self] = newValue }
  }
}
