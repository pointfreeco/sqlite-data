import Foundation
import SharingGRDB

@Table struct Reminder: Equatable, Identifiable {
  let id: UUID
  var title = ""
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

@Table struct Parent: Equatable, Identifiable {
  let id: UUID
}
@Table struct ChildWithOnDeleteRestrict: Equatable, Identifiable {
  let id: UUID
  let parentID: Parent.ID
}
@Table struct ChildWithOnDeleteSetNull: Equatable, Identifiable {
  let id: UUID
  let parentID: Parent.ID?
}
@Table struct ChildWithOnDeleteSetDefault: Equatable, Identifiable {
  let id: UUID
  let parentID: Parent.ID
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
func database() throws -> DatabasePool {
  var configuration = Configuration()
  configuration.foreignKeysEnabled = false
  configuration.prepareDatabase { db in 
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
        "id" TEXT NOT NULL PRIMARY KEY ON CONFLICT REPLACE DEFAULT (uuid()),
        "title" TEXT NOT NULL DEFAULT ''
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "users" (
        "id" TEXT NOT NULL PRIMARY KEY ON CONFLICT REPLACE DEFAULT (uuid()),
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
        "id" TEXT NOT NULL PRIMARY KEY ON CONFLICT REPLACE DEFAULT (uuid()),
        "title" TEXT NOT NULL DEFAULT '',
        "remindersListID" TEXT NOT NULL, 
        
        FOREIGN KEY("remindersListID") REFERENCES "remindersLists"("id") ON DELETE CASCADE ON UPDATE CASCADE
      ) STRICT
      """
    )
    .execute(db)
    try #sql("""
      CREATE TABLE "parents"(
        "id" TEXT NOT NULL PRIMARY KEY ON CONFLICT REPLACE DEFAULT (uuid())
      ) STRICT
      """)
    .execute(db)
    try #sql("""
      CREATE TABLE "childWithOnDeleteRestricts"(
        "id" TEXT NOT NULL PRIMARY KEY ON CONFLICT REPLACE DEFAULT (uuid()),
        "parentID" TEXT NOT NULL REFERENCES "parents"("id") ON DELETE RESTRICT ON UPDATE RESTRICT
      ) STRICT
      """)
    .execute(db)
    try #sql("""
      CREATE TABLE "childWithOnDeleteSetNulls"(
        "id" TEXT NOT NULL PRIMARY KEY ON CONFLICT REPLACE DEFAULT (uuid()),
        "parentID" TEXT REFERENCES "parents"("id") ON DELETE SET NULL ON UPDATE SET NULL
      ) STRICT
      """)
    .execute(db)
    try #sql("""
      CREATE TABLE "childWithOnDeleteSetDefaults"(
        "id" TEXT NOT NULL PRIMARY KEY ON CONFLICT REPLACE DEFAULT '00000000-0000-0000-0000-000000000000',
        "parentID" TEXT REFERENCES "parents"("id") ON DELETE SET DEFAULT ON UPDATE SET DEFAULT
      ) STRICT
      """)
    .execute(db)

    
  }
  return database
}
