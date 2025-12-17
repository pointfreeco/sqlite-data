import CloudKit
import Combine
import Dependencies
import SQLiteData
import SwiftData
import SwiftUI
import UIKit

@main
struct RemindersApp: App {
  @UIApplicationDelegateAdaptor var delegate: AppDelegate
  @Dependency(\.context) var context
  @Dependency(\.defaultSyncEngine) var syncEngine
  static let model = RemindersListsModel()

  @State var syncEngineDelegate = RemindersSyncEngineDelegate()

  init() {
    if context == .live {
      try! prepareDependencies {
        try $0.bootstrapDatabase(syncEngineDelegate: syncEngineDelegate)
      }
    }
  }

  var body: some Scene {
    WindowGroup {
      if context == .live {
        NavigationStack {
          RemindersListsView(model: Self.model)
        }
        .alert(
          "Reset local data?",
          isPresented: $syncEngineDelegate.isDeleteLocalDataAlertPresented
        ) {
          Button("Reset", role: .destructive) {
            Task {
              try await syncEngine.deleteLocalData()
            }
          }
        } message: {
          Text(
            """
            You are no longer logged into iCloud. Would you like to reset your local data to the \
            defaults? This will not affect your data in iCloud.
            """
          )
        }
      }
    }
  }
}

@MainActor
@Observable
class RemindersSyncEngineDelegate: SyncEngineDelegate {
  var isDeleteLocalDataAlertPresented = false
  func syncEngine(
    _ syncEngine: SQLiteData.SyncEngine,
    accountChanged changeType: CKSyncEngine.Event.AccountChange.ChangeType
  ) async {
    switch changeType {
    case .signIn:
      break
    case .signOut, .switchAccounts:
      isDeleteLocalDataAlertPresented = true
    @unknown default:
      break
    }
  }
}

class AppDelegate: UIResponder, UIApplicationDelegate, ObservableObject {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    true
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
