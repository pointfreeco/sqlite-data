import Foundation
import IssueReporting
import OSLog
import SharingGRDB
import SwiftUI

@Table
struct RemindersList: Hashable, Identifiable {
  @Column(as: UUID.LowercasedRepresentation.self)
  var id: UUID
  @Column(as: Color.HexRepresentation.self)
  var color = Color(red: 0x4a / 255, green: 0x99 / 255, blue: 0xef / 255)
  var position = 0
  var title = ""
}

@Table
struct Reminder: Equatable, Identifiable {
  @Column(as: UUID.LowercasedRepresentation.self)
  var id: UUID
  @Column(as: Date.ISO8601Representation?.self)
  var dueDate: Date?
  var isCompleted = false
  var isFlagged = false
  var notes = ""
  var priority: Priority?
  @Column(as: UUID.LowercasedRepresentation.self)
  var remindersListID: RemindersList.ID
  var position = 0
  var title = ""
}

extension Reminder {
  static let incomplete = Self.where { !$0.isCompleted }
  static func searching(_ text: String) -> Where<Reminder> {
    Self.where {
      $0.title.collate(.nocase).contains(text)
        || $0.notes.collate(.nocase).contains(text)
    }
  }
  static let withTags = group(by: \.id)
    .leftJoin(ReminderTag.all) { $0.id.eq($1.reminderID) }
    .leftJoin(Tag.all) { $1.tagID.eq($2.id) }
}

extension Reminder.TableColumns {
  var isPastDue: some QueryExpression<Bool> {
    !isCompleted && #sql("coalesce(date(\(dueDate)) < date('now'), 0)")
  }
  var isToday: some QueryExpression<Bool> {
    !isCompleted && #sql("coalesce(date(\(dueDate)) = date('now'), 0)")
  }
  var isScheduled: some QueryExpression<Bool> {
    !isCompleted && dueDate.isNot(nil)
  }
  var inlineNotes: some QueryExpression<String> {
    notes.replace("\n", " ")
  }
}

enum Priority: Int, QueryBindable {
  case low = 1
  case medium
  case high
}

@Table
struct Tag: Hashable, Identifiable {
  @Column(as: UUID.LowercasedRepresentation.self)
  var id: UUID
  var title = ""
}

extension Tag {
  static let withReminders = group(by: \.id)
    .leftJoin(ReminderTag.all) { $0.id.eq($1.tagID) }
    .leftJoin(Reminder.all) { $1.reminderID.eq($2.id) }
}

extension Tag.TableColumns {
  var jsonNames: some QueryExpression<[String].JSONRepresentation> {
    self.title.jsonGroupArray(filter: self.title.isNot(nil))
  }
}

@Table("remindersTags")
struct ReminderTag: Hashable, Identifiable {
  @Column(as: UUID.LowercasedRepresentation.self)
  var reminderID: Reminder.ID
  @Column(as: UUID.LowercasedRepresentation.self)
  var tagID: Tag.ID
  var id: Self { self }
}

