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
  @Column(primaryKey: true)
  var title: String
  var id: String { title }
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
  var inlineNotes: some QueryExpression<String> {
    notes.replace("\n", " ")
  }
}

extension Tag {
  static let withReminders = group(by: \.title)
    .leftJoin(ReminderTag.all) { $0.primaryKey.eq($1.tagID) }
    .leftJoin(Reminder.all) { $1.reminderID.eq($2.id) }
}

extension Tag.TableColumns {
  var jsonTitles: some QueryExpression<[String].JSONRepresentation> {
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
        "remindersListID" TEXT NOT NULL,
        "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',

        FOREIGN KEY("remindersListID") REFERENCES "remindersLists"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "tags" (
        "title" TEXT COLLATE NOCASE PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT ''
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "remindersTags" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "reminderID" TEXT NOT NULL,
        "tag" TEXT NOT NULL,

        FOREIGN KEY("reminderID") REFERENCES "reminders"("id") ON DELETE CASCADE,
        FOREIGN KEY("tag") REFERENCES "tags"("title") ON DELETE CASCADE ON UPDATE CASCADE
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
        .find(new.id)
        .update { $0.position = RemindersList.select { ($0.position.max() ?? -1) + 1} }
    })
    .execute(db)
    try Reminder.createTemporaryTrigger(after: .insert { new in
      Reminder
        .find(new.id)
        .update { $0.position = Reminder.select { ($0.position.max() ?? -1) + 1} }
    })
    .execute(db)
    try RemindersList.createTemporaryTrigger(after: .delete { _ in
      RemindersList.insert {
        RemindersList.Draft(
          color: RemindersList.defaultColor,
          title: RemindersList.defaultTitle
        )
      }
    } when: { _ in
      !RemindersList.exists()
    })
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
        Tag(title: "car")
        Tag(title: "kids")
        Tag(title: "someday")
        Tag(title: "optional")
        Tag(title: "social")
        Tag(title: "night")
        Tag(title: "adulting")
        ReminderTag.Draft(reminderID: remindersIDs[0], tagID: "someday")
        ReminderTag.Draft(reminderID: remindersIDs[0], tagID: "optional")
        ReminderTag.Draft(reminderID: remindersIDs[0], tagID: "adulting")
        ReminderTag.Draft(reminderID: remindersIDs[1], tagID: "someday")
        ReminderTag.Draft(reminderID: remindersIDs[1], tagID: "optional")
        ReminderTag.Draft(reminderID: remindersIDs[2], tagID: "adulting")
        ReminderTag.Draft(reminderID: remindersIDs[3], tagID: "car")
        ReminderTag.Draft(reminderID: remindersIDs[3], tagID: "kids")
        ReminderTag.Draft(reminderID: remindersIDs[4], tagID: "social")
        ReminderTag.Draft(reminderID: remindersIDs[3], tagID: "social")
        ReminderTag.Draft(reminderID: remindersIDs[10], tagID: "social")
        ReminderTag.Draft(reminderID: remindersIDs[4], tagID: "night")
      }
    }
  }
#endif
