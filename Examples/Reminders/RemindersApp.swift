import CloudKit
import Combine
import Dependencies
import SharingGRDB
import SwiftUI
import UIKit

@main
struct RemindersApp: App {
  @UIApplicationDelegateAdaptor var delegate: AppDelegate
  @Dependency(\.context) var context
  static let model = RemindersListsModel()

  init() {
    if context == .live {
      try! prepareDependencies {
        try $0.bootstrapDatabase()
      }
    }
  }

  var body: some Scene {
    WindowGroup {
      if context == .live {
        NavigationStack {
          RemindersListsView(model: Self.model)
        }
      }
    }
  }
}

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