func appDatabase() throws -> any DatabaseWriter {
  @Dependency(\.context) var context
  let database: any DatabaseWriter
  var configuration = Configuration()
  configuration.foreignKeysEnabled = true
  configuration.prepareDatabase { db in
    #if DEBUG
      db.trace(options: .profile) {
        if context == .live {
          logger.debug("\($0.expandedDescription)")
        } else {
          print("\($0.expandedDescription)")
        }
      }
    #endif
  }
  if context == .live {
    let path = URL.documentsDirectory.appending(component: "db.sqlite").path()
    logger.info("open \(path)")
    database = try DatabasePool(path: path, configuration: configuration)
  } else {
    database = try DatabaseQueue(configuration: configuration)
  }
  var migrator = DatabaseMigrator()
  #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
  #endif
  migrator.registerMigration("Create initial tables") { db in
    try #sql(
      """
      CREATE TABLE "remindersLists" (
        "id" TEXT PRIMARY KEY DEFAULT (uuid()),
        "color" INTEGER NOT NULL DEFAULT \(raw: 0x4a99_ef00),
        "title" TEXT NOT NULL
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "reminders" (
        "id" TEXT PRIMARY KEY DEFAULT (uuid()),
        "dueDate" TEXT,
        "isCompleted" INTEGER NOT NULL DEFAULT 0,
        "isFlagged" INTEGER NOT NULL DEFAULT 0,
        "notes" TEXT,
        "priority" INTEGER,
        "remindersListID" TEXT NOT NULL,
        "title" TEXT NOT NULL,

        FOREIGN KEY("remindersListID") REFERENCES "remindersLists"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "tags" (
        "id" TEXT PRIMARY KEY DEFAULT (uuid()),
        "title" TEXT NOT NULL COLLATE NOCASE UNIQUE
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "remindersTags" (
        "reminderID" TEXT NOT NULL,
        "tagID" TEXT NOT NULL,

        FOREIGN KEY("reminderID") REFERENCES "reminders"("id") ON DELETE CASCADE,
        FOREIGN KEY("tagID") REFERENCES "tags"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
  }
  migrator.registerMigration("Add 'position' column to 'remindersLists'") { db in
    try #sql(
      """
      ALTER TABLE "remindersLists"
      ADD COLUMN "position" INTEGER NOT NULL DEFAULT 0
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TRIGGER "default_position_reminders_lists" 
      AFTER INSERT ON "remindersLists"
      FOR EACH ROW BEGIN
        UPDATE "remindersLists"
        SET "position" = (SELECT max("position") + 1 FROM "remindersLists")
        WHERE "id" = NEW."id";
      END
      """
    )
    .execute(db)
  }
  migrator.registerMigration("Add 'position' column to 'reminders'") { db in
    try #sql(
      """
      ALTER TABLE "reminders"
      ADD COLUMN "position" INTEGER NOT NULL DEFAULT 0
      """
    )
    .execute(db)
    // Backfill position of reminders based on their completion status and due date.
    try #sql(
      """
      WITH "reminderPositions" AS (
        SELECT
          "reminders"."id",
          ROW_NUMBER() OVER (PARTITION BY "remindersListID" ORDER BY id) - 1 AS "position"
        FROM "reminders"
        ORDER BY NOT "isCompleted", "dueDate" DESC
      )
      UPDATE "reminders"
      SET "position" = "reminderPositions"."position"
      FROM "reminderPositions"
      WHERE "reminders"."id" = "reminderPositions"."id"
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TRIGGER "default_position_reminders" 
      AFTER INSERT ON "reminders"
      FOR EACH ROW BEGIN
        UPDATE "reminders"
        SET "position" = (SELECT max("position") + 1 FROM "reminders")
        WHERE "id" = NEW."id";
      END
      """
    )
    .execute(db)
  }
  #if DEBUG && targetEnvironment(simulator)
    if context != .test {
      migrator.registerMigration("Seed sample data") { db in
        try db.seedSampleData()
      }
    }
  #endif
  try migrator.migrate(database)

  try database.write { db in
    try installTriggers(db: db)
  }

  /*
   prepareDependencies {
    $0.cloudKitDatabase = …
   }

   @Dependency(\.cloudKitDatabase) var cloudKitDatabase
   try cloudKitDatabase.registerTriggers(db)

   let tableNames = select name from sqlite_master where type = 'table';
   for tableName in tablesNames {
      CREATE TRIGGER "\(tableName)_insert_trigger"
      AFTER INSERT ON "\(tableName)" FOR EACH ROW BEGIN
        SELECT insertTrigger('\(tableName)', new.id)
      END
   }
}
   */

  return database
}

func installTriggers(db: Database) throws {
  db.add(function: DatabaseFunction.init("didInsert", function: { arguments in
    logger.info("didInsert: \(arguments[0]).\(arguments[1])")
    return 0
  }))
  db.add(function: DatabaseFunction.init("didUpdate", function: { arguments in
    logger.info("didUpdate: \(arguments[0]).\(arguments[1])")
    return 0
  }))
  db.add(function: DatabaseFunction.init("didDelete", function: { arguments in
    logger.info("didDelete: \(arguments[0]).\(arguments[1])")
    return 0
  }))
  let tableNames = try #sql(
    """
    SELECT "name" FROM "sqlite_master" WHERE "type" = 'table'
    """,
    as: String.self
  )
  .fetchAll(db)
  .filter { !$0.hasPrefix("sqlite_") && !$0.hasPrefix("grdb_") }

  for tableName in tableNames {
    try #sql(
      """
      DROP TRIGGER IF EXISTS "__\(raw: tableName)_sync_inserts"
      """
    )
    .execute(db)
    try #sql(
      """
      DROP TRIGGER IF EXISTS "__\(raw: tableName)_sync_updates"
      """
    )
    .execute(db)
    try #sql(
      """
      DROP TRIGGER IF EXISTS "__\(raw: tableName)_sync_deletes"
      """
    )
    .execute(db)
//    // TODO: what about tables without 'id'?
    try #sql(
      """
      CREATE TRIGGER "__\(raw: tableName)_sync_inserts"
      AFTER INSERT ON "\(raw: tableName)" FOR EACH ROW BEGIN
        SELECT didInsert('\(raw: tableName)', new.rowid);
      END
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TRIGGER "__\(raw: tableName)_sync_updates"
      AFTER UPDATE ON "\(raw: tableName)" FOR EACH ROW BEGIN
        SELECT didUpdate('\(raw: tableName)', new.rowid);
      END
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TRIGGER "__\(raw: tableName)_sync_deletes"
      BEFORE DELETE ON "\(raw: tableName)" FOR EACH ROW BEGIN
        SELECT didDelete('\(raw: tableName)', old.rowid);
      END
      """
    )
    .execute(db)
  }
}

//
//func insertTrigger(tableName: String, id: UUID) {
//  @Dependency(\.cloudKitDatabase) var db
//  db.add(pendingRecordZoneChanges: .saveRecord(CKRecord.ID(zoneID: tableName, recordName: id)))
//}
//func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
//}
//

private let logger = Logger(subsystem: "Reminders", category: "Database")

#if DEBUG
  extension Database {
    func seedSampleData() throws {
      try seed {
        RemindersList(
          id: UUID(1),
          color: Color(red: 0x4a / 255, green: 0x99 / 255, blue: 0xef / 255),
          title: "Personal"
        )
        RemindersList(
          id: UUID(2),
          color: Color(red: 0xed / 255, green: 0x89 / 255, blue: 0x35 / 255),
          title: "Family"
        )
        RemindersList(
          id: UUID(3),
          color: Color(red: 0xb2 / 255, green: 0x5d / 255, blue: 0xd3 / 255),
          title: "Business"
        )

        Reminder(
          id: UUID(1),
          notes: "Milk\nEggs\nApples\nOatmeal\nSpinach",
          remindersListID: UUID(1),
          title: "Groceries"
        )
        Reminder(
          id: UUID(2),
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isFlagged: true,
          remindersListID: UUID(1),
          title: "Haircut"
        )
        Reminder(
          id: UUID(3),
          dueDate: Date(),
          notes: "Ask about diet",
          priority: .high,
          remindersListID: UUID(1),
          title: "Doctor appointment"
        )
        Reminder(
          id: UUID(4),
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 190),
          isCompleted: true,
          remindersListID: UUID(1),
          title: "Take a walk"
        )
        Reminder(
          id: UUID(5),
          dueDate: Date(),
          remindersListID: UUID(1),
          title: "Buy concert tickets"
        )
        Reminder(
          id: UUID(6),
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 2),
          isFlagged: true,
          priority: .high,
          remindersListID: UUID(2),
          title: "Pick up kids from school"
        )
        Reminder(
          id: UUID(7),
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isCompleted: true,
          priority: .low,
          remindersListID: UUID(2),
          title: "Get laundry"
        )
        Reminder(
          id: UUID(8),
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 4),
          isCompleted: false,
          priority: .high,
          remindersListID: UUID(2),
          title: "Take out trash"
        )
        Reminder(
          id: UUID(9),
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 2),
          notes: """
            Status of tax return
            Expenses for next year
            Changing payroll company
            """,
          remindersListID: UUID(3),
          title: "Call accountant"
        )
        Reminder(
          id: UUID(10),
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isCompleted: true,
          priority: .medium,
          remindersListID: UUID(3),
          title: "Send weekly emails"
        )

        Tag(id: UUID(1), title: "car")
        Tag(id: UUID(2), title: "kids")
        Tag(id: UUID(3), title: "someday")
        Tag(id: UUID(4), title: "optional")
        Tag(id: UUID(5), title: "social")
        Tag(id: UUID(6), title: "night")
        Tag(id: UUID(7), title: "adulting")
        
        ReminderTag(reminderID: UUID(1), tagID: UUID(3))
        ReminderTag(reminderID: UUID(1), tagID: UUID(4))
        ReminderTag(reminderID: UUID(1), tagID: UUID(7))
        ReminderTag(reminderID: UUID(2), tagID: UUID(3))
        ReminderTag(reminderID: UUID(2), tagID: UUID(4))
        ReminderTag(reminderID: UUID(3), tagID: UUID(7))
        ReminderTag(reminderID: UUID(4), tagID: UUID(1))
        ReminderTag(reminderID: UUID(4), tagID: UUID(2))
      }
    }
  }
#endif
