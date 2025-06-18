import Foundation
import SharingGRDB

@Table struct Reminder: Equatable, Identifiable {
  let id: UUID
  var assignedUserID: User.ID?
  var title = ""
  var parentReminderID: ID?
  var remindersListID: RemindersList.ID
}
@Table struct RemindersList: Equatable, Identifiable {
  let id: UUID
  var title = ""
}
@Table struct User: Equatable, Identifiable {
  let id: UUID
  var name = ""
  var parentUserID: User.ID?
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
func database() throws -> DatabasePool {
  var configuration = Configuration()
  configuration.foreignKeysEnabled = false
  let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
  let database = try DatabasePool(path: url.path(), configuration: configuration)
  try database.write { db in
    try #sql(
      """
      CREATE TABLE "remindersLists" (
        "id" TEXT NOT NULL PRIMARY KEY DEFAULT (uuid()),
        "title" TEXT NOT NULL DEFAULT ''
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "users" (
        "id" TEXT NOT NULL PRIMARY KEY DEFAULT (uuid()),
        "name" TEXT NOT NULL DEFAULT '',
        "parentUserID" TEXT,
      
        FOREIGN KEY("parentUserID") REFERENCES "users"("id") ON DELETE SET DEFAULT ON UPDATE CASCADE 
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "reminders" (
        "id" TEXT NOT NULL PRIMARY KEY DEFAULT (uuid()),
        "assignedUserID" TEXT,
        "title" TEXT NOT NULL DEFAULT '',
        "parentReminderID" TEXT, 
        "remindersListID" TEXT NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000', 
        
        FOREIGN KEY("assignedUserID") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE,
        FOREIGN KEY("parentReminderID") REFERENCES "reminders"("id") ON DELETE RESTRICT ON UPDATE RESTRICT,
        FOREIGN KEY("remindersListID") REFERENCES "remindersLists"("id") ON DELETE CASCADE ON UPDATE CASCADE
      ) STRICT
      """
    )
    .execute(db)
  }
  return database
}
