import SharingGRDB
import SwiftUI

struct SyncUp: Codable, Hashable, FetchableRecord, MutablePersistableRecord {
  static let tableName = "syncUps"

  var id: Int64?
  var seconds = 60 * 5
  var theme: Theme = .bubblegum
  var title = ""

  var duration: Duration {
    get { .seconds(seconds) }
    set { seconds = Int(newValue.components.seconds) }
  }

  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}

struct Attendee: Codable, Hashable, FetchableRecord, MutablePersistableRecord {
  static let tableName = "attendees"

  var id: Int64?
  var name = ""
  var syncUpID: Int64

  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}

struct Meeting: Codable, Hashable, FetchableRecord, MutablePersistableRecord {
  static let tableName = "meetings"

  var id: Int64?
  var date: Date
  var syncUpID: Int64
  var transcript: String

  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}

enum Theme: String, CaseIterable, Codable, Hashable, Identifiable, DatabaseValueConvertible {
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
    try db.create(table: SyncUp.databaseTableName) { table in
      table.autoIncrementedPrimaryKey("id")
      table.column("seconds", .integer).defaults(to: 5 * 60).notNull()
      table.column("theme", .text).notNull().defaults(to: Theme.bubblegum)
      table.column("title", .text).notNull()
    }
  }
  migrator.registerMigration("Create attendees table") { db in
    try db.create(table: Attendee.databaseTableName) { table in
      table.autoIncrementedPrimaryKey("id")
      table.column("name", .text).notNull()
      table.column("syncUpID", .integer)
        .references(SyncUp.databaseTableName, column: "id", onDelete: .cascade)
        .notNull()
    }
  }
  migrator.registerMigration("Create meetings table") { db in
    try db.create(table: Meeting.databaseTableName) { table in
      table.autoIncrementedPrimaryKey("id")
      table.column("date", .datetime).notNull().unique().defaults(sql: "CURRENT_TIMESTAMP")
      table.column("syncUpID", .integer)
        .references(SyncUp.databaseTableName, column: "id", onDelete: .cascade)
        .notNull()
      table.column("transcript", .text).notNull()
    }
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
      let design = try SyncUp(seconds: 60, theme: .appOrange, title: "Design")
        .inserted(self)
      for name in ["Blob", "Blob Jr", "Blob Sr", "Blob Esq", "Blob III", "Blob I"] {
        _ = try Attendee(name: name, syncUpID: design.id!).inserted(self)
      }
      _ = try Meeting(
        date: Date().addingTimeInterval(-60 * 60 * 24 * 7),
        syncUpID: design.id!,
        transcript: """
          Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor \
          incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud \
          exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure \
          dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. \
          Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt \
          mollit anim id est laborum.
          """
      )
      .inserted(self)

      let engineering = try SyncUp(seconds: 60 * 10, theme: .periwinkle, title: "Engineering")
        .inserted(self)
      for name in ["Blob", "Blob Jr"] {
        _ = try Attendee(name: name, syncUpID: engineering.id!).inserted(self)
      }

      let product = try SyncUp(seconds: 60 * 30, theme: .poppy, title: "Product")
        .inserted(self)
      for name in ["Blob Sr", "Blob Jr"] {
        _ = try Attendee(name: name, syncUpID: product.id!).inserted(self)
      }
    }
  }
#endif
