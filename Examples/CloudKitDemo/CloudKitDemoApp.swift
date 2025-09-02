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
        $0.defaultSyncEngine = try SyncEngine(
          for: $0.defaultDatabase,
          tables: Counter.self
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

    func scene(
      _ scene: UIScene,
      willConnectTo session: UISceneSession,
      options connectionOptions: UIScene.ConnectionOptions
    ) {
      guard let cloudKitShareMetadata = connectionOptions.cloudKitShareMetadata
      else {
        return
      }
      Task {
        try await syncEngine.acceptShare(metadata: cloudKitShareMetadata)
      }
    }
  }
#endif
