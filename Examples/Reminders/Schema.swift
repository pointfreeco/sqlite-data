import Dependencies
import Foundation
import IssueReporting
import OSLog
import SQLiteData
import SwiftUI

@Table
struct RemindersList: Hashable, Identifiable {
  let id: UUID
  @Column(as: Color.HexRepresentation.self)
  var color: Color = Self.defaultColor
  var position = 0
  var title = ""

  static var defaultColor: Color { Color(red: 0x4a / 255, green: 0x99 / 255, blue: 0xef / 255) }
  static var defaultTitle: String { "Personal" }
}

extension RemindersList.Draft: Identifiable {}

@Table
struct RemindersListAsset: Hashable, Identifiable {
  @Column(primaryKey: true)
  let remindersListID: RemindersList.ID
  var coverImage: Data?
  var id: RemindersList.ID { remindersListID }
}

@Table
struct Reminder: Hashable, Identifiable {
  let id: UUID
  var dueDate: Date?
  var isCompleted = false
  var isFlagged = false
  var notes = ""
  var position = 0
  var priority: Priority?
  var remindersListID: RemindersList.ID
  var title = ""
}

extension Reminder.Draft: Identifiable {}

@Table
struct Tag: Hashable, Identifiable {
  @Column(primaryKey: true)
  var title: String
  var id: String { title }
}

enum Priority: Int, QueryBindable {
  case low = 1
  case medium
  case high
}

extension Reminder {
  static let incomplete = Self.where { !$0.isCompleted }
  static let withTags = group(by: \.id)
    .leftJoin(ReminderTag.all) { $0.id.eq($1.reminderID) }
    .leftJoin(Tag.all) { $1.tagID.eq($2.primaryKey) }
}

extension Reminder.TableColumns {
  var isPastDue: some QueryExpression<Bool> {
    @Dependency(\.date.now) var now
    return !isCompleted && #sql("coalesce(date(\(dueDate)) < date(\(now)), 0)")
  }
  var isToday: some QueryExpression<Bool> {
    @Dependency(\.date.now) var now
    return !isCompleted && #sql("coalesce(date(\(dueDate)) = date(\(now)), 0)")
  }
  var isScheduled: some QueryExpression<Bool> {
    !isCompleted && dueDate.isNot(nil)
  }
}

extension Tag {
  static let withReminders = group(by: \.primaryKey)
    .leftJoin(ReminderTag.all) { $0.primaryKey.eq($1.tagID) }
    .leftJoin(Reminder.all) { $1.reminderID.eq($2.id) }
}

@Table("remindersTags")
struct ReminderTag: Hashable, Identifiable {
  let id: UUID
  var reminderID: Reminder.ID
  var tagID: Tag.ID
}

@Table @Selection
struct ReminderText: FTS5 {
  let rowid: Int
  let title: String
  let notes: String
  let tags: String
}

extension DependencyValues {
  mutating func bootstrapDatabase() throws {
    defaultDatabase = try Reminders.appDatabase()
    defaultSyncEngine = try SyncEngine(
      for: defaultDatabase,
      tables: RemindersList.self,
      RemindersListAsset.self,
      Reminder.self,
      Tag.self,
      ReminderTag.self
    )
  }
}

