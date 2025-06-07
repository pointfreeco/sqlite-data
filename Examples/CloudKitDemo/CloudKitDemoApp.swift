import CloudKit
import SharingGRDB
import SwiftUI

@main
struct CloudKitDemoApp: App {
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
