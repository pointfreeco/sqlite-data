import CloudKit
import SQLiteData
import SwiftUI

@main
struct CloudKitDemoApp: App {
  @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
  @Dependency(\.context) var context

  init() {
//    if context == .live {
    try! prepareDependencies {
      $0.context = .preview
    }
      try! prepareDependencies {
        try $0.bootstrapDatabase()
      }
//    }
  }

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        CountersListView()
      }
    }
  }
}

class AppDelegate: UIResponder, UIApplicationDelegate, ObservableObject {
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
    else { return }
    Task {
      try await syncEngine.acceptShare(metadata: cloudKitShareMetadata)
    }
  }
}
