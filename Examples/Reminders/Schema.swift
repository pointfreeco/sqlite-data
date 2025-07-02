import Dependencies
import Foundation
import IssueReporting
import OSLog
import SharingGRDB
import SwiftUI

@Table
struct RemindersList: Hashable, Identifiable {
  let id: UUID
  @Column(as: Color.HexRepresentation.self)
  var color: Color = .blue
  var position = 0
  var title = ""
}

extension RemindersList.Draft: Identifiable {}

@Table
struct RemindersListAsset: Hashable, Identifiable {
  let id: UUID
  var coverImage: Data?
  let remindersListID: RemindersList.ID
}

@Table
struct Reminder: Codable, Equatable, Identifiable {
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
  let id: UUID
  var title = ""
}

enum Priority: Int, Codable, QueryBindable {
  case low = 1
  case medium
  case high
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
  var inlineNotes: some QueryExpression<String> {
    notes.replace("\n", " ")
  }
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
    try db.attachMetadatabase(containerIdentifier: "iCloud.co.pointfree.SQLiteData.demos.Reminders")
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
      App database
      open "\(path)"
      """
    )
    database = try DatabasePool(path: path, configuration: configuration)
  }
  var migrator = DatabaseMigrator()
  #if DEBUG
  // TODO: should we warn against this for CK apps?
    migrator.eraseDatabaseOnSchemaChange = true
  #endif
  migrator.registerMigration("Create initial tables") { db in
    try #sql(
      """
      CREATE TABLE "remindersLists" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "color" INTEGER NOT NULL DEFAULT \(raw: 0x4a99_ef00),
        "position" INTEGER NOT NULL DEFAULT 0,
        "title" TEXT NOT NULL DEFAULT ''
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "remindersListAssets" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "coverImage" BLOB,
        "remindersListID" TEXT NOT NULL 
          DEFAULT '00000000-0000-0000-0000-000000000000'
          REFERENCES "remindersLists"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "reminders" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "dueDate" TEXT,
        "isCompleted" INTEGER NOT NULL DEFAULT 0,
        "isFlagged" INTEGER NOT NULL DEFAULT 0,
        "notes" TEXT NOT NULL DEFAULT '',
        "position" INTEGER NOT NULL DEFAULT 0,
        "priority" INTEGER,
        "remindersListID" TEXT NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000',
        "title" TEXT NOT NULL DEFAULT '',

        FOREIGN KEY("remindersListID") REFERENCES "remindersLists"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "tags" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "title" TEXT NOT NULL DEFAULT ''
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "remindersTags" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "reminderID" TEXT NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000',
        "tagID" TEXT NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000',

        FOREIGN KEY("reminderID") REFERENCES "reminders"("id") ON DELETE CASCADE,
        FOREIGN KEY("tagID") REFERENCES "tags"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
  }

  try migrator.migrate(database)

  try database.write { db in
    if context == .preview {
      try db.seedSampleData()
    }

    try RemindersList.createTemporaryTrigger(after: .insert { new in
      RemindersList
        .update { $0.position = RemindersList.select { ($0.position.max() ?? -1) + 1} }
        .where { $0.id.eq(new.id) }
    })
    .execute(db)
    try Reminder.createTemporaryTrigger(after: .insert { new in
      Reminder
        .update { $0.position = Reminder.select { ($0.position.max() ?? -1) + 1} }
        .where { $0.id.eq(new.id) }
    })
    .execute(db)
    try RemindersList.createTemporaryTrigger(
      after: .delete { _ in
        RemindersList.insert {
          RemindersList.Draft(color: .blue, title: "Personal")
        }
      } when: { _ in
        RemindersList.count().eq(0)
      }
    )
    .execute(db)
  }

  return database
}

private let logger = Logger(subsystem: "Reminders", category: "Database")

