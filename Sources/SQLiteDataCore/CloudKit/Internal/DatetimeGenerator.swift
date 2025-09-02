import Dependencies
import Foundation

package struct DatetimeGenerator: DependencyKey, Sendable {
  private var generate: @Sendable () -> Date
  package var now: Date {
    get { self.generate() }
    set { self.generate = { newValue } }
  }
  package func callAsFunction() -> Date {
    self.generate()
  }
  package static var liveValue: DatetimeGenerator {
    Self { Date() }
  }
  package static var testValue: DatetimeGenerator {
    Self { Date() }
  }
}

extension DependencyValues {
  package var datetime: DatetimeGenerator {
    get { self[DatetimeGenerator.self] }
    set { self[DatetimeGenerator.self] = newValue }
  }
}
