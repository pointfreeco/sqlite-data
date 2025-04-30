import Foundation
import IssueReporting
import OSLog
import SharingGRDB
import SwiftUI

@Table
struct RemindersList: Hashable, Identifiable {
  var id: Int
  @Column(as: Color.HexRepresentation.self)
  var color = Color(red: 0x4a / 255, green: 0x99 / 255, blue: 0xef / 255)
  var title = ""
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
  var id: Int
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
  var reminderID: Reminder.ID
  var tagID: Tag.ID
  var id: Self { self }
}

func appDatabase() throws -> any DatabaseWriter {
  let database: any DatabaseWriter
  var configuration = Configuration()
  configuration.foreignKeysEnabled = true
  configuration.prepareDatabase { db in
    #if DEBUG
      db.trace(options: .profile) {
        logger.debug("\($0.expandedDescription)")
      }
    #endif
  }
  @Dependency(\.context) var context
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
  migrator.registerMigration("Add reminders lists table") { db in
    try #sql(
      """
      CREATE TABLE "remindersLists" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "color" INTEGER NOT NULL DEFAULT \(raw: 0x4a99_ef00),
        "title" TEXT NOT NULL
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
        "title" TEXT NOT NULL COLLATE NOCASE UNIQUE
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
  #if DEBUG && targetEnvironment(simulator)
    if context != .test {
      migrator.registerMigration("Seed sample data") { db in
        try db.seedSampleData()
      }
    }
  #endif
  try migrator.migrate(database)

  return database
}

private let logger = Logger(subsystem: "Reminders", category: "Database")

#if DEBUG
  extension Database {
    func seedSampleData() throws {
      try seed {
        RemindersList(
          id: 1,
          color: Color(red: 0x4a / 255, green: 0x99 / 255, blue: 0xef / 255),
          title: "Personal"
        )
        RemindersList(
          id: 2,
          color: Color(red: 0xed / 255, green: 0x89 / 255, blue: 0x35 / 255),
          title: "Family"
        )
        RemindersList(
          id: 3,
          color: Color(red: 0xb2 / 255, green: 0x5d / 255, blue: 0xd3 / 255),
          title: "Business"
        )
        Reminder(
          id: 1,
          notes: "Milk\nEggs\nApples\nOatmeal\nSpinach",
          remindersListID: 1,
          title: "Groceries"
        )
        Reminder(
          id: 2,
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isFlagged: true,
          remindersListID: 1,
          title: "Haircut"
        )
        Reminder(
          id: 3,
          dueDate: Date(),
          notes: "Ask about diet",
          priority: .high,
          remindersListID: 1,
          title: "Doctor appointment"
        )
        Reminder(
          id: 4,
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 190),
          isCompleted: true,
          remindersListID: 1,
          title: "Take a walk"
        )
        Reminder(
          id: 5,
          dueDate: Date(),
          remindersListID: 1,
          title: "Buy concert tickets"
        )
        Reminder(
          id: 6,
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 2),
          isFlagged: true,
          priority: .high,
          remindersListID: 2,
          title: "Pick up kids from school"
        )
        Reminder(
          id: 7,
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isCompleted: true,
          priority: .low,
          remindersListID: 2,
          title: "Get laundry"
        )
        Reminder(
          id: 8,
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 4),
          isCompleted: false,
          priority: .high,
          remindersListID: 2,
          title: "Take out trash"
        )
        Reminder(
          id: 9,
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 2),
          notes: """
            Status of tax return
            Expenses for next year
            Changing payroll company
            """,
          remindersListID: 3,
          title: "Call accountant"
        )
        Reminder(
          id: 10,
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isCompleted: true,
          priority: .medium,
          remindersListID: 3,
          title: "Send weekly emails"
        )
        Tag(id: 1, title: "car")
        Tag(id: 2, title: "kids")
        Tag(id: 3, title: "someday")
        Tag(id: 4, title: "optional")
        Tag(id: 5, title: "social")
        Tag(id: 6, title: "night")
        Tag(id: 7, title: "adulting")
        ReminderTag(reminderID: 1, tagID: 3)
        ReminderTag(reminderID: 1, tagID: 4)
        ReminderTag(reminderID: 1, tagID: 7)
        ReminderTag(reminderID: 2, tagID: 3)
        ReminderTag(reminderID: 2, tagID: 4)
        ReminderTag(reminderID: 3, tagID: 7)
        ReminderTag(reminderID: 4, tagID: 1)
        ReminderTag(reminderID: 4, tagID: 2)
      }
    }
  }
#endif
