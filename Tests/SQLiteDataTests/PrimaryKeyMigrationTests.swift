import Foundation
import SQLiteData
import SQLiteDataTestSupport
import SnapshotTesting
import Testing
import SQLite3

@Suite(.snapshots(record: .failed))
struct PrimaryKeyMigrationTests {
  @Table struct Parent: Identifiable {
    let id: Int
    var title = ""
  }
  @Table("parents") struct NewParent: Identifiable {
    let id: UUID
    var title = ""
  }
  @Table("children") struct Child {
    let id: Int
    var title = ""
    var parentID: PrimaryKeyMigrationTests.Parent.ID
  }
  @Table("children") struct NewChild {
    let id: UUID
    var title = ""
    var parentID: PrimaryKeyMigrationTests.NewParent.ID
  }

  @Test func test() throws {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      db.trace { print($0.expandedDescription) }
    }
    let database = try DatabaseQueue(configuration: configuration)
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "parents" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "title" TEXT NOT NULL
        ) STRICT
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE TABLE "children" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "title" TEXT NOT NULL,
          "parentID" INTEGER NOT NULL REFERENCES "parents"("id") ON DELETE CASCADE
        ) STRICT
        """
      )
      .execute(db)
      try db.seed {
        Parent.Draft(title: "foo")
        Parent.Draft(title: "bar")
        Parent.Draft(title: "baz")
        Child.Draft(title: "foo", parentID: 1)
        Child.Draft(title: "bar", parentID: 2)
        Child.Draft(title: "baz", parentID: 3)
      }
    }

    try database.writeWithoutTransaction { db in
      try #sql("PRAGMA foreign_keys = OFF").execute(db)
      try #sql("BEGIN IMMEDIATE TRANSACTION").execute(db)
      try Parent.migratePrimaryKeyToUUID(db: db)
      try Child.migratePrimaryKeyToUUID(db: db)
      try #sql("COMMIT TRANSACTION").execute(db)
      try #sql("PRAGMA foreign_keys = ON").execute(db)
    }

    assertQuery(SQLiteSchema.where { !$0.name.hasPrefix("sqlite_") }, database: database) {
      #"""
      ┌───────────────────────────────────────────────────────────────────────────┐
      │ SQLiteSchema(                                                             │
      │   type: .table,                                                           │
      │   name: "parents",                                                        │
      │   tableName: "parents",                                                   │
      │   sql: """                                                                │
      │   CREATE TABLE "parents" (                                                │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),  │
      │     "title" TEXT NOT NULL                                                 │
      │   ) STRICT                                                                │
      │   """                                                                     │
      │ )                                                                         │
      ├───────────────────────────────────────────────────────────────────────────┤
      │ SQLiteSchema(                                                             │
      │   type: .table,                                                           │
      │   name: "children",                                                       │
      │   tableName: "children",                                                  │
      │   sql: """                                                                │
      │   CREATE TABLE "children" (                                               │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),  │
      │     "title" TEXT NOT NULL,                                                │
      │     "parentID" TEXT NOT NULL REFERENCES "parents"("id") ON DELETE CASCADE │
      │   ) STRICT                                                                │
      │   """                                                                     │
      │ )                                                                         │
      └───────────────────────────────────────────────────────────────────────────┘
      """#
    }
    assertQuery(NewParent.all, database: database) {
      """
      ┌───────────────────────────────────────────────────┐
      │ PrimaryKeyMigrationTests.NewParent(               │
      │   id: UUID(00000000-0000-0000-0000-000000000001), │
      │   title: "foo"                                    │
      │ )                                                 │
      ├───────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.NewParent(               │
      │   id: UUID(00000000-0000-0000-0000-000000000002), │
      │   title: "bar"                                    │
      │ )                                                 │
      ├───────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.NewParent(               │
      │   id: UUID(00000000-0000-0000-0000-000000000003), │
      │   title: "baz"                                    │
      │ )                                                 │
      └───────────────────────────────────────────────────┘
      """
    }
    assertQuery(NewChild.all, database: database) {
      """
      ┌────────────────────────────────────────────────────────┐
      │ PrimaryKeyMigrationTests.NewChild(                     │
      │   id: UUID(00000000-0000-0000-0000-000000000001),      │
      │   title: "foo",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000001) │
      │ )                                                      │
      ├────────────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.NewChild(                     │
      │   id: UUID(00000000-0000-0000-0000-000000000002),      │
      │   title: "bar",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000002) │
      │ )                                                      │
      ├────────────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.NewChild(                     │
      │   id: UUID(00000000-0000-0000-0000-000000000003),      │
      │   title: "baz",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000003) │
      │ )                                                      │
      └────────────────────────────────────────────────────────┘
      """
    }
  }
}
