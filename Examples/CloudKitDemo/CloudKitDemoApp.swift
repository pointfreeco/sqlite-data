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

  init() {
    try! prepareDependencies {
      $0.defaultDatabase = try appDatabase()
      $0.defaultSyncEngine = try SyncEngine(
        container: CKContainer(
          identifier: "iCloud.co.pointfree.SharingGRDB.CloudKitDemo"
        ),
        database: $0.defaultDatabase,
        tables: [Counter.self]
      )
    }
  }
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
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
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
  @Dependency(\.defaultSyncEngine) var syncEngine
  var window: UIWindow?
  func windowScene(
    _ windowScene: UIWindowScene,
    userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
  ) {
    Task {
      try await syncEngine.acceptShare(metadata: cloudKitShareMetadata)
    }
  }
}
#endif