#if DEBUG
  extension Database {
    func seedSampleData() throws {
      let remindersListsIDs = (0...2).map { _ in UUID() }
      let remindersIDs = (0...10).map { _ in UUID() }
      let tagsIDs = (0...6).map { _ in UUID() }
      try seed {
        RemindersList(
          id: remindersListsIDs[0],
          color: Color(red: 0x4a / 255, green: 0x99 / 255, blue: 0xef / 255),
          title: "Personal"
        )
        RemindersList(
          id: remindersListsIDs[1],
          color: Color(red: 0xed / 255, green: 0x89 / 255, blue: 0x35 / 255),
          title: "Family"
        )
        RemindersList(
          id: remindersListsIDs[2],
          color: Color(red: 0xb2 / 255, green: 0x5d / 255, blue: 0xd3 / 255),
          title: "Business"
        )
        Reminder(
          id: remindersIDs[0],
          notes: "Milk\nEggs\nApples\nOatmeal\nSpinach",
          remindersListID: remindersListsIDs[0],
          title: "Groceries"
        )
        Reminder(
          id: remindersIDs[1],
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isFlagged: true,
          remindersListID: remindersListsIDs[0],
          title: "Haircut"
        )
        Reminder(
          id: remindersIDs[2],
          dueDate: Date(),
          notes: "Ask about diet",
          priority: .high,
          remindersListID: remindersListsIDs[0],
          title: "Doctor appointment"
        )
        Reminder(
          id: remindersIDs[3],
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 190),
          isCompleted: true,
          remindersListID: remindersListsIDs[0],
          title: "Take a walk"
        )
        Reminder(
          id: remindersIDs[4],
          dueDate: Date(),
          remindersListID: remindersListsIDs[0],
          title: "Buy concert tickets"
        )
        Reminder(
          id: remindersIDs[5],
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 2),
          isFlagged: true,
          priority: .high,
          remindersListID: remindersListsIDs[1],
          title: "Pick up kids from school"
        )
        Reminder(
          id: remindersIDs[6],
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isCompleted: true,
          priority: .low,
          remindersListID: remindersListsIDs[1],
          title: "Get laundry"
        )
        Reminder(
          id: remindersIDs[7],
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 4),
          isCompleted: false,
          priority: .high,
          remindersListID: remindersListsIDs[1],
          title: "Take out trash"
        )
        Reminder(
          id: remindersIDs[8],
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 2),
          notes: """
            Status of tax return
            Expenses for next year
            Changing payroll company
            """,
          remindersListID: remindersListsIDs[2],
          title: "Call accountant"
        )
        Reminder(
          id: remindersIDs[9],
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isCompleted: true,
          priority: .medium,
          remindersListID: remindersListsIDs[2],
          title: "Send weekly emails"
        )
        Reminder(
          id: remindersIDs[10],
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 2),
          isCompleted: false,
          remindersListID: remindersListsIDs[2],
          title: "Prepare for WWDC"
        )
        Tag(id: tagsIDs[0], title: "car")
        Tag(id: tagsIDs[1], title: "kids")
        Tag(id: tagsIDs[2], title: "someday")
        Tag(id: tagsIDs[3], title: "optional")
        Tag(id: tagsIDs[4], title: "social")
        Tag(id: tagsIDs[5], title: "night")
        Tag(id: tagsIDs[6], title: "adulting")
        ReminderTag.Draft(reminderID: remindersIDs[0], tagID: tagsIDs[2])
        ReminderTag.Draft(reminderID: remindersIDs[0], tagID: tagsIDs[3])
        ReminderTag.Draft(reminderID: remindersIDs[0], tagID: tagsIDs[6])
        ReminderTag.Draft(reminderID: remindersIDs[1], tagID: tagsIDs[2])
        ReminderTag.Draft(reminderID: remindersIDs[1], tagID: tagsIDs[3])
        ReminderTag.Draft(reminderID: remindersIDs[2], tagID: tagsIDs[6])
        ReminderTag.Draft(reminderID: remindersIDs[3], tagID: tagsIDs[0])
        ReminderTag.Draft(reminderID: remindersIDs[3], tagID: tagsIDs[1])
        ReminderTag.Draft(reminderID: remindersIDs[4], tagID: tagsIDs[4])
        ReminderTag.Draft(reminderID: remindersIDs[3], tagID: tagsIDs[4])
        ReminderTag.Draft(reminderID: remindersIDs[10], tagID: tagsIDs[4])
        ReminderTag.Draft(reminderID: remindersIDs[4], tagID: tagsIDs[5])
      }
    }
  }
#endif
