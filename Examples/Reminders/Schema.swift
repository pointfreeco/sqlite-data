import CloudKit
import Foundation
import IssueReporting
import OSLog
import SharingGRDB
import SwiftUI

@Table
struct RemindersList: Hashable, Identifiable {
  let id: UUID
  @Column(as: Color.HexRepresentation.self)
  var color = Color(red: 0x4a / 255, green: 0x99 / 255, blue: 0xef / 255)
  var position = 0
  var title = ""
}

@Table
struct Reminder: Equatable, Identifiable {
  let id: UUID
  var dueDate: Date?
  var isCompleted = false
  var isFlagged = false
  var notes = ""
  var priority: Priority?
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
  let id: UUID
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
  let id: UUID
  var reminderID: Reminder.ID
  var tagID: Tag.ID
}

func appDatabase() throws -> any DatabaseWriter {
  @Dependency(\.context) var context
  let database: any DatabaseWriter
  var configuration = Configuration()
  configuration.foreignKeysEnabled = context != .live
  configuration.prepareDatabase { db in
    #if DEBUG
      db.trace(options: .profile) {
        if context == .preview {
          print("\($0.expandedDescription)")
        } else {
          logger.debug("\($0.expandedDescription)")
        }
      }
    #endif
  }
  if context == .live {
    let path = URL.documentsDirectory.appending(component: "db.sqlite").path(percentEncoded: false)
    logger.info(
      """
      open "\(path)"
      """
    )
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
        "title" TEXT NOT NULL COLLATE NOCASE
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "remindersTags" (
        "id" TEXT NOT NULL PRIMARY KEY DEFAULT (uuid()),
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

  migrator.registerMigration("foo") { db in
    try #sql("alter table tags add column hello text").execute(db)
  }

  #if DEBUG && targetEnvironment(simulator)
    if context == .preview {
      migrator.registerMigration("Seed sample data") { db in
        try db.seedSampleData()
      }
    }
  #endif

  try migrator.migrate(database)
  return database
}

let logger = Logger(subsystem: "Reminders", category: "Database")

#if DEBUG
  extension Database {
    func seedSampleData() throws {
      try seed {
        RemindersList(
          id: UUID(0),
          color: Color(red: 0x4a / 255, green: 0x99 / 255, blue: 0xef / 255),
          title: "Personal"
        )
        RemindersList(
          id: UUID(1),
          color: Color(red: 0xed / 255, green: 0x89 / 255, blue: 0x35 / 255),
          title: "Family"
        )
        RemindersList(
          id: UUID(2),
          color: Color(red: 0xb2 / 255, green: 0x5d / 255, blue: 0xd3 / 255),
          title: "Business"
        )

        Reminder(
          id: UUID(0),
          notes: "Milk\nEggs\nApples\nOatmeal\nSpinach",
          remindersListID: UUID(0),
          title: "Groceries"
        )
        Reminder(
          id: UUID(1),
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isFlagged: true,
          remindersListID: UUID(0),
          title: "Haircut"
        )
        Reminder(
          id: UUID(2),
          dueDate: Date(),
          notes: "Ask about diet",
          priority: .high,
          remindersListID: UUID(0),
          title: "Doctor appointment"
        )
        Reminder(
          id: UUID(3),
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 190),
          isCompleted: true,
          remindersListID: UUID(0),
          title: "Take a walk"
        )
        Reminder(
          id: UUID(4),
          dueDate: Date(),
          remindersListID: UUID(0),
          title: "Buy concert tickets"
        )
        Reminder(
          id: UUID(5),
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 2),
          isFlagged: true,
          priority: .high,
          remindersListID: UUID(1),
          title: "Pick up kids from school"
        )
        Reminder(
          id: UUID(6),
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isCompleted: true,
          priority: .low,
          remindersListID: UUID(1),
          title: "Get laundry"
        )
        Reminder(
          id: UUID(7),
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 4),
          isCompleted: false,
          priority: .high,
          remindersListID: UUID(1),
          title: "Take out trash"
        )
        Reminder(
          id: UUID(8),
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 2),
          notes: """
            Status of tax return
            Expenses for next year
            Changing payroll company
            """,
          remindersListID: UUID(2),
          title: "Call accountant"
        )
        Reminder(
          id: UUID(9),
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isCompleted: true,
          priority: .medium,
          remindersListID: UUID(2),
          title: "Send weekly emails"
        )

        Tag(id: UUID(0), title: "car")
        Tag(id: UUID(1), title: "kids")
        Tag(id: UUID(2), title: "someday")
        Tag(id: UUID(3), title: "optional")
        Tag(id: UUID(4), title: "social")
        Tag(id: UUID(5), title: "night")
        Tag(id: UUID(6), title: "adulting")

        ReminderTag(id: UUID(), reminderID: UUID(0), tagID: UUID(2))
        ReminderTag(id: UUID(), reminderID: UUID(0), tagID: UUID(3))
        ReminderTag(id: UUID(), reminderID: UUID(0), tagID: UUID(6))
        ReminderTag(id: UUID(), reminderID: UUID(1), tagID: UUID(2))
        ReminderTag(id: UUID(), reminderID: UUID(1), tagID: UUID(3))
        ReminderTag(id: UUID(), reminderID: UUID(2), tagID: UUID(6))
        ReminderTag(id: UUID(), reminderID: UUID(3), tagID: UUID(0))
        ReminderTag(id: UUID(), reminderID: UUID(3), tagID: UUID(1))
      }
    }
  }
#endif
