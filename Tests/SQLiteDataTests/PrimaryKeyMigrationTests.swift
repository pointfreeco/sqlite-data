import Foundation
import SQLite3
import SQLiteData
import SQLiteDataTestSupport
import SnapshotTesting
import Testing

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

  @DatabaseFunction func uuid() -> UUID {
    UUID()
  }

  @Test func test() throws {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      db.add(function: $uuid)
      db.trace { print($0.expandedDescription) }
    }
    let database = try DatabaseQueue(configuration: configuration)
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "parents" (  -- This comment's to exercise the parser a bit more
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "title" TEXT NOT NULL UNIQUE DEFAULT 'Blob''s world'
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
      try #sql(
        """
        CREATE UNIQUE INDEX "children_title_index" ON "children"("title")
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE TRIGGER "parents_trigger"
        AFTER INSERT ON "parents" BEGIN
        SELECT 1;
        END
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE TEMPORARY TRIGGER "children_temp_trigger"
        AFTER INSERT ON "children" BEGIN
        SELECT 1;
        END
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
      defer { try? #sql("PRAGMA foreign_keys = ON").execute(db) }
      do {
        try db.inTransaction {
          try db.migrateToSyncEnginePrimaryKeys(
            Child.self,
            Parent.self,
            uuidFunction: $uuid
          )
          return .commit
        }
      }
    }

    assertQuery(SQLiteSchema.where { !$0.name.hasPrefix("sqlite_") }, database: database) {
      #"""
      ┌─────────────────────────────────────────────────────────────────────────────────┐
      │ SQLiteSchema(                                                                   │
      │   type: .table,                                                                 │
      │   name: "children",                                                             │
      │   tableName: "children",                                                        │
      │   sql: """                                                                      │
      │   CREATE TABLE "children" (                                                     │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT ("uuid"()),      │
      │     "title" TEXT NOT NULL,                                                      │
      │     "parentID" TEXT NOT NULL REFERENCES "parents"("id") ON DELETE CASCADE       │
      │   ) STRICT                                                                      │
      │   """                                                                           │
      │ )                                                                               │
      ├─────────────────────────────────────────────────────────────────────────────────┤
      │ SQLiteSchema(                                                                   │
      │   type: .table,                                                                 │
      │   name: "parents",                                                              │
      │   tableName: "parents",                                                         │
      │   sql: """                                                                      │
      │   CREATE TABLE "parents" (  -- This comment's to exercise the parser a bit more │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT ("uuid"()),      │
      │     "title" TEXT NOT NULL UNIQUE DEFAULT 'Blob''s world'                        │
      │   ) STRICT                                                                      │
      │   """                                                                           │
      │ )                                                                               │
      ├─────────────────────────────────────────────────────────────────────────────────┤
      │ SQLiteSchema(                                                                   │
      │   type: .index,                                                                 │
      │   name: "children_title_index",                                                 │
      │   tableName: "children",                                                        │
      │   sql: #"CREATE UNIQUE INDEX "children_title_index" ON "children"("title")"#    │
      │ )                                                                               │
      ├─────────────────────────────────────────────────────────────────────────────────┤
      │ SQLiteSchema(                                                                   │
      │   type: .trigger,                                                               │
      │   name: "parents_trigger",                                                      │
      │   tableName: "parents",                                                         │
      │   sql: """                                                                      │
      │   CREATE TRIGGER "parents_trigger"                                              │
      │   AFTER INSERT ON "parents" BEGIN                                               │
      │   SELECT 1;                                                                     │
      │   END                                                                           │
      │   """                                                                           │
      │ )                                                                               │
      └─────────────────────────────────────────────────────────────────────────────────┘
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