func appDatabase() throws -> any DatabaseWriter {
  @Dependency(\.context) var context
  let database: any DatabaseWriter
  var configuration = Configuration()
  configuration.foreignKeysEnabled = true
  configuration.prepareDatabase { db in
    try db.attachMetadatabase()
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
  if context == .preview {
    database = try DatabaseQueue(configuration: configuration)
  } else {
    let path =
      context == .live
      ? URL.documentsDirectory.appending(component: "db.sqlite").path()
      : URL.temporaryDirectory.appending(component: "\(UUID().uuidString)-db.sqlite").path()
    logger.debug(
      """
      App database:
      open "\(path)"
      """
    )
    database = try DatabasePool(path: path, configuration: configuration)
  }
  var migrator = DatabaseMigrator()
  #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
  #endif
  migrator.registerMigration("Create initial tables") { db in
    let defaultListColor = Color.HexRepresentation(queryOutput: RemindersList.defaultColor).hexValue
    try #sql(
      """
      CREATE TABLE "remindersLists" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "color" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT \(raw: defaultListColor ?? 0),
        "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
        "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "remindersListAssets" (
        "remindersListID" TEXT PRIMARY KEY NOT NULL 
          REFERENCES "remindersLists"("id") ON DELETE CASCADE,
        "coverImage" BLOB
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "reminders" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "dueDate" TEXT,
        "isCompleted" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
        "isFlagged" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
        "notes" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
        "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
        "priority" INTEGER,
        "remindersListID" TEXT NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE,
        "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "tags" (
        "title" TEXT COLLATE NOCASE PRIMARY KEY NOT NULL
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "remindersTags" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "reminderID" TEXT NOT NULL REFERENCES "reminders"("id") ON DELETE CASCADE,
        "tagID" TEXT NOT NULL REFERENCES "tags"("title") ON DELETE CASCADE ON UPDATE CASCADE
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE VIRTUAL TABLE "reminderTexts" USING fts5(
        "title",
        "notes",
        "tags",
        tokenize = 'trigram'
      )
      """
    )
    .execute(db)
  }

  try migrator.migrate(database)

  try database.write { db in
    if context == .preview {
      try db.seedSampleData()
    }

    try RemindersList.createTemporaryTrigger(
      after: .insert { new in
        RemindersList
          .find(new.id)
          .update { $0.position = RemindersList.select { ($0.position.max() ?? -1) + 1 } }
      }
    )
    .execute(db)

    try Reminder.createTemporaryTrigger(
      after: .insert { new in
        Reminder
          .find(new.id)
          .update { $0.position = Reminder.select { ($0.position.max() ?? -1) + 1 } }
      }
    )
    .execute(db)

    try RemindersList.createTemporaryTrigger(
      after: .delete { _ in
        RemindersList.insert {
          RemindersList.Draft(
            color: RemindersList.defaultColor,
            title: RemindersList.defaultTitle
          )
        }
      } when: { _ in
        !RemindersList.exists()
      }
    )
    .execute(db)

    try Reminder.createTemporaryTrigger(
      after: .insert { new in
        ReminderText.insert {
          ReminderText.Columns(
            rowid: new.rowid,
            title: new.title,
            notes: new.notes.replace("\n", " "),
            tags: ""
          )
        }
      }
    )
    .execute(db)

    try Reminder.createTemporaryTrigger(
      after: .update {
        ($0.title, $0.notes)
      } forEachRow: { _, new in
        ReminderText
          .where { $0.rowid.eq(new.rowid) }
          .update {
            $0.title = new.title
            $0.notes = new.notes.replace("\n", " ")
          }
      }
    )
    .execute(db)

    try Reminder.createTemporaryTrigger(
      after: .delete { old in
        ReminderText
          .where { $0.rowid.eq(old.rowid) }
          .delete()
      }
    )
    .execute(db)

    func updateReminderTextTags(
      for reminderID: some QueryExpression<Reminder.ID>
    ) -> UpdateOf<ReminderText> {
      ReminderText
        .where { $0.rowid.eq(Reminder.find(reminderID).select(\.rowid)) }
        .update {
          $0.tags =
            ReminderTag
            .order(by: \.tagID)
            .where { $0.reminderID.eq(reminderID) }
            .join(Tag.all) { $0.tagID.eq($1.primaryKey) }
            .select { ("#" + $1.title).groupConcat(" ") ?? "" }
        }
    }

    try ReminderTag.createTemporaryTrigger(
      after: .insert { new in
        updateReminderTextTags(for: new.reminderID)
      }
    )
    .execute(db)

    try ReminderTag.createTemporaryTrigger(
      after: .delete { old in
        updateReminderTextTags(for: old.reminderID)
      }
    )
    .execute(db)

    if context != .live {
      try db.seedSampleData()
    }
  }

  return database
}

private let logger = Logger(subsystem: "Reminders", category: "Database")

