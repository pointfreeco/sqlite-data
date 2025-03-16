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
extension Reminder.Columns {
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

func appDatabase(inMemory: Bool = false) throws -> any DatabaseWriter {
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
    try db.create(table: RemindersList.tableName) { table in
      table.autoIncrementedPrimaryKey("id")
      table.column("color", .integer).defaults(to: 0x4a99ef).notNull()
      table.column("name", .text).notNull()
    }
  }
  migrator.registerMigration("Add reminders table") { db in
    try db.create(table: Reminder.tableName) { table in
      table.autoIncrementedPrimaryKey("id")
      table.column("date", .date)
      table.column("isCompleted", .boolean).defaults(to: false).notNull()
      table.column("isFlagged", .boolean).defaults(to: false).notNull()
      table.column("remindersListID", .integer)
        .references(RemindersList.tableName, column: "id", onDelete: .cascade)
        .notNull()
      table.column("notes", .text).notNull()
      table.column("priority", .integer)
      table.column("title", .text).notNull()
    }
    try db.create(indexOn: Reminder.tableName, columns: [Reminder.columns.remindersListID.name])
  }
  migrator.registerMigration("Add tags table") { db in
    try db.create(table: Tag.tableName) { table in
      table.autoIncrementedPrimaryKey("id")
      table.column("name", .text).notNull().collate(.nocase).unique()
    }
    try db.create(table: ReminderTag.tableName) { table in
      table.column("reminderID", .integer).notNull()
        .references(Reminder.tableName, column: "id", onDelete: .cascade)
      table.column("tagID", .integer).notNull()
        .references(Tag.tableName, column: "id", onDelete: .cascade)
    }
    try db.create(indexOn: ReminderTag.tableName, columns: [ReminderTag.columns.reminderID.name])
    try db.create(indexOn: ReminderTag.tableName, columns: [ReminderTag.columns.tagID.name])
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
      // TODO: Support this?
//      _ = try Reminder.Draft(
//        date: Date(),
//        notes: "Milk\nEggs\nApples\nOatmeal\nSpinach",
//        remindersListID: 1,
//        title: "Groceries"
//      )
//      .inserted(self)
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
      try Tag.insert(\.name) { "car"; "kids"; "someday"; "optional" }.execute(self)
      try ReminderTag.insert {
        ($0.reminderID, $0.tagID)
      } values: {
        (1, 3)
        (1, 4)
        (2, 3)
        (2, 4)
        (4, 1)
        (4, 2)
      }
      .execute(self)
    }
  }
#endif
