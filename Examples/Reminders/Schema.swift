import Foundation
import GRDB
import IssueReporting
import SharingGRDB

struct RemindersList: Codable, FetchableRecord, Hashable, Identifiable, MutablePersistableRecord {
  static let databaseTableName = "remindersLists"

  var id: Int64?
  var color = 0x4a99ef
  var name = ""

  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}

struct Reminder: Codable, Equatable, FetchableRecord, Identifiable, MutablePersistableRecord {
  static let databaseTableName = "reminders"

  var id: Int64?
  var date: Date?
  var isCompleted = false
  var isFlagged = false
  var listID: Int64
  var notes = ""
  var priority: Int?
  var title = ""

  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}

struct Tag: Codable, FetchableRecord, MutablePersistableRecord {
  static let databaseTableName = "tags"

  var id: Int64?
  var name = ""

  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}

struct ReminderTag: Codable, FetchableRecord, MutablePersistableRecord {
  static let databaseTableName = "remindersTags"

  var reminderID: Int64?
  var tagID: Int64?
}

func appDatabase(inMemory: Bool) throws -> any DatabaseWriter {
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
  if inMemory {
    database = try DatabaseQueue(configuration: configuration)
  } else {
    let path = URL.documentsDirectory.appending(component: "db.sqlite").path()
    print("open", path)
    database = try DatabasePool(path: path, configuration: configuration)
  }
  var migrator = DatabaseMigrator()
  #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
  #endif
  migrator.registerMigration("Add reminders lists table") { db in
    try db.create(table: RemindersList.databaseTableName) { table in
      table.autoIncrementedPrimaryKey("id")
      table.column("color", .integer).defaults(to: 0x4a99ef).notNull()
      table.column("name", .text).notNull()
    }
  }
  migrator.registerMigration("Add reminders table") { db in
    try db.create(table: Reminder.databaseTableName) { table in
      table.autoIncrementedPrimaryKey("id")
      table.column("date", .date)
      table.column("isCompleted", .boolean).defaults(to: false).notNull()
      table.column("isFlagged", .boolean).defaults(to: false).notNull()
      table.column("listID", .integer)
        .references(RemindersList.databaseTableName, column: "id", onDelete: .cascade)
        .notNull()
      table.column("notes", .text).notNull()
      table.column("priority", .integer)
      table.column("title", .text).notNull()
    }
  }
  migrator.registerMigration("Add tags table") { db in
    try db.create(table: Tag.databaseTableName) { table in
      table.autoIncrementedPrimaryKey("id")
      table.column("name", .text).notNull().collate(.nocase).unique()
    }
    try db.create(table: ReminderTag.databaseTableName) { table in
      table.column("reminderID", .integer).notNull()
        .references(Reminder.databaseTableName, column: "id", onDelete: .cascade)
      table.column("tagID", .integer).notNull()
        .references(Tag.databaseTableName, column: "id", onDelete: .cascade)
    }
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
      _ = try RemindersList(color: 0x4a99ef, name: "Personal").inserted(self)
      _ = try RemindersList(color: 0xed8935, name: "Family").inserted(self)
      _ = try RemindersList(color: 0xb25dd3, name: "Business").inserted(self)
    }

    func createDebugReminders() throws {
      _ = try Reminder(
        date: Date(),
        listID: 1,
        notes: "Milk\nEggs\nApples\nOatmeal\nSpinach",
        title: "Groceries"
      )
      .inserted(self)
      _ = try Reminder(
        date: Date().addingTimeInterval(-60 * 60 * 24 * 2),
        isFlagged: true,
        listID: 1,
        title: "Haircut"
      )
      .inserted(self)
      _ = try Reminder(
        date: Date(),
        listID: 1,
        notes: "Ask about diet",
        priority: 3,
        title: "Doctor appointment"
      )
      .inserted(self)
      _ = try Reminder(
        date: Date().addingTimeInterval(-60 * 60 * 24 * 190),
        isCompleted: true,
        listID: 1,
        title: "Take a walk"
      )
      .inserted(self)
      _ = try Reminder(
        date: Date(),
        listID: 1,
        title: "Buy concert tickets"
      )
      .inserted(self)
      _ = try Reminder(
        date: Date().addingTimeInterval(60 * 60 * 24 * 2),
        isFlagged: true,
        listID: 2,
        priority: 3,
        title: "Pick up kids from school"
      )
      .inserted(self)
      _ = try Reminder(
        date: Date().addingTimeInterval(-60 * 60 * 24 * 2),
        isCompleted: true,
        listID: 2,
        priority: 1,
        title: "Get laundry"
      )
      .inserted(self)
      _ = try Reminder(
        date: Date().addingTimeInterval(60 * 60 * 24 * 4),
        isCompleted: false,
        listID: 2,
        priority: 3,
        title: "Take out trash"
      )
      .inserted(self)
      _ = try Reminder(
        date: Date().addingTimeInterval(60 * 60 * 24 * 2),
        listID: 3,
        notes: """
          Status of tax return
          Expenses for next year
          Changing payroll company
          """,
        title: "Call accountant"
      )
      .inserted(self)
      _ = try Reminder(
        date: Date().addingTimeInterval(-60 * 60 * 24 * 2),
        isCompleted: true,
        listID: 3,
        priority: 2,
        title: "Send weekly emails"
      )
      .inserted(self)
    }

    func createDebugTags() throws {
      _ = try Tag(name: "car").inserted(self)
      _ = try Tag(name: "kids").inserted(self)
      _ = try Tag(name: "someday").inserted(self)
      _ = try Tag(name: "optional").inserted(self)
      _ = try ReminderTag(reminderID: 1, tagID: 3).inserted(self)
      _ = try ReminderTag(reminderID: 1, tagID: 4).inserted(self)
      _ = try ReminderTag(reminderID: 2, tagID: 3).inserted(self)
      _ = try ReminderTag(reminderID: 2, tagID: 4).inserted(self)
      _ = try ReminderTag(reminderID: 4, tagID: 1).inserted(self)
      _ = try ReminderTag(reminderID: 4, tagID: 2).inserted(self)
    }
  }
#endif
