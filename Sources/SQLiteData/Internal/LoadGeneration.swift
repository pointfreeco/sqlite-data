import Foundation

final class LoadGeneration: Sendable {
  private let count = LockIsolated(0)

  func begin() -> Token {
    Token(
      count: count,
      generation: count.withLock {
        $0 += 1
        return $0
      }
    )
  }

  func invalidate() {
    count.withLock { $0 += 1 }
  }

  struct Token: Sendable {
    fileprivate let count: LockIsolated<Int>
    fileprivate let generation: Int

    func ifCurrent(_ body: sending () -> Void) {
      count.withLock {
        guard $0 == generation else { return }
        body()
      }
    }
  }
}

private final class LockIsolated<Value>: @unchecked Sendable {
  private var _value: Value
  private let lock = NSLock()
  init(_ value: sending Value) {
    self._value = value
  }
  func withLock<T>(
    _ operation: sending (inout sending Value) throws -> sending T
  ) rethrows -> sending T {
    lock.lock()
    defer { lock.unlock() }
    var value = _value
    defer { _value = value }
    return try operation(&value)
  }
}
