import Foundation
import SharingGRDB

@Table struct Reminder: Equatable, Identifiable {
  let id: UUID
  var title = ""
  var parentReminderID: Reminder.ID?
  var remindersListID: RemindersList.ID
}
@Table struct RemindersList: Equatable, Identifiable {
  let id: UUID
  var title = ""
}

func database() throws -> DatabasePool {
  var configuration = Configuration()
  configuration.foreignKeysEnabled = false
  let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
  let database = try DatabasePool(path: url.path(), configuration: configuration)
  try database.write { db in
    try #sql(
      """
      CREATE TABLE "remindersLists" (
        "id" TEXT PRIMARY KEY DEFAULT (uuid()),
        "title" TEXT NOT NULL
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "reminders" (
        "id" TEXT PRIMARY KEY DEFAULT (uuid()),
        "title" TEXT NOT NULL,
        "parentReminderID" TEXT REFERENCES "reminders"("id") ON DELETE SET NULL,
        "remindersListID" TEXT NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE ON UPDATE CASCADE
      ) STRICT
      """
    )
    .execute(db)
  }
  return database
}
