import Dependencies
import Foundation
import IssueReporting
import OSLog
import SQLiteData
import SwiftUI
import Synchronization

@Table
struct RemindersList: Hashable, Identifiable {
  let id: UUID
  var title = ""

  static var defaultColor: Color { Color(red: 0x4a / 255, green: 0x99 / 255, blue: 0xef / 255) }
  static var defaultTitle: String { "Personal" }
}

extension RemindersList.Draft: Identifiable {}

@Table
struct Reminder: Hashable, Identifiable, Codable {
  let id: UUID
  var remindersListID: RemindersList.ID
  var title = ""
  var isCompleted: Bool = false
}

extension Reminder.Draft: Identifiable {}

extension DependencyValues {
  mutating func bootstrapDatabase() throws {
    defaultDatabase = try AppKitDemo.appDatabase()
    //    defaultSyncEngine = try SyncEngine(
    //      for: defaultDatabase,
    //      tables: RemindersList.self,
    //      Reminder.self,
    //    )
  }
}

func appDatabase() throws -> any DatabaseWriter {
  @Dependency(\.context) var context
  var configuration = Configuration()
  configuration.foreignKeysEnabled = true
  configuration.prepareDatabase { db in
    //try db.attachMetadatabase()
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
  let database = try SQLiteData.defaultDatabase(configuration: configuration)
  logger.debug(
    """
    App database:
    open "\(database.path)"
    """
  )
  var migrator = DatabaseMigrator()
  #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
  #endif
  migrator.registerMigration("Create initial tables") { db in
    try #sql(
      """
      CREATE TABLE "remindersLists" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "reminders" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "remindersListID" TEXT NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE,
        "isCompleted" INTEGER NOT NULL DEFAULT 0,
        "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
      ) STRICT
      """
    )
    .execute(db)
  }

  try migrator.migrate(database)

  try database.write { db in

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
          title: "Personal"
        )
        RemindersList(
          id: remindersListIDs[1],
          title: "Family"
        )
        RemindersList(
          id: remindersListIDs[2],
          title: "Business"
        )
        Reminder(
          id: reminderIDs[0],
          remindersListID: remindersListIDs[0],
          title: "Groceries"
        )
        Reminder(
          id: reminderIDs[1],
          remindersListID: remindersListIDs[0],
          title: "Haircut"
        )
        Reminder(
          id: reminderIDs[2],
          remindersListID: remindersListIDs[0],
          title: "Doctor appointment"
        )
        Reminder(
          id: reminderIDs[3],
          remindersListID: remindersListIDs[0],
          title: "Take a walk",
          isCompleted: true,
        )
        Reminder(
          id: reminderIDs[4],
          remindersListID: remindersListIDs[0],
          title: "Buy concert tickets"
        )
        Reminder(
          id: reminderIDs[5],
          remindersListID: remindersListIDs[1],
          title: "Pick up kids from school"
        )
        Reminder(
          id: reminderIDs[6],
          remindersListID: remindersListIDs[1],
          title: "Get laundry",
          isCompleted: true,
        )
        Reminder(
          id: reminderIDs[7],
          remindersListID: remindersListIDs[1],
          title: "Take out trash"
        )
        Reminder(
          id: reminderIDs[8],
          remindersListID: remindersListIDs[2],
          title: "Call accountant"
        )
        Reminder(
          id: reminderIDs[9],
          remindersListID: remindersListIDs[2],
          title: "Send weekly emails",
          isCompleted: true,
        )
        Reminder(
          id: reminderIDs[10],
          remindersListID: remindersListIDs[2],
          title: "Prepare for WWDC"
        )
      }
    }
  }
#endif
