#if canImport(UIKit)
  import UIKit
#endif

#if canImport(UIKit)
  private enum DefaultNotificationCenterKey: DependencyKey {
    static let liveValue = NotificationCenter.default
    static var testValue: NotificationCenter {
      NotificationCenter()
    }
  }
  extension DependencyValues {
    package var defaultNotificationCenter: NotificationCenter {
      get { self[DefaultNotificationCenterKey.self] }
      set { self[DefaultNotificationCenterKey.self] = newValue }
    }
  }
#endif
