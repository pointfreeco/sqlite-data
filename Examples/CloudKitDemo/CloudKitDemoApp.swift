import CloudKit
import SharingGRDB
import SwiftUI
#if canImport
import UIKit
#endif

@main
struct CloudKitDemoApp: App {
  @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        CountersListView()
      }
    }
  }
}


class AppDelegate: UIResponder, UIApplicationDelegate, ObservableObject {
  @Dependency(\.defaultSyncEngine) var syncEngine

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
  ) -> Bool {
    try! prepareDependencies {
      $0.defaultDatabase = try appDatabase()
      $0.defaultSyncEngine = try SyncEngine(
        container: CKContainer(identifier: "iCloud.co.pointfree.SQLiteData.demos.CloudKitDemo"),
        database: $0.defaultDatabase,
        tables: [
          Counter.self
        ]
      )
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
