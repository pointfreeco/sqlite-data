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
  @Dependency(\.defaultSyncEngine) var syncEngine

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
  ) -> Bool {
    try! prepareDependencies {
      $0.defaultDatabase = try appDatabase()
      $0.defaultSyncEngine = try SyncEngine(
        container: CKContainer(
          identifier: "iCloud.co.pointfree.SQLiteData.demos.CloudKitDemo"
        ),
        database: $0.defaultDatabase,
        tables: [Counter.self]
      )
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
  func windowScene(
    _ windowScene: UIWindowScene,
    userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
  ) {
    @Dependency(\.defaultSyncEngine) var syncEngine
    Task {
      try await syncEngine.acceptShare(metadata: cloudKitShareMetadata)
    }
  }
}
#endif
