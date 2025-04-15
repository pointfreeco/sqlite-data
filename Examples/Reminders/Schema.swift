import Foundation
import GRDB
import IssueReporting
import SharingGRDB
import StructuredQueriesGRDB
import SwiftUI

@Table
struct RemindersList: Hashable, Identifiable {
  var id: Int
  @Column(as: Color.HexRepresentation.self)
  var color = Color(red: 0x4a / 255, green: 0x99 / 255, blue: 0xef / 255)
  var name = ""
}

@Table
struct Reminder: Equatable, Identifiable {
  var id: Int
  @Column(as: Date.ISO8601Representation?.self)
  var dueDate: Date?
  var isCompleted = false
  var isFlagged = false
  var notes = ""
  var priority: Priority?
  var remindersListID: Int
  var title = ""
  static let incomplete = Self.where { !$0.isCompleted }
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
}

enum Priority: Int, QueryBindable {
  case low = 1
  case medium
  case high
}

@Table
struct Tag {
  var id: Int
  var name = ""
}

@Table("remindersTags")
struct ReminderTag {
  var reminderID: Int
  var tagID: Int
}

protocol VirtualTable {}

extension StructuredQueries.TableDefinition where QueryValue: VirtualTable {
  var rank: some QueryExpression<Double> {
    SQLQueryExpression(
      """
      \(QueryValue.self)."rank"
      """
    )
  }

  func match(_ pattern: some QueryExpression<String>) -> some QueryExpression<Bool> {
    SQLQueryExpression(
      """
      (\(QueryValue.self) MATCH \(pattern))
      """
    )
  }

  func highlight<Value>(
    _ column: KeyPath<Self, StructuredQueries.TableColumn<QueryValue, Value>>,
    _ open: String,
    _ close: String
  ) -> some QueryExpression<String> {
    let column = self[keyPath: column]
    let offset = Self.allColumns.firstIndex { $0.name == column.name }!
    return SQLQueryExpression(
      """
      highlight(\
      \(QueryValue.self), \
      \(raw: offset),
      \(quote: open, delimiter: .text), \
      \(quote: close, delimiter: .text)\
      )
      """
    )
  }
}

@Table
struct ReminderText: VirtualTable {
  @Column(primaryKey: true)
  let reminderID: Int
  let reminderNotes: String
  let reminderTags: String
  let reminderTitle: String
  let remindersListName: String
}

func appDatabase() throws -> any DatabaseWriter {
  let database: any DatabaseWriter
  var configuration = Configuration()
  configuration.foreignKeysEnabled = true
  configuration.prepareDatabase { db in
    #if DEBUG
      db.trace(options: .profile) {
        print($0.expandedDescription)
      }
    #endif
  }
  @Dependency(\.context) var context
  if context == .live {
    let path = URL.documentsDirectory.appending(component: "db.sqlite").path()
    print("open", path)
    database = try DatabasePool(path: path, configuration: configuration)
  } else {
    database = try DatabaseQueue(configuration: configuration)
  }
  var migrator = DatabaseMigrator()
  #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
  #endif
  migrator.registerMigration("Add reminders lists table") { db in
    try #sql(
      """
      CREATE TABLE "remindersLists" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "color" INTEGER NOT NULL DEFAULT \(raw: 0x4a99ef00),
        "name" TEXT NOT NULL
      ) STRICT
      """
    )
    .execute(db)
  }
  migrator.registerMigration("Add reminders table") { db in
    try #sql(
      """
      CREATE TABLE "reminders" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "dueDate" TEXT,
        "isCompleted" INTEGER NOT NULL DEFAULT 0,
        "isFlagged" INTEGER NOT NULL DEFAULT 0,
        "notes" TEXT,
        "priority" INTEGER,
        "remindersListID" INTEGER NOT NULL,
        "title" TEXT NOT NULL,

        FOREIGN KEY("remindersListID") REFERENCES "remindersLists"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
  }
  migrator.registerMigration("Add tags table") { db in
    try #sql(
      """
      CREATE TABLE "tags" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "name" TEXT NOT NULL COLLATE NOCASE UNIQUE
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "remindersTags" (
        "reminderID" INTEGER NOT NULL,
        "tagID" INTEGER NOT NULL,

        FOREIGN KEY("reminderID") REFERENCES "reminders"("id") ON DELETE CASCADE,
        FOREIGN KEY("tagID") REFERENCES "tags"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
  }
  migrator.registerMigration("Add reminders FTS") { db in
    try #sql(
      """
      CREATE VIRTUAL TABLE "reminderTexts" USING fts5(
        "reminderID",
        "reminderNotes",
        "reminderTags",
        "reminderTitle",
        "remindersListID",
        "remindersListName",
        tokenize = 'trigram'
      )
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TRIGGER "remindersInserts" AFTER INSERT ON "reminders" BEGIN
        INSERT INTO "reminderTexts"
          (
            "reminderID",
            "reminderNotes",
            "reminderTags",
            "reminderTitle",
            "remindersListID",
            "remindersListName"
          )
        SELECT 
          "reminders"."id",
          "reminders"."notes",
          '',
          "reminders"."title",
          "remindersLists"."id",
          "remindersLists"."name"
        FROM "reminders"
        JOIN "remindersLists" ON "reminders"."remindersListID" = "remindersLists"."id"
        WHERE "reminders"."id" = "new"."id";
      END
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TRIGGER "remindersUpdates" AFTER UPDATE OF "notes", "title" ON "reminders" BEGIN
        UPDATE "reminderTexts" SET
          "reminderID" = "new"."id",
          "reminderNotes" = "new"."notes",
          "reminderTitle" = "new"."title"
        WHERE "reminderTexts"."reminderID" = "old"."id";
      END
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TRIGGER "remindersDeletes" AFTER DELETE ON "reminders" BEGIN
        DELETE FROM "reminderTexts" WHERE "reminderID" = "old"."id";
      END
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TRIGGER "remindersListsUpdates" AFTER UPDATE OF "name" ON "remindersLists" BEGIN
        UPDATE "reminderTexts" SET
          "remindersListID" = "new"."id",
          "remindersListName" = "new"."name"
        WHERE "reminderTexts"."remindersListID" = "old"."id";
      END
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TRIGGER "remindersTagsInserts" AFTER INSERT ON "remindersTags" BEGIN
        UPDATE "reminderTexts" SET "reminderTags" = (
          SELECT group_concat("tags"."name", ' ') FROM "tags"
          JOIN "remindersTags" ON "tags"."id" = "remindersTags"."tagID"
          WHERE "remindersTags"."reminderID" = "reminderTexts"."reminderID"
        )
        WHERE "reminderTexts"."reminderID" = "new"."reminderID";
      END
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TRIGGER "remindersTagsDeletes" AFTER DELETE ON "remindersTags" BEGIN
        UPDATE "reminderTexts" SET "reminderTags" = (
          SELECT group_concat("tags"."name", ' ') FROM "tags"
          JOIN "remindersTags" ON "tags"."id" = "remindersTags"."tagID"
          WHERE "remindersTags"."reminderID" = "reminderTexts"."reminderID"
        )
        WHERE "reminderTexts"."reminderID" = "old"."reminderID";
      END
      """
    )
    .execute(db)
  }
  #if DEBUG
    migrator.registerMigration("Add mock data") { db in
      try db.createMockData()
    }
  #endif
  try migrator.migrate(database)

  return database
}

