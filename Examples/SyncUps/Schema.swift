import OSLog
import SharingGRDB
import SwiftUI

@Table
struct SyncUp: Hashable, Identifiable {
  let id: UUID
  var seconds: Int = 60 * 5
  var theme: Theme = .bubblegum
  var title = ""
}

@Table
struct Attendee: Hashable, Identifiable {
  let id: UUID
  var name = ""
  var syncUpID: SyncUp.ID
}

@Table
struct Meeting: Hashable, Identifiable {
  let id: UUID
  var date: Date
  var syncUpID: SyncUp.ID
  var transcript: String
}

enum Theme: String, CaseIterable, Hashable, Identifiable, QueryBindable {
  case appIndigo
  case appMagenta
  case appOrange
  case appPurple
  case appTeal
  case appYellow
  case bubblegum
  case buttercup
  case lavender
  case navy
  case oxblood
  case periwinkle
  case poppy
  case seafoam
  case sky
  case tan

  var id: Self { self }

  var accentColor: Color {
    switch self {
    case .appOrange, .appTeal, .appYellow, .bubblegum, .buttercup, .lavender, .periwinkle, .poppy,
      .seafoam, .sky, .tan:
      return .black
    case .appIndigo, .appMagenta, .appPurple, .navy, .oxblood:
      return .white
    }
  }

  var mainColor: Color { Color(rawValue) }

  var name: String {
    switch self {
    case .appIndigo, .appMagenta, .appOrange, .appPurple, .appTeal, .appYellow:
      rawValue.dropFirst(3).capitalized
    case .bubblegum, .buttercup, .lavender, .navy, .oxblood, .periwinkle, .poppy, .seafoam, .sky,
      .tan:
      rawValue.capitalized
    }
  }
}

extension Int {
  var duration: Duration {
    get { .seconds(self) }
    set { self = Int(newValue.components.seconds) }
  }
}

func appDatabase() throws -> any DatabaseWriter {
  @Dependency(\.context) var context
  let database: any DatabaseWriter
  var configuration = Configuration()
  configuration.foreignKeysEnabled = true
  configuration.prepareDatabase { db in
    #if DEBUG
      db.trace(options: .profile) {
        if context == .preview {
          print("\($0.expandedDescription)")
        } else {
          logger.debug("\($0.expandedDescription)")
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
      CREATE TABLE "syncUps" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "seconds" INTEGER NOT NULL DEFAULT 300,
        "theme" TEXT NOT NULL DEFAULT \(raw: Theme.bubblegum.rawValue),
        "title" TEXT NOT NULL
      )
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "attendees" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "name" TEXT NOT NULL,
        "syncUpID" INTEGER NOT NULL,
        
        FOREIGN KEY("syncUpID") REFERENCES "syncUps"("id") ON DELETE CASCADE
      )
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "meetings" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "date" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP UNIQUE,
        "syncUpID" INTEGER NOT NULL,
        "transcript" TEXT NOT NULL,

        FOREIGN KEY("syncUpID") REFERENCES "syncUps"("id") ON DELETE CASCADE
      )
      """
    )
    .execute(db)
  }

  try migrator.migrate(database)

  if context == .preview {
    try database.write { db in
      try db.seedSampleData()
    }
  }

  return database
}

private let logger = Logger(subsystem: "SyncUps", category: "Database")

#if DEBUG
extension Database {
  func seedSampleData() throws {
    try seed {
      SyncUp(id: UUID(1), seconds: 60, theme: .appOrange, title: "Design")
      SyncUp(id: UUID(2), seconds: 60 * 10, theme: .periwinkle, title: "Engineering")
      SyncUp(id: UUID(3), seconds: 60 * 30, theme: .poppy, title: "Product")

      for name in ["Blob", "Blob Jr", "Blob Sr", "Blob Esq", "Blob III", "Blob I"] {
        Attendee.Draft(name: name, syncUpID: UUID(1))
      }
      for name in ["Blob", "Blob Jr"] {
        Attendee.Draft(name: name, syncUpID: UUID(2))
      }
      for name in ["Blob Sr", "Blob Jr"] {
        Attendee.Draft(name: name, syncUpID: UUID(3))
      }

      Meeting.Draft(
        date: Date().addingTimeInterval(-60 * 60 * 24 * 7),
        syncUpID: UUID(1),
        transcript: """
          Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor \
          incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud \
          exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute \
          irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla \
          pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia \
          deserunt mollit anim id est laborum.
          """
      )
    }
  }
}
#endif
