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
    }
    return true
  }

  func application(
    _ application: UIApplication,
    userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
  ) {
    Task {
      try await syncEngine.acceptShare(metadata: cloudKitShareMetadata)
    }
  }
}
#endif
