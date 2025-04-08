import SharingGRDB
import StructuredQueriesGRDB
import SwiftUI

@Table
struct SyncUp: Codable, Hashable, Identifiable {
  let id: Int
  var seconds: Int = 60 * 5
  var theme: Theme = .bubblegum
  var title = ""
}

@Table
struct Attendee: Codable, Hashable, Identifiable {
  let id: Int
  var name = ""
  var syncUpID: SyncUp.ID
}

@Table
struct Meeting: Codable, Hashable, Identifiable {
  let id: Int
  @Column(as: Date.ISO8601Representation.self)
  var date: Date
  var syncUpID: SyncUp.ID
  var transcript: String
}

enum Theme: String, CaseIterable, Codable, Hashable, Identifiable, QueryBindable {
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
  migrator.registerMigration("Create sync-ups table") { db in
    try #sql(
      """
      CREATE TABLE "syncUps" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "seconds" INTEGER NOT NULL DEFAULT 300,
        "theme" TEXT NOT NULL DEFAULT \(raw: Theme.bubblegum.rawValue),
        "title" TEXT NOT NULL
      )
      """
    )
    .execute(db)
  }
  migrator.registerMigration("Create attendees table") { db in
    try #sql(
      """
      CREATE TABLE "attendees" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "name" TEXT NOT NULL,
        "syncUpID" INTEGER NOT NULL,
        
        FOREIGN KEY("syncUpID") REFERENCES "syncUps"("id") ON DELETE CASCADE
      )
      """
    )
    .execute(db)
  }
  migrator.registerMigration("Create meetings table") { db in
    try #sql(
      """
      CREATE TABLE "meetings" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "date" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP UNIQUE,
        "syncUpID" INTEGER NOT NULL,
        "transcript" TEXT NOT NULL,

        FOREIGN KEY("syncUpID") REFERENCES "syncUps"("id") ON DELETE CASCADE
      )
      """
    )
    .execute(db)
  }
  #if DEBUG
    migrator.registerMigration("Insert sample data") { db in
      try db.insertSampleData()
    }
  #endif

  try migrator.migrate(database)

  return database
}

#if DEBUG
  extension Database {
    func insertSampleData() throws {
      let design = try SyncUp
        .insert(SyncUp.Draft(seconds: 60, theme: .appOrange, title: "Design"))
        .returning(\.self)
        .fetchOne(self)!

      for name in ["Blob", "Blob Jr", "Blob Sr", "Blob Esq", "Blob III", "Blob I"] {
        try Attendee
          .insert(Attendee.Draft(name: name, syncUpID: design.id))
          .execute(self)
      }
      try Meeting
        .insert(
          Meeting.Draft(
            date: Date().addingTimeInterval(-60 * 60 * 24 * 7),
            syncUpID: design.id,
            transcript: """
              Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor \
              incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud \
              exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute \
              irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla \
              pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia \
              deserunt mollit anim id est laborum.
              """
          )
        )
        .execute(self)

      let engineering = try SyncUp
        .insert(SyncUp.Draft(seconds: 60 * 10, theme: .periwinkle, title: "Engineering"))
        .returning(\.self)
        .fetchOne(self)!
      for name in ["Blob", "Blob Jr"] {
        try Attendee
          .insert(Attendee.Draft(name: name, syncUpID: engineering.id))
          .execute(self)
      }

      let product = try SyncUp
        .insert(SyncUp.Draft(seconds: 60 * 30, theme: .poppy, title: "Product"))
        .returning(\.self)
        .fetchOne(self)!
      for name in ["Blob Sr", "Blob Jr"] {
        try Attendee
          .insert(Attendee.Draft(name: name, syncUpID: product.id))
          .execute(self)
      }
    }
  }
#endif
