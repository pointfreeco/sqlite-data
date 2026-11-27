import Dependencies
import Clocks

@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
extension DependencyValues {
  package var cloudKitClock: any NonsendingClock<Duration> {
    get { self[CloudKitClockKey.self] }
    set { self[CloudKitClockKey.self] = newValue }
  }

  private enum CloudKitClockKey: DependencyKey {
    static let liveValue: any NonsendingClock<Duration> = ContinuousClock()
    static let testValue: any NonsendingClock<Duration> = ContinuousClock()
  }
}
