import Foundation
import GRDB
import IssueReporting
import SharingGRDB
import StructuredQueriesGRDB

@Table("remindersLists")
struct RemindersList: Codable, FetchableRecord, Hashable, Identifiable, MutablePersistableRecord {
  static let databaseTableName = "remindersLists"
  var id: Int64
  var color = 0x4a99ef
  var name = ""
}

@Table("reminders")
struct Reminder: Codable, Equatable, FetchableRecord, Identifiable, MutablePersistableRecord {
  static let databaseTableName = "reminders"

  var id: Int64
  @Column(as: .iso8601)
  var date: Date?
  var isCompleted = false
  var isFlagged = false
  var listID: Int64 // TODO: rename to remindersListID?
  var notes = ""
  var priority: Int?
  var title = ""

  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }

  static func searching(_ text: String) -> Where<Reminder> {
    Self.where {
      $0.title.collate(.nocase).contains(text)
      || $0.notes.collate(.nocase).contains(text)
    }
  }
}
extension Reminder.Columns {
  var isPastDue: some QueryExpression<Bool> {
    isCompleted && .raw("coalesce(\(date), date('now')) < date('now')")
  }
}

@Table("tags")
struct Tag: Codable, FetchableRecord, MutablePersistableRecord {
  static let databaseTableName = "tags"

  var id: Int64
  var name = ""

  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}

@Table("remindersTags")
struct ReminderTag: Codable, FetchableRecord, MutablePersistableRecord {
  static let databaseTableName = "remindersTags"

  // TODO: Both of these should be non-optional even on 'main'
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
    try db.create(table: RemindersList.name) { table in
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
        .references(RemindersList.name, column: "id", onDelete: .cascade)
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
//        listID: 1,
//        notes: "Milk\nEggs\nApples\nOatmeal\nSpinach",
//        title: "Groceries"
//      )
//      .inserted(self)
      try Reminder.insert([
        Reminder.Draft(
          date: Date(),
          listID: 1,
          notes: "Milk\nEggs\nApples\nOatmeal\nSpinach",
          title: "Groceries"
        ),
        Reminder.Draft(
          date: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isFlagged: true,
          listID: 1,
          title: "Haircut"
        ),
        Reminder.Draft(
          date: Date(),
          listID: 1,
          notes: "Ask about diet",
          priority: 3,
          title: "Doctor appointment"
        ),
        Reminder.Draft(
          date: Date().addingTimeInterval(-60 * 60 * 24 * 190),
          isCompleted: true,
          listID: 1,
          title: "Take a walk"
        ),
        Reminder.Draft(
          date: Date(),
          listID: 1,
          title: "Buy concert tickets"
        ),
        Reminder.Draft(
          date: Date().addingTimeInterval(60 * 60 * 24 * 2),
          isFlagged: true,
          listID: 2,
          priority: 3,
          title: "Pick up kids from school"
        ),
        Reminder.Draft(
          date: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isCompleted: true,
          listID: 2,
          priority: 1,
          title: "Get laundry"
        ),
        Reminder.Draft(
          date: Date().addingTimeInterval(60 * 60 * 24 * 4),
          isCompleted: false,
          listID: 2,
          priority: 3,
          title: "Take out trash"
        ),
        Reminder.Draft(
          date: Date().addingTimeInterval(60 * 60 * 24 * 2),
          listID: 3,
          notes: """
            Status of tax return
            Expenses for next year
            Changing payroll company
            """,
          title: "Call accountant"
        ),
        Reminder.Draft(
          date: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isCompleted: true,
          listID: 3,
          priority: 2,
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