#if DEBUG
  extension Database {
    func createMockData() throws {
      try createDebugRemindersLists()
      try createDebugReminders()
      try createDebugTags()
    }

    func createDebugRemindersLists() throws {
      try RemindersList.delete().execute(self)
      try RemindersList.insert {
        RemindersList.Draft(
          color: Color(red: 0x4a / 255, green: 0x99 / 255, blue: 0xef / 255),
          name: "Personal"
        )
        RemindersList.Draft(
          color: Color(red: 0xed / 255, green: 0x89 / 255, blue: 0x35 / 255),
          name: "Family"
        )
        RemindersList.Draft(
          color: Color(red: 0xb2 / 255, green: 0x5d / 255, blue: 0xd3 / 255),
          name: "Business"
        )
      }
      .execute(self)
    }

    func createDebugReminders() throws {
      try Reminder.delete().execute(self)
      try Reminder.insert {
        Reminder.Draft(
          notes: "Milk\nEggs\nApples\nOatmeal\nSpinach",
          remindersListID: 1,
          title: "Groceries"
        )
        Reminder.Draft(
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isFlagged: true,
          remindersListID: 1,
          title: "Haircut"
        )
        Reminder.Draft(
          dueDate: Date(),
          notes: "Ask about diet",
          priority: .high,
          remindersListID: 1,
          title: "Doctor appointment"
        )
        Reminder.Draft(
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 190),
          isCompleted: true,
          remindersListID: 1,
          title: "Take a walk"
        )
        Reminder.Draft(
          dueDate: Date(),
          remindersListID: 1,
          title: "Buy concert tickets"
        )
        Reminder.Draft(
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 2),
          isFlagged: true,
          priority: .high,
          remindersListID: 2,
          title: "Pick up kids from school"
        )
        Reminder.Draft(
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isCompleted: true,
          priority: .low,
          remindersListID: 2,
          title: "Get laundry"
        )
        Reminder.Draft(
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 4),
          isCompleted: false,
          priority: .high,
          remindersListID: 2,
          title: "Take out trash"
        )
        Reminder.Draft(
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 2),
          notes: """
            Status of tax return
            Expenses for next year
            Changing payroll company
            """,
          remindersListID: 3,
          title: "Call accountant"
        )
        Reminder.Draft(
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isCompleted: true,
          priority: .medium,
          remindersListID: 3,
          title: "Send weekly emails"
        )
      }
      .execute(self)
    }

    func createDebugTags() throws {
      try ReminderTag.delete().execute(self)
      try Tag.delete().execute(self)
      try Tag.insert(\.name) {
        "car"
        "kids"
        "someday"
        "optional"
        "social"
        "night"
        "adulting"
      }
      .execute(self)
      try ReminderTag.insert {
        ($0.reminderID, $0.tagID)
      } values: {
        (1, 3)
        (1, 4)
        (1, 7)
        (2, 3)
        (2, 4)
        (3, 7)
        (4, 1)
        (4, 2)
      }
      .execute(self)
    }
  }
#endif
