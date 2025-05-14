import CloudKit
import SharingGRDB
import SwiftUI

@main
struct RemindersApp: App {
  @Dependency(\.context) var context

  init() {
    if context == .live {
      try! prepareDependencies {
        $0.defaultDatabase = try Reminders.appDatabase()
//        $0.cloudKitDatabase = try CloudKitDatabase(
//          container: CKContainer(identifier: "iCloud.co.pointfree.sharing-grdb.Reminders"),
//          database: $0.defaultDatabase,
//          tables: [
//            Reminder.self,
//            RemindersList.self,
//            Tag.self,
//            ReminderTag.self,
//          ]
//        )
        $0.defaultSyncEngine = SyncEngine(
          container: CKContainer(identifier: "iCloud.co.pointfree.sharing-grdb.Reminders"),
          database: $0.defaultDatabase,
          tables: [
            Reminder.self,
            RemindersList.self,
            Tag.self,
            ReminderTag.self,
          ]
        )
      }
    }
  }

  var body: some Scene {
    WindowGroup {
      if context == .live {
        NavigationStack {
          RemindersListsView()
        }
      }
    }
  }
}
