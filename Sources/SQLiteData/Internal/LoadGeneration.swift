import ConcurrencyExtras
import Foundation

final class LoadGeneration: Sendable {
  private let count = LockIsolated(0)

  func begin() -> Token {
    count.withValue {
      $0 += 1
      return Token(loadGeneration: self, generation: $0)
    }
  }

  func invalidate() {
    count.withValue {
      $0 += 1
    }
  }

  struct Token: Sendable {
    fileprivate let loadGeneration: LoadGeneration
    fileprivate let generation: Int

    func ifValid(_ body: @Sendable () -> Void) {
      loadGeneration.count.withValue {
        guard $0 == generation else { return }
        body()
      }
    }
  }
}
