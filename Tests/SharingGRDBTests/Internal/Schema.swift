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
@Table struct ChildWithOnDeleteRestrict: Equatable, Identifiable {
  let id: Int
  let parentID: Parent.ID
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
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "remindersListAssets" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "coverImage" BLOB NOT NULL,
        "remindersListID" TEXT NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "remindersListPrivates" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
        "remindersListID" TEXT NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "reminders" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "dueDate" TEXT,
        "isCompleted" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
        "priority" INTEGER,
        "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
        "remindersListID" TEXT NOT NULL,
        
        FOREIGN KEY("remindersListID") REFERENCES "remindersLists"("id") ON DELETE CASCADE ON UPDATE CASCADE
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "tags" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "reminderTags" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "reminderID" TEXT NOT NULL REFERENCES "reminders"("id") ON DELETE CASCADE,
        "tagID" TEXT NOT NULL REFERENCES "tags"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
    try #sql("""
      CREATE TABLE "parents"(
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid())
      ) STRICT
      """)
    .execute(db)
    try #sql("""
      CREATE TABLE "childWithOnDeleteRestricts"(
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "parentID" TEXT NOT NULL REFERENCES "parents"("id") ON DELETE RESTRICT ON UPDATE RESTRICT
      ) STRICT
      """)
    .execute(db)
    try #sql("""
      CREATE TABLE "childWithOnDeleteSetNulls"(
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "parentID" TEXT REFERENCES "parents"("id") ON DELETE SET NULL ON UPDATE SET NULL
      ) STRICT
      """)
    .execute(db)
    try #sql("""
      CREATE TABLE "childWithOnDeleteSetDefaults"(
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT '00000000-0000-0000-0000-000000000000',
        "parentID" TEXT REFERENCES "parents"("id") ON DELETE SET DEFAULT ON UPDATE SET DEFAULT
      ) STRICT
      """)
    .execute(db)
    try #sql(
      """
      CREATE TABLE "localUsers" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "name" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
        "parentID" TEXT REFERENCES "localUsers"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
    try #sql("""
      CREATE TABLE "modelAs" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "count" INTEGER NOT NULL
      )
      """)
    .execute(db)
    try #sql("""
      CREATE TABLE "modelBs" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "isOn" INTEGER NOT NULL,
        "modelAID" INTEGER NOT NULL REFERENCES "modelAs"("id") ON DELETE CASCADE
      )
      """)
    .execute(db)
    try #sql("""
      CREATE TABLE "modelCs" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "title" TEXT NOT NULL,
        "modelBID" INTEGER NOT NULL REFERENCES "modelBs"("id") ON DELETE CASCADE
      )
      """)
    .execute(db)
  }
  return database
}
