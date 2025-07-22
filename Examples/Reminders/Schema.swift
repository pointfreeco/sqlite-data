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
  var color = Color(red: 0x4a / 255, green: 0x99 / 255, blue: 0xef / 255)
  var position = 0
  var title = ""
}

extension RemindersList.Draft: Identifiable {}

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
      if !text.isEmpty {
        $0.id.in(
          RemindersText
            .where { $0.match(text) }
            .select(\.reminderID)
        )
      }
    }
//    Self.where {
//      $0.title.collate(.nocase).contains(text)
//        || $0.notes.collate(.nocase).contains(text)
//    }
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

protocol FTS5: StructuredQueriesCore.Table {}

extension StructuredQueriesCore.TableDefinition where QueryValue: FTS5 {
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
struct RemindersText: FTS5 {
  let reminderID: Reminder.ID
  let title: String
  let notes: String
  let listID: RemindersList.ID
  let listTitle: String
  let tags: String
}

@Table @Selection
struct TagText {
  let titles: String
}

func appDatabase() throws -> any DatabaseWriter {
  @Dependency(\.context) var context
  let database: any DatabaseWriter
  var configuration = Configuration()
  configuration.foreignKeysEnabled = true
  configuration.prepareDatabase { db in
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
    logger.info("open \(path)")
    database = try DatabasePool(path: path, configuration: configuration)
  }
  var migrator = DatabaseMigrator()
  #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
  #endif
  migrator.registerMigration("Create initial tables") { db in
    try #sql(
      """
      CREATE TABLE "remindersLists" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "color" INTEGER NOT NULL DEFAULT \(raw: 0x4a99_ef00),
        "position" INTEGER NOT NULL DEFAULT 0,
        "title" TEXT NOT NULL
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
        "notes" TEXT,
        "position" INTEGER NOT NULL DEFAULT 0,
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
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "title" TEXT NOT NULL COLLATE NOCASE
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "remindersTags" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "reminderID" TEXT NOT NULL,
        "tagID" TEXT NOT NULL,

        FOREIGN KEY("reminderID") REFERENCES "reminders"("id") ON DELETE CASCADE,
        FOREIGN KEY("tagID") REFERENCES "tags"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE VIRTUAL TABLE "remindersTexts" USING fts5(
        "reminderID",
        "title",
        "notes",
        "listID",
        "listTitle",
        "tags",
        tokenize = 'trigram'
      )
      """
    )
    .execute(db)
    // TODO: Populate virtual table here
  }

  try migrator.migrate(database)

  if context == .preview {
    try database.write { db in
      try db.seedSampleData()
    }
  }

  try database.write { db in
    try #sql(
      """
      CREATE TEMPORARY TRIGGER "default_position_reminders_lists" 
      AFTER INSERT ON "remindersLists"
      FOR EACH ROW BEGIN
        UPDATE "remindersLists"
        SET "position" = (SELECT max("position") + 1 FROM "remindersLists")
        WHERE "id" = NEW."id";
      END
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TEMPORARY TRIGGER "default_position_reminders" 
      AFTER INSERT ON "reminders"
      FOR EACH ROW BEGIN
        UPDATE "reminders"
        SET "position" = (SELECT max("position") + 1 FROM "reminders")
        WHERE "id" = NEW."id";
      END
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TEMPORARY TRIGGER "non_empty_reminders_lists" 
      AFTER DELETE ON "remindersLists"
      FOR EACH ROW BEGIN
        INSERT INTO "remindersLists"
        ("title", "color")
        SELECT 'Personal', \(raw: 0x4a99ef)
        WHERE (SELECT count(*) FROM "remindersLists") = 0;
      END
      """
    )
    .execute(db)

