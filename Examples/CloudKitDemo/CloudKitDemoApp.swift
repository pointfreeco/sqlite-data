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
}
