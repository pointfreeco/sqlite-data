import Foundation
import InlineSnapshotTesting
import SQLite3
import SQLiteData
import SQLiteDataTestSupport
import SnapshotTesting
import SnapshotTestingCustomDump
import Testing

@Suite(.snapshots(record: .failed)) struct PrimaryKeyMigrationTests {
  @Table struct Parent: Identifiable {
    let id: UUID
    var title = ""
  }
  @Table("children") struct Child {
    let id: UUID
    var title = ""
    var parentID: PrimaryKeyMigrationTests.Parent.ID
  }
  @Table struct Tag {
    let id: UUID
    var title = ""
  }
  @Table struct PhoneNumber {
    @Column(primaryKey: true)
    let number: String
  }
  @Table struct User {
    @Column(primaryKey: true)
    let identifier: UUID
    var name = ""
  }
  let database = try! DatabaseQueue(
    configuration: {
      var configuration = Configuration()
      configuration.prepareDatabase { db in
        db.add(function: $uuid)
        db.add(function: $customUUID)
        db.trace { print($0.expandedDescription) }
      }
      return configuration
    }()
  )

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func basics() throws {
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
      try #sql(
        """
        CREATE TABLE "tags" (
          "title" TEXT NOT NULL
        ) STRICT
        """
      )
      .execute(db)
      try seed(db)
    }

    try migrate()

    assertQuery(SQLiteSchema.where { !$0.name.hasPrefix("sqlite_") }, database: database) {
      #"""
      ┌────────────────────────────────────────────────────────────────────────────┐
      │ SQLiteSchema(                                                              │
      │   type: .table,                                                            │
      │   name: "children",                                                        │
      │   tableName: "children",                                                   │
      │   sql: """                                                                 │
      │   CREATE TABLE "children" (                                                │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT ("uuid"()), │
      │     "title" TEXT NOT NULL,                                                 │
      │     "parentID" TEXT NOT NULL REFERENCES "parents"("id") ON DELETE CASCADE  │
      │   ) STRICT                                                                 │
      │   """                                                                      │
      │ )                                                                          │
      ├────────────────────────────────────────────────────────────────────────────┤
      │ SQLiteSchema(                                                              │
      │   type: .table,                                                            │
      │   name: "parents",                                                         │
      │   tableName: "parents",                                                    │
      │   sql: """                                                                 │
      │   CREATE TABLE "parents" (                                                 │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT ("uuid"()), │
      │     "title" TEXT NOT NULL                                                  │
      │   ) STRICT                                                                 │
      │   """                                                                      │
      │ )                                                                          │
      ├────────────────────────────────────────────────────────────────────────────┤
      │ SQLiteSchema(                                                              │
      │   type: .table,                                                            │
      │   name: "tags",                                                            │
      │   tableName: "tags",                                                       │
      │   sql: """                                                                 │
      │   CREATE TABLE "tags" (                                                    │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT ("uuid"()), │
      │     "title" TEXT NOT NULL                                                  │
      │   ) STRICT                                                                 │
      │   """                                                                      │
      │ )                                                                          │
      └────────────────────────────────────────────────────────────────────────────┘
      """#
    }
    assertQuery(Parent.all, database: database) {
      """
      ┌───────────────────────────────────────────────────┐
      │ PrimaryKeyMigrationTests.Parent(                  │
      │   id: UUID(00000000-0000-0000-0000-000000000001), │
      │   title: "foo"                                    │
      │ )                                                 │
      ├───────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Parent(                  │
      │   id: UUID(00000000-0000-0000-0000-000000000002), │
      │   title: "bar"                                    │
      │ )                                                 │
      ├───────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Parent(                  │
      │   id: UUID(00000000-0000-0000-0000-000000000003), │
      │   title: "baz"                                    │
      │ )                                                 │
      └───────────────────────────────────────────────────┘
      """
    }
    assertQuery(Child.all, database: database) {
      """
      ┌────────────────────────────────────────────────────────┐
      │ PrimaryKeyMigrationTests.Child(                        │
      │   id: UUID(00000000-0000-0000-0000-000000000001),      │
      │   title: "foo",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000001) │
      │ )                                                      │
      ├────────────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Child(                        │
      │   id: UUID(00000000-0000-0000-0000-000000000002),      │
      │   title: "bar",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000002) │
      │ )                                                      │
      ├────────────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Child(                        │
      │   id: UUID(00000000-0000-0000-0000-000000000003),      │
      │   title: "baz",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000003) │
      │ )                                                      │
      └────────────────────────────────────────────────────────┘
      """
    }
    // NB: Cannot select 'id' since it will be random UUID.
    assertQuery(Tag.select(\.title), database: database) {
      """
      ┌────────────┐
      │ "personal" │
      │ "business" │
      └────────────┘
      """
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func columnConstraints() throws {
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "parents" (
          "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE CHECK("id" > 0),
          "title" TEXT NOT NULL CHECK(length("title") > 0)
        ) STRICT
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE TABLE "children" (
          "id" INTEGER PRIMARY KEY, -- No autoincrement
          "title" TEXT COLLATE NOCASE NOT NULL DEFAULT (''),
          "parentID" INTEGER NOT NULL REFERENCES "parents"("id") ON DELETE CASCADE,
          "exlaimedTitle" TEXT NOT NULL AS ("title" || '!') STORED
        ) STRICT
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE TABLE "tags" (
          "title" TEXT NOT NULL UNIQUE
        ) STRICT
        """
      )
      .execute(db)
      try seed(db)
    }

    try migrate()

    assertQuery(SQLiteSchema.where { !$0.name.hasPrefix("sqlite_") }, database: database) {
      #"""
      ┌────────────────────────────────────────────────────────────────────────────────────────────────┐
      │ SQLiteSchema(                                                                                  │
      │   type: .table,                                                                                │
      │   name: "children",                                                                            │
      │   tableName: "children",                                                                       │
      │   sql: """                                                                                     │
      │   CREATE TABLE "children" (                                                                    │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT ("uuid"()), -- No autoincrement │
      │     "title" TEXT COLLATE NOCASE NOT NULL DEFAULT (''),                                         │
      │     "parentID" TEXT NOT NULL REFERENCES "parents"("id") ON DELETE CASCADE,                     │
      │     "exlaimedTitle" TEXT NOT NULL AS ("title" || '!') STORED                                   │
      │   ) STRICT                                                                                     │
      │   """                                                                                          │
      │ )                                                                                              │
      ├────────────────────────────────────────────────────────────────────────────────────────────────┤
      │ SQLiteSchema(                                                                                  │
      │   type: .table,                                                                                │
      │   name: "parents",                                                                             │
      │   tableName: "parents",                                                                        │
      │   sql: """                                                                                     │
      │   CREATE TABLE "parents" (                                                                     │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT ("uuid"()),                     │
      │     "title" TEXT NOT NULL CHECK(length("title") > 0)                                           │
      │   ) STRICT                                                                                     │
      │   """                                                                                          │
      │ )                                                                                              │
      ├────────────────────────────────────────────────────────────────────────────────────────────────┤
      │ SQLiteSchema(                                                                                  │
      │   type: .table,                                                                                │
      │   name: "tags",                                                                                │
      │   tableName: "tags",                                                                           │
      │   sql: """                                                                                     │
      │   CREATE TABLE "tags" (                                                                        │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT ("uuid"()),                     │
      │     "title" TEXT NOT NULL UNIQUE                                                               │
      │   ) STRICT                                                                                     │
      │   """                                                                                          │
      │ )                                                                                              │
      └────────────────────────────────────────────────────────────────────────────────────────────────┘
      """#
    }
    assertQuery(Parent.all, database: database) {
      """
      ┌───────────────────────────────────────────────────┐
      │ PrimaryKeyMigrationTests.Parent(                  │
      │   id: UUID(00000000-0000-0000-0000-000000000001), │
      │   title: "foo"                                    │
      │ )                                                 │
      ├───────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Parent(                  │
      │   id: UUID(00000000-0000-0000-0000-000000000002), │
      │   title: "bar"                                    │
      │ )                                                 │
      ├───────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Parent(                  │
      │   id: UUID(00000000-0000-0000-0000-000000000003), │
      │   title: "baz"                                    │
      │ )                                                 │
      └───────────────────────────────────────────────────┘
      """
    }
    assertQuery(Child.all, database: database) {
      """
      ┌────────────────────────────────────────────────────────┐
      │ PrimaryKeyMigrationTests.Child(                        │
      │   id: UUID(00000000-0000-0000-0000-000000000001),      │
      │   title: "foo",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000001) │
      │ )                                                      │
      ├────────────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Child(                        │
      │   id: UUID(00000000-0000-0000-0000-000000000002),      │
      │   title: "bar",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000002) │
      │ )                                                      │
      ├────────────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Child(                        │
      │   id: UUID(00000000-0000-0000-0000-000000000003),      │
      │   title: "baz",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000003) │
      │ )                                                      │
      └────────────────────────────────────────────────────────┘
      """
    }
    assertQuery(Tag.select(\.title), database: database) {
      """
      ┌────────────┐
      │ "business" │
      │ "personal" │
      └────────────┘
      """
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func topLevelConstraints() throws {
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "parents" (
          "id" INTEGER,
          "title" TEXT NOT NULL,

          PRIMARY KEY("id"),
          UNIQUE("title")
        ) STRICT
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE TABLE "children" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "title" TEXT NOT NULL,
          "parentID" INTEGER NOT NULL,

          CHECK("id" > 0 AND length("title") > 0),
          FOREIGN KEY ("parentID") REFERENCES "parents"("id") ON DELETE CASCADE
        ) STRICT
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE TABLE "tags" (
          "title" TEXT NOT NULL
        ) STRICT
        """
      )
      .execute(db)
      try seed(db)
    }

    try migrate()

    assertQuery(SQLiteSchema.where { !$0.name.hasPrefix("sqlite_") }, database: database) {
      #"""
      ┌────────────────────────────────────────────────────────────────────────────────────────────────┐
      │ SQLiteSchema(                                                                                  │
      │   type: .table,                                                                                │
      │   name: "children",                                                                            │
      │   tableName: "children",                                                                       │
      │   sql: """                                                                                     │
      │   CREATE TABLE "children" (                                                                    │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT ("uuid"()), -- No autoincrement │
      │     "title" TEXT COLLATE NOCASE NOT NULL DEFAULT (''),                                         │
      │     "parentID" TEXT NOT NULL REFERENCES "parents"("id") ON DELETE CASCADE,                     │
      │     "exlaimedTitle" TEXT NOT NULL AS ("title" || '!') STORED                                   │
      │   ) STRICT                                                                                     │
      │   """                                                                                          │
      │ )                                                                                              │
      ├────────────────────────────────────────────────────────────────────────────────────────────────┤
      │ SQLiteSchema(                                                                                  │
      │   type: .table,                                                                                │
      │   name: "parents",                                                                             │
      │   tableName: "parents",                                                                        │
      │   sql: """                                                                                     │
      │   CREATE TABLE "parents" (                                                                     │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT ("uuid"()),                     │
      │     "title" TEXT NOT NULL CHECK(length("title") > 0)                                           │
      │   ) STRICT                                                                                     │
      │   """                                                                                          │
      │ )                                                                                              │
      ├────────────────────────────────────────────────────────────────────────────────────────────────┤
      │ SQLiteSchema(                                                                                  │
      │   type: .table,                                                                                │
      │   name: "tags",                                                                                │
      │   tableName: "tags",                                                                           │
      │   sql: """                                                                                     │
      │   CREATE TABLE "tags" (                                                                        │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT ("uuid"()),                     │
      │     "title" TEXT NOT NULL UNIQUE                                                               │
      │   ) STRICT                                                                                     │
      │   """                                                                                          │
      │ )                                                                                              │
      └────────────────────────────────────────────────────────────────────────────────────────────────┘
      """#
    }
    assertQuery(Parent.all, database: database) {
      """
      ┌───────────────────────────────────────────────────┐
      │ PrimaryKeyMigrationTests.Parent(                  │
      │   id: UUID(00000000-0000-0000-0000-000000000001), │
      │   title: "foo"                                    │
      │ )                                                 │
      ├───────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Parent(                  │
      │   id: UUID(00000000-0000-0000-0000-000000000002), │
      │   title: "bar"                                    │
      │ )                                                 │
      ├───────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Parent(                  │
      │   id: UUID(00000000-0000-0000-0000-000000000003), │
      │   title: "baz"                                    │
      │ )                                                 │
      └───────────────────────────────────────────────────┘
      """
    }
    assertQuery(Child.all, database: database) {
      """
      ┌────────────────────────────────────────────────────────┐
      │ PrimaryKeyMigrationTests.Child(                        │
      │   id: UUID(00000000-0000-0000-0000-000000000001),      │
      │   title: "foo",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000001) │
      │ )                                                      │
      ├────────────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Child(                        │
      │   id: UUID(00000000-0000-0000-0000-000000000002),      │
      │   title: "bar",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000002) │
      │ )                                                      │
      ├────────────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Child(                        │
      │   id: UUID(00000000-0000-0000-0000-000000000003),      │
      │   title: "baz",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000003) │
      │ )                                                      │
      └────────────────────────────────────────────────────────┘
      """
    }
    assertQuery(Tag.select(\.title), database: database) {
      """
      ┌────────────┐
      │ "business" │
      │ "personal" │
      └────────────┘
      """
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func commentsAndNewlines() throws {
    try database.write { db in
      try #sql(
        """
        -- Comment
        CREATE TABLE "parents" ( -- Comment
          -- Comment
          "id" INTEGER -- Comment
            -- Comment
            PRIMARY KEY -- Comment
            -- Comment
            AUTOINCREMENT, -- Comment
          -- Comment
          "title" TEXT NOT NULL -- Comment
          -- Comment
        ) STRICT -- Comment
        -- Comment
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE TABLE "children" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "title" TEXT NOT NULL,
          "parentID" INTEGER 
            NOT NULL 
            REFERENCES "parents"("id") 
            ON DELETE CASCADE
            ON UPDATE CASCADE
        ) STRICT
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE TABLE "tags" (
          "title" TEXT NOT NULL
        ) STRICT
        """
      )
      .execute(db)
      try seed(db)
    }

    try migrate()

    assertQuery(SQLiteSchema.where { !$0.name.hasPrefix("sqlite_") }, database: database) {
      #"""
      ┌───────────────────────────────────────────────────────────────────────────────────────┐
      │ SQLiteSchema(                                                                         │
      │   type: .table,                                                                       │
      │   name: "children",                                                                   │
      │   tableName: "children",                                                              │
      │   sql: """                                                                            │
      │   CREATE TABLE "children" (                                                           │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT ("uuid"()),            │
      │     "title" TEXT NOT NULL,                                                            │
      │     "parentID" TEXT                                                                   │
      │       NOT NULL                                                                        │
      │       REFERENCES "parents"("id")                                                      │
      │       ON DELETE CASCADE                                                               │
      │       ON UPDATE CASCADE                                                               │
      │   ) STRICT                                                                            │
      │   """                                                                                 │
      │ )                                                                                     │
      ├───────────────────────────────────────────────────────────────────────────────────────┤
      │ SQLiteSchema(                                                                         │
      │   type: .table,                                                                       │
      │   name: "parents",                                                                    │
      │   tableName: "parents",                                                               │
      │   sql: """                                                                            │
      │   CREATE TABLE "parents" ( -- Comment                                                 │
      │     -- Comment                                                                        │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT ("uuid"()), -- Comment │
      │     -- Comment                                                                        │
      │     "title" TEXT NOT NULL -- Comment                                                  │
      │     -- Comment                                                                        │
      │   ) STRICT -- Comment                                                                 │
      │   -- Comment                                                                          │
      │   """                                                                                 │
      │ )                                                                                     │
      ├───────────────────────────────────────────────────────────────────────────────────────┤
      │ SQLiteSchema(                                                                         │
      │   type: .table,                                                                       │
      │   name: "tags",                                                                       │
      │   tableName: "tags",                                                                  │
      │   sql: """                                                                            │
      │   CREATE TABLE "tags" (                                                               │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT ("uuid"()),            │
      │     "title" TEXT NOT NULL                                                             │
      │   ) STRICT                                                                            │
      │   """                                                                                 │
      │ )                                                                                     │
      └───────────────────────────────────────────────────────────────────────────────────────┘
      """#
    }
    assertQuery(Parent.all, database: database) {
      """
      ┌───────────────────────────────────────────────────┐
      │ PrimaryKeyMigrationTests.Parent(                  │
      │   id: UUID(00000000-0000-0000-0000-000000000001), │
      │   title: "foo"                                    │
      │ )                                                 │
      ├───────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Parent(                  │
      │   id: UUID(00000000-0000-0000-0000-000000000002), │
      │   title: "bar"                                    │
      │ )                                                 │
      ├───────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Parent(                  │
      │   id: UUID(00000000-0000-0000-0000-000000000003), │
      │   title: "baz"                                    │
      │ )                                                 │
      └───────────────────────────────────────────────────┘
      """
    }
    assertQuery(Child.all, database: database) {
      """
      ┌────────────────────────────────────────────────────────┐
      │ PrimaryKeyMigrationTests.Child(                        │
      │   id: UUID(00000000-0000-0000-0000-000000000001),      │
      │   title: "foo",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000001) │
      │ )                                                      │
      ├────────────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Child(                        │
      │   id: UUID(00000000-0000-0000-0000-000000000002),      │
      │   title: "bar",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000002) │
      │ )                                                      │
      ├────────────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Child(                        │
      │   id: UUID(00000000-0000-0000-0000-000000000003),      │
      │   title: "baz",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000003) │
      │ )                                                      │
      └────────────────────────────────────────────────────────┘
      """
    }
    assertQuery(Tag.select(\.title), database: database) {
      """
      ┌────────────┐
      │ "personal" │
      │ "business" │
      └────────────┘
      """
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func nonIntPrimaryKey() throws {
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "phoneNumbers" (
          "number" TEXT NOT NULL PRIMARY KEY
        )
        """
      )
      .execute(db)
      try #sql("""
        INSERT INTO "phoneNumbers"
        VALUES
        ('212-555-1234')
        """)
      .execute(db)
    }

    let error = #expect(throws: (any Error).self) {
      try migrate(tables: PhoneNumber.self)
    }
    assertInlineSnapshot(of: error, as: .customDump) {
      """
      MigrationError()
      """
    }
    assertQuery(SQLiteSchema.where { !$0.name.hasPrefix("sqlite_") }, database: database) {
      #"""
      ┌────────────────────────────────────────┐
      │ SQLiteSchema(                          │
      │   type: .table,                        │
      │   name: "phoneNumbers",                │
      │   tableName: "phoneNumbers",           │
      │   sql: """                             │
      │   CREATE TABLE "phoneNumbers" (        │
      │     "number" TEXT NOT NULL PRIMARY KEY │
      │   )                                    │
      │   """                                  │
      │ )                                      │
      └────────────────────────────────────────┘
      """#
    }
    assertQuery(PhoneNumber.all, database: database) {
      """
      ┌──────────────────────────────────────────────────────────────┐
      │ PrimaryKeyMigrationTests.PhoneNumber(number: "212-555-1234") │
      └──────────────────────────────────────────────────────────────┘
      """
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func compoundPrimaryKey() throws {
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "parents" (
          "id" INTEGER,
          "title" TEXT NOT NULL,
        
          PRIMARY KEY("id", "title")
        ) STRICT
        """
      )
      .execute(db)
    }

    let error = #expect(throws: (any Error).self) {
      try migrate(tables: Parent.self)
    }
    assertInlineSnapshot(of: error, as: .customDump) {
      """
      MigrationError()
      """
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func addPrimaryKeyWithCustomName() throws {
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "users" (
          "name" TEXT NOT NULL
        )
        """
      )
      .execute(db)
      try #sql("""
        INSERT INTO "users"
        VALUES
        ('blob'), ('blob jr'), ('blob sr')
        """)
      .execute(db)
    }

    try migrate(tables: User.self)

    assertQuery(SQLiteSchema.where { !$0.name.hasPrefix("sqlite_") }, database: database) {
      #"""
      ┌────────────────────────────────────────────────────────────────────────────┐
      │ SQLiteSchema(                                                              │
      │   type: .table,                                                            │
      │   name: "users",                                                           │
      │   tableName: "users",                                                      │
      │   sql: """                                                                 │
      │   CREATE TABLE "users" (                                                   │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT ("uuid"()), │
      │     "name" TEXT NOT NULL                                                   │
      │   )                                                                        │
      │   """                                                                      │
      │ )                                                                          │
      └────────────────────────────────────────────────────────────────────────────┘
      """#
    }
    assertQuery(User.select(\.name), database: database) {
      """
      ┌───────────┐
      │ "blob"    │
      │ "blob jr" │
      │ "blob sr" │
      └───────────┘
      """
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func lowercaseNoQuotes() throws {
    try database.write { db in
      try #sql(
        """
        create table parents (
          id integer primary key autoincrement,
          title text not null
        ) strict
        """
      )
      .execute(db)
      try #sql(
        """
        create table children (
          id integer primary key autoincrement,
          title text not null,
          parentID integer not null references parents(id) on delete cascade
        ) strict
        """
      )
      .execute(db)
      try #sql(
        """
        create table tags (
          title text not null
        ) strict
        """
      )
      .execute(db)
      try seed(db)
    }

    try migrate()

    assertQuery(SQLiteSchema.where { !$0.name.hasPrefix("sqlite_") }, database: database) {
      #"""
      ┌────────────────────────────────────────────────────────────────────────────┐
      │ SQLiteSchema(                                                              │
      │   type: .table,                                                            │
      │   name: "parents",                                                         │
      │   tableName: "parents",                                                    │
      │   sql: """                                                                 │
      │   CREATE TABLE "parents" (                                                 │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT ("uuid"()), │
      │     title text not null                                                    │
      │   ) strict                                                                 │
      │   """                                                                      │
      │ )                                                                          │
      ├────────────────────────────────────────────────────────────────────────────┤
      │ SQLiteSchema(                                                              │
      │   type: .table,                                                            │
      │   name: "children",                                                        │
      │   tableName: "children",                                                   │
      │   sql: """                                                                 │
      │   CREATE TABLE "children" (                                                │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT ("uuid"()), │
      │     title text not null,                                                   │
      │     parentID TEXT not null references parents(id) on delete cascade        │
      │   ) strict                                                                 │
      │   """                                                                      │
      │ )                                                                          │
      ├────────────────────────────────────────────────────────────────────────────┤
      │ SQLiteSchema(                                                              │
      │   type: .table,                                                            │
      │   name: "tags",                                                            │
      │   tableName: "tags",                                                       │
      │   sql: """                                                                 │
      │   CREATE TABLE "tags" (                                                    │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT ("uuid"()), │
      │     title text not null                                                    │
      │   ) strict                                                                 │
      │   """                                                                      │
      │ )                                                                          │
      └────────────────────────────────────────────────────────────────────────────┘
      """#
    }
    assertQuery(Parent.all, database: database) {
      """
      ┌───────────────────────────────────────────────────┐
      │ PrimaryKeyMigrationTests.Parent(                  │
      │   id: UUID(00000000-0000-0000-0000-000000000001), │
      │   title: "foo"                                    │
      │ )                                                 │
      ├───────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Parent(                  │
      │   id: UUID(00000000-0000-0000-0000-000000000002), │
      │   title: "bar"                                    │
      │ )                                                 │
      ├───────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Parent(                  │
      │   id: UUID(00000000-0000-0000-0000-000000000003), │
      │   title: "baz"                                    │
      │ )                                                 │
      └───────────────────────────────────────────────────┘
      """
    }
    assertQuery(Child.all, database: database) {
      """
      ┌────────────────────────────────────────────────────────┐
      │ PrimaryKeyMigrationTests.Child(                        │
      │   id: UUID(00000000-0000-0000-0000-000000000001),      │
      │   title: "foo",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000001) │
      │ )                                                      │
      ├────────────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Child(                        │
      │   id: UUID(00000000-0000-0000-0000-000000000002),      │
      │   title: "bar",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000002) │
      │ )                                                      │
      ├────────────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.Child(                        │
      │   id: UUID(00000000-0000-0000-0000-000000000003),      │
      │   title: "baz",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000003) │
      │ )                                                      │
      └────────────────────────────────────────────────────────┘
      """
    }

    // NB: Cannot select 'id' since it will be random UUID.
    assertQuery(Tag.select(\.title), database: database) {
      """
      ┌────────────┐
      │ "personal" │
      │ "business" │
      └────────────┘
      """
    }
  }
  private func seed(_ db: Database) throws {
    try #sql(
      """
      INSERT INTO "parents"
      ("title")
      VALUES
      ('foo'), ('bar'), ('baz')
      """
    )
    .execute(db)
    try #sql(
      """
      INSERT INTO "children"
      ("title", "parentID")
      VALUES
      ('foo', 1), ('bar', 2), ('baz', 3) 
      """
    )
    .execute(db)
    try #sql(
      """
      INSERT INTO "tags"
      ("title")
      VALUES
      ('personal'), ('business')
      """
    )
    .execute(db)
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  private func migrate() throws {
    try migrate(tables: Parent.self, Child.self, Tag.self)
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  private func migrate<each T: PrimaryKeyedTable>(
    tables: repeat (each T).Type
  ) throws where repeat (each T).PrimaryKey.QueryOutput: IdentifierStringConvertible {
    try database.writeWithoutTransaction { db in
      try #sql("PRAGMA foreign_keys = OFF").execute(db)
      defer { try? #sql("PRAGMA foreign_keys = ON").execute(db) }
      do {
        try db.inTransaction {
          try SyncEngine.migratePrimaryKeys(
            db,
            tables: repeat each tables,
            uuid: $uuid
          )
          return .commit
        }
      }
    }
  }
}

@DatabaseFunction private func uuid() -> UUID { UUID() }
@DatabaseFunction private func customUUID() -> UUID { UUID() }