#if DEBUG
  extension Database {
    func seedSampleData() throws {
      @Dependency(\.date.now) var now
      @Dependency(\.uuid) var uuid
      let remindersListIDs = (0...2).map { _ in uuid() }
      let reminderIDs = (0...10).map { _ in uuid() }
      try seed {
        RemindersList(
          id: remindersListIDs[0],
          color: Color(red: 0x4a / 255, green: 0x99 / 255, blue: 0xef / 255),
          title: "Personal"
        )
        RemindersList(
          id: remindersListIDs[1],
          color: Color(red: 0xed / 255, green: 0x89 / 255, blue: 0x35 / 255),
          title: "Family"
        )
        RemindersList(
          id: remindersListIDs[2],
          color: Color(red: 0xb2 / 255, green: 0x5d / 255, blue: 0xd3 / 255),
          title: "Business"
        )
        Reminder(
          id: reminderIDs[0],
          notes: "Milk\nEggs\nApples\nOatmeal\nSpinach",
          remindersListID: remindersListIDs[0],
          title: "Groceries"
        )
        Reminder(
          id: reminderIDs[1],
          dueDate: now.addingTimeInterval(-60 * 60 * 24 * 2),
          isFlagged: true,
          remindersListID: remindersListIDs[0],
          title: "Haircut"
        )
        Reminder(
          id: reminderIDs[2],
          dueDate: now,
          notes: "Ask about diet",
          priority: .high,
          remindersListID: remindersListIDs[0],
          title: "Doctor appointment"
        )
        Reminder(
          id: reminderIDs[3],
          dueDate: now.addingTimeInterval(-60 * 60 * 24 * 190),
          isCompleted: true,
          remindersListID: remindersListIDs[0],
          title: "Take a walk"
        )
        Reminder(
          id: reminderIDs[4],
          dueDate: now,
          remindersListID: remindersListIDs[0],
          title: "Buy concert tickets"
        )
        Reminder(
          id: reminderIDs[5],
          dueDate: now.addingTimeInterval(60 * 60 * 24 * 2),
          isFlagged: true,
          priority: .high,
          remindersListID: remindersListIDs[1],
          title: "Pick up kids from school"
        )
        Reminder(
          id: reminderIDs[6],
          dueDate: now.addingTimeInterval(-60 * 60 * 24 * 2),
          isCompleted: true,
          priority: .low,
          remindersListID: remindersListIDs[1],
          title: "Get laundry"
        )
        Reminder(
          id: reminderIDs[7],
          dueDate: now.addingTimeInterval(60 * 60 * 24 * 4),
          isCompleted: false,
          priority: .high,
          remindersListID: remindersListIDs[1],
          title: "Take out trash"
        )
        Reminder(
          id: reminderIDs[8],
          dueDate: now.addingTimeInterval(60 * 60 * 24 * 2),
          notes: """
            Status of tax return
            Expenses for next year
            Changing payroll company
            """,
          remindersListID: remindersListIDs[2],
          title: "Call accountant"
        )
        Reminder(
          id: reminderIDs[9],
          dueDate: now.addingTimeInterval(-60 * 60 * 24 * 2),
          isCompleted: true,
          priority: .medium,
          remindersListID: remindersListIDs[2],
          title: "Send weekly emails"
        )
        Reminder(
          id: reminderIDs[10],
          dueDate: now.addingTimeInterval(60 * 60 * 24 * 2),
          isCompleted: false,
          remindersListID: remindersListIDs[2],
          title: "Prepare for WWDC"
        )
        let tagIDs = ["car", "kids", "someday", "optional", "social", "night", "adulting"]
        for tagID in tagIDs {
          Tag(title: tagID)
        }
        ReminderTag.Draft(reminderID: reminderIDs[0], tagID: tagIDs[2])
        ReminderTag.Draft(reminderID: reminderIDs[0], tagID: tagIDs[3])
        ReminderTag.Draft(reminderID: reminderIDs[0], tagID: tagIDs[6])
        ReminderTag.Draft(reminderID: reminderIDs[1], tagID: tagIDs[2])
        ReminderTag.Draft(reminderID: reminderIDs[1], tagID: tagIDs[3])
        ReminderTag.Draft(reminderID: reminderIDs[2], tagID: tagIDs[6])
        ReminderTag.Draft(reminderID: reminderIDs[3], tagID: tagIDs[0])
        ReminderTag.Draft(reminderID: reminderIDs[3], tagID: tagIDs[1])
        ReminderTag.Draft(reminderID: reminderIDs[4], tagID: tagIDs[4])
        ReminderTag.Draft(reminderID: reminderIDs[3], tagID: tagIDs[4])
        ReminderTag.Draft(reminderID: reminderIDs[10], tagID: tagIDs[4])
        ReminderTag.Draft(reminderID: reminderIDs[4], tagID: tagIDs[5])
      }
    }
  }
#endif