    try Reminder.createTemporaryTrigger(after: .insert { new in
      RemindersText.insert {
        ($0.reminderID, $0.title, $0.notes, $0.listID, $0.listTitle)
      } select: {
        Reminder
          .find(new.id)
          .join(RemindersList.all) { $0.remindersListID.eq($1.id) }
          .select { ($0.id, $0.title, $0.notes, $1.id, $1.title) }
      }
    })
    .execute(db)
    try Reminder.createTemporaryTrigger(after: .update {
      ($0.title, $0.notes, $0.remindersListID)
    } forEachRow: { _, new in
      RemindersText
        .where { $0.reminderID.eq(new.id) }
        .update {
          $0.title = new.title
          $0.notes = new.notes
          $0.listID = new.remindersListID
        }
    })
    .execute(db)
    try Reminder.createTemporaryTrigger(after: .delete { old in
      RemindersText
        .where { $0.reminderID.eq(old.id) }
        .delete()
    })
    .execute(db)
    try RemindersList.createTemporaryTrigger(after: .update {
      $0.title
    } forEachRow: { _, new in
      RemindersText
        .where { $0.listID.eq(new.id) }
        .update { $0.listTitle = new.title }
    })
    .execute(db)
    try ReminderTag.createTemporaryTrigger(after: .insert { new in
      RemindersText
        .where { $0.reminderID.eq(new.reminderID) }
        .update {
          $0.tags = ReminderTag
            .where { $0.reminderID.eq(new.reminderID) }
            .join(Tag.all) { $0.tagID.eq($1.id) }
            .select { $1.title.groupConcat(" ") ?? "" }
        }
    })
    .execute(db)
    try ReminderTag.createTemporaryTrigger(after: .delete { old in
      RemindersText
        .where { $0.reminderID.eq(old.reminderID) }
        .update {
          $0.tags = ReminderTag
            .where { $0.reminderID.eq(old.reminderID) }
            .join(Tag.all) { $0.tagID.eq($1.id) }
            .select { $1.title.groupConcat(" ") ?? "" }
        }
    })
    .execute(db)
  }

  return database
}

private let logger = Logger(subsystem: "Reminders", category: "Database")

#if DEBUG
  extension Database {
    func seedSampleData() throws {
      let remindersListIDs = (0...2).map { _ in UUID() }
      let reminderIDs = (0...10).map { _ in UUID() }
      let tagIDs = (0...6).map { _ in UUID() }
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
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isFlagged: true,
          remindersListID: remindersListIDs[0],
          title: "Haircut"
        )
        Reminder(
          id: reminderIDs[2],
          dueDate: Date(),
          notes: "Ask about diet",
          priority: .high,
          remindersListID: remindersListIDs[0],
          title: "Doctor appointment"
        )
        Reminder(
          id: reminderIDs[3],
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 190),
          isCompleted: true,
          remindersListID: remindersListIDs[0],
          title: "Take a walk"
        )
        Reminder(
          id: reminderIDs[4],
          dueDate: Date(),
          remindersListID: remindersListIDs[0],
          title: "Buy concert tickets"
        )
        Reminder(
          id: reminderIDs[5],
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 2),
          isFlagged: true,
          priority: .high,
          remindersListID: remindersListIDs[1],
          title: "Pick up kids from school"
        )
        Reminder(
          id: reminderIDs[6],
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isCompleted: true,
          priority: .low,
          remindersListID: remindersListIDs[1],
          title: "Get laundry"
        )
        Reminder(
          id: reminderIDs[7],
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 4),
          isCompleted: false,
          priority: .high,
          remindersListID: remindersListIDs[1],
          title: "Take out trash"
        )
        Reminder(
          id: reminderIDs[8],
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 2),
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
          dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
          isCompleted: true,
          priority: .medium,
          remindersListID: remindersListIDs[2],
          title: "Send weekly emails"
        )
        Reminder(
          id: reminderIDs[10],
          dueDate: Date().addingTimeInterval(60 * 60 * 24 * 2),
          isCompleted: false,
          remindersListID: remindersListIDs[2],
          title: "Prepare for WWDC"
        )
        Tag(id: tagIDs[0], title: "car")
        Tag(id: tagIDs[1], title: "kids")
        Tag(id: tagIDs[2], title: "someday")
        Tag(id: tagIDs[3], title: "optional")
        Tag(id: tagIDs[4], title: "social")
        Tag(id: tagIDs[5], title: "night")
        Tag(id: tagIDs[6], title: "adulting")
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
