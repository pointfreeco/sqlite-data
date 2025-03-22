import Foundation
import GRDB
import IssueReporting
import SharingGRDB
import StructuredQueriesGRDB

@Table
struct RemindersList: Codable, Hashable, Identifiable {
  var id: Int64
  var color = 0x4a99ef
  var name = ""
}

@Table
struct Reminder: Codable, Equatable, Identifiable {
  var id: Int64
  @Column(as: Date.ISO8601Representation?.self)
  var date: Date?
  var isCompleted = false
  var isFlagged = false
  var notes = ""
  var priority: Int?
  var remindersListID: Int64
  var title = ""
  static func searching(_ text: String) -> Where<Reminder> {
    Self.where {
      $0.title.collate(.nocase).contains(text)
        || $0.notes.collate(.nocase).contains(text)
    }
  }
  static let incomplete = Self.where { !$0.isCompleted }
}
extension Reminder.TableColumns {
  var isPastDue: some QueryExpression<Bool> {
    !isCompleted && #sql("coalesce(\(date), date('now')) < date('now')")
  }
}

@Table
struct Tag: Codable {
  var id: Int64
  var name = ""
}

@Table("remindersTags")
struct ReminderTag: Codable {
  var reminderID: Int64
  var tagID: Int64
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
        "color" INTEGER NOT NULL DEFAULT '\(raw: 0x4a99ef)',
        "name" TEXT NOT NULL
      )
      """
    )
    .execute(db)
  }
  migrator.registerMigration("Add reminders table") { db in
    try #sql(
      """
      CREATE TABLE "reminders" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "date" TEXT,
        "isCompleted" INTEGER NOT NULL DEFAULT 0,
        "isFlagged" INTEGER NOT NULL DEFAULT 0,
        "remindersListID" INTEGER NOT NULL,
        "notes" TEXT NOT NULL,
        "priority" INTEGER,
        "title" TEXT NOT NULL,

        FOREIGN KEY("remindersListID") REFERENCES "remindersLists"("id") ON DELETE CASCADE
      )
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE INDEX "reminders_remindersListID" ON "reminders"("remindersListID")
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
      )
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
      )
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE INDEX "remindersTags_reminderID" ON "remindersTags"("reminderID")
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE INDEX "remindersTags_tagID" ON "remindersTags"("tagID")
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
      try RemindersList.insert {
        ($0.color, $0.name)
      } values: {
        (color: 0x4a99ef, name: "Personal")
        (color: 0xed8935, name: "Family")
        (color: 0xb25dd3, name: "Business")
      }
      .execute(self)
    }

    func createDebugReminders() throws {
      try Reminder.insert([
        Reminder.Draft(
          date: Date(),
          notes: "Milk\nEggs\nApples\nOatmeal\nSpinach",
          remindersListID: 1,
          title: "Groceries"
        ),
        Reminder.Draft(
          date: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isFlagged: true,
          remindersListID: 1,
          title: "Haircut"
        ),
        Reminder.Draft(
          date: Date(),
          notes: "Ask about diet",
          priority: 3,
          remindersListID: 1,
          title: "Doctor appointment"
        ),
        Reminder.Draft(
          date: Date().addingTimeInterval(-60 * 60 * 24 * 190),
          isCompleted: true,
          remindersListID: 1,
          title: "Take a walk"
        ),
        Reminder.Draft(
          date: Date(),
          remindersListID: 1,
          title: "Buy concert tickets"
        ),
        Reminder.Draft(
          date: Date().addingTimeInterval(60 * 60 * 24 * 2),
          isFlagged: true,
          priority: 3,
          remindersListID: 2,
          title: "Pick up kids from school"
        ),
        Reminder.Draft(
          date: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isCompleted: true,
          priority: 1,
          remindersListID: 2,
          title: "Get laundry"
        ),
        Reminder.Draft(
          date: Date().addingTimeInterval(60 * 60 * 24 * 4),
          isCompleted: false,
          priority: 3,
          remindersListID: 2,
          title: "Take out trash"
        ),
        Reminder.Draft(
          date: Date().addingTimeInterval(60 * 60 * 24 * 2),
          notes: """
            Status of tax return
            Expenses for next year
            Changing payroll company
            """,
          remindersListID: 3,
          title: "Call accountant"
        ),
        Reminder.Draft(
          date: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isCompleted: true,
          priority: 2,
          remindersListID: 3,
          title: "Send weekly emails"
        ),
      ])
      .execute(self)
    }

    func createDebugTags() throws {
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
