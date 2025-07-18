import Foundation
import SharingGRDB

// NB: The IDs in this schema are integers for ease of testing. You should _not_ use integer IDs
//     in a production application.

@Table struct Reminder: Equatable, Identifiable {
  let id: Int
  var dueDate: Date?
  var isCompleted = false
  var priority: Int?
  var title = ""
  var remindersListID: RemindersList.ID
}
@Table struct RemindersList: Equatable, Identifiable {
  let id: Int
  var title = ""
}
@Table struct RemindersListAsset: Equatable, Identifiable {
  let id: Int
  var coverImage: Data?
  var remindersListID: RemindersList.ID
}
@Table struct RemindersListPrivate: Equatable, Identifiable {
  let id: Int
  var position = 0
  var remindersListID: RemindersList.ID
}
@Table struct Tag: Equatable, Identifiable {
  let id: Int
  var title = ""
}
@Table struct ReminderTag: Equatable, Identifiable {
  let id: Int
  var reminderID: Reminder.ID
  var tagID: Tag.ID
}
@Table struct Parent: Equatable, Identifiable {
  let id: Int
}
@Table struct ChildWithOnDeleteSetNull: Equatable, Identifiable {
  let id: Int
  let parentID: Parent.ID?
}
@Table struct ChildWithOnDeleteSetDefault: Equatable, Identifiable {
  let id: Int
  let parentID: Parent.ID
}
@Table struct LocalUser: Equatable, Identifiable {
  let id: Int
  var name = ""
  var parentID: LocalUser.ID?
}
@Table struct ModelA: Identifiable {
  let id: Int
  var count = 0
}
@Table struct ModelB: Identifiable {
  let id: Int
  var isOn = false
  var modelAID: ModelA.ID
}
@Table struct ModelC: Identifiable {
  let id: Int
  var title = ""
  var modelBID: ModelB.ID
}
@Table struct PrivateModel {
  let id: Int
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
func database(containerIdentifier: String) throws -> DatabasePool {
  var configuration = Configuration()
  configuration.prepareDatabase { db in
    try db.attachMetadatabase(containerIdentifier: containerIdentifier)
    db.trace {
      print($0.expandedDescription)
    }
  }
  let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
  let database = try DatabasePool(path: url.path(), configuration: configuration)
  try database.write { db in
    try #sql(
      """
      CREATE TABLE "remindersLists" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "remindersListAssets" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        "coverImage" BLOB NOT NULL,
        "remindersListID" INTEGER NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "remindersListPrivates" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
        "remindersListID" INTEGER NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "reminders" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        "dueDate" TEXT,
        "isCompleted" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
        "priority" INTEGER,
        "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
        "remindersListID" INTEGER NOT NULL,
        
        FOREIGN KEY("remindersListID") REFERENCES "remindersLists"("id") ON DELETE CASCADE ON UPDATE CASCADE
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "tags" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "reminderTags" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        "reminderID" INTEGER NOT NULL REFERENCES "reminders"("id") ON DELETE CASCADE,
        "tagID" INTEGER NOT NULL REFERENCES "tags"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
    try #sql("""
      CREATE TABLE "parents"(
        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
      ) STRICT
      """)
    .execute(db)
    try #sql("""
      CREATE TABLE "childWithOnDeleteSetNulls"(
        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        "parentID" INTEGER REFERENCES "parents"("id") ON DELETE SET NULL ON UPDATE SET NULL
      ) STRICT
      """)
    .execute(db)
    try #sql("""
      CREATE TABLE "childWithOnDeleteSetDefaults"(
        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        "parentID" INTEGER NOT NULL DEFAULT 0 
          REFERENCES "parents"("id") ON DELETE SET DEFAULT ON UPDATE SET DEFAULT
      ) STRICT
      """)
    .execute(db)
    try #sql(
      """
      CREATE TABLE "localUsers" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        "name" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
        "parentID" INTEGER REFERENCES "localUsers"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
    try #sql("""
      CREATE TABLE "modelAs" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        "count" INTEGER NOT NULL
      )
      """)
    .execute(db)
    try #sql("""
      CREATE TABLE "modelBs" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        "isOn" INTEGER NOT NULL,
        "modelAID" INTEGER NOT NULL REFERENCES "modelAs"("id") ON DELETE CASCADE
      )
      """)
    .execute(db)
    try #sql("""
      CREATE TABLE "modelCs" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        "title" TEXT NOT NULL,
        "modelBID" INTEGER NOT NULL REFERENCES "modelBs"("id") ON DELETE CASCADE
      )
      """)
    .execute(db)
    try #sql("""
      CREATE TABLE "privateModels" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
      )
      """)
    .execute(db)
  }
  return database
}
