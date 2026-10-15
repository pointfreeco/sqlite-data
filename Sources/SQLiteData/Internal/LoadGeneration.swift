import Foundation

final class LoadGeneration: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  func begin() -> Token {
    lock.lock()
    defer { lock.unlock() }
    count += 1
    return Token(loadGeneration: self, generation: count)
  }

  func invalidate() {
    lock.lock()
    defer { lock.unlock() }
    count += 1
  }

  struct Token: Sendable {
    fileprivate let loadGeneration: LoadGeneration
    fileprivate let generation: Int

    func ifCurrent(_ body: () -> Void) {
      loadGeneration.lock.lock()
      defer { loadGeneration.lock.unlock() }
      guard loadGeneration.count == generation else { return }
      body()
    }
  }
}
