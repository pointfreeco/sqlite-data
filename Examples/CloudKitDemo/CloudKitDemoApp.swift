import CloudKit
import SharingGRDB
import SwiftUI

#if canImport
  import UIKit
#endif

@main
struct CloudKitDemoApp: App {
  #if canImport(UIKit)
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
  #endif
  var body: some Scene {
    WindowGroup {
      NavigationStack {
        CountersListView()
      }
    }
  }
}

#if canImport(UIKit)
  class AppDelegate: UIResponder, UIApplicationDelegate, ObservableObject {
    func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication
        .LaunchOptionsKey: Any]? = nil
    ) -> Bool {
      try! prepareDependencies {
        $0.defaultDatabase = try appDatabase()
      }
      return true
    }

    func application(
      _ application: UIApplication,
      configurationForConnecting connectingSceneSession: UISceneSession,
      options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
      let configuration = UISceneConfiguration(
        name: "Default Configuration",
        sessionRole: connectingSceneSession.role
      )
      configuration.delegateClass = SceneDelegate.self
      return configuration
    }
  }

  class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
  }
#endif
