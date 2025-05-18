import CloudKit
import SharingGRDB
import Testing

@Suite
struct CloudKitTests {
  let database: any DatabaseWriter
  let _syncEngine: Any

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  var syncEngine: SyncEngine {
    _syncEngine as! SyncEngine
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  init() throws {
    self.database = try SharingGRDBTests.database()
    _syncEngine = SyncEngine(
      container: CKContainer(identifier: "CloudKit-Anonymous.tests"),
      database: database,
      tables: [Reminder.self, RemindersList.self]
    )
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func setUpSyncEngine() throws {

  }
}

@Table private struct Reminder: Identifiable {
  let id: Int
  var title = ""
  var remindersListID: RemindersList.ID
}
@Table private struct RemindersList: Identifiable {
  let id: Int
  var title = ""
}

private func database() throws -> any DatabaseWriter {
  var configuration = Configuration()
  configuration.foreignKeysEnabled = false
  let database = try DatabaseQueue(configuration: configuration)
  var migrator = DatabaseMigrator()
  migrator.registerMigration("Create tables") { db in
    try #sql(
      """
      CREATE TABLE "remindersLists" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "title" TEXT NOT NULL
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "reminders" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "title" TEXT NOT NULL,
        "remindersListID" INTEGER NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
  }
  try migrator.migrate(database)
  return database
}
