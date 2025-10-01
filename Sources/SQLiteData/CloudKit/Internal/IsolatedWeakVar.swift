#if canImport(CloudKit)
  import Foundation

  final class IsolatedWeakVar<T: AnyObject>: @unchecked Sendable {
    let lock = NSLock()
    weak var _value: T?

    init() {}

    var value: T? {
      lock.lock()
      defer { lock.unlock() }
      return _value
    }
    func set(_ value: T) {
      precondition(_value == nil)
      lock.lock()
      defer { lock.unlock() }
      _value = value
    }
  }
#endif
