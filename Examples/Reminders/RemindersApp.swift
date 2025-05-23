import CloudKit
import SharingGRDB
import SwiftUI

@main
struct RemindersApp: App {
  init() {
    try! prepareDependencies {
      $0.defaultDatabase = try Reminders.appDatabase()
      $0.defaultSyncEngine = SyncEngine(
        container: CKContainer(
          identifier: "iCloud.co.pointfree.sharing-grdb.Reminders"
        ),
        database: $0.defaultDatabase,
        tables: [
          RemindersList.self,
          Reminder.self,
          Tag.self,
          ReminderTag.self,
        ]
      )
    }
  }

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        RemindersListsView()
      }
    }
  }
}
