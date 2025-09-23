import Foundation
import SQLiteData
import SQLiteDataTestSupport
import SnapshotTesting
import Testing
import SQLite3

@Suite(.snapshots(record: .failed))
struct PrimaryKeyMigrationTests {
  @Table struct Parent: Identifiable {
    let id: Int
    var title = ""
  }
  @Table("parents") struct NewParent: Identifiable {
    let id: UUID
    var title = ""
  }
  @Table("children") struct Child {
    let id: Int
    var title = ""
    var parentID: PrimaryKeyMigrationTests.Parent.ID
  }
  @Table("children") struct NewChild {
    let id: UUID
    var title = ""
    var parentID: PrimaryKeyMigrationTests.NewParent.ID
  }

  @Test func test() throws {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      db.trace { print($0.expandedDescription) }
    }
    let database = try DatabaseQueue(configuration: configuration)
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "parents" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "title" TEXT NOT NULL
        ) STRICT
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE TABLE "children" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "title" TEXT NOT NULL,
          "parentID" INTEGER NOT NULL REFERENCES "parents"("id") ON DELETE CASCADE
        ) STRICT
        """
      )
      .execute(db)
      try db.seed {
        Parent.Draft(title: "foo")
        Parent.Draft(title: "bar")
        Parent.Draft(title: "baz")
        Child.Draft(title: "foo", parentID: 1)
        Child.Draft(title: "bar", parentID: 2)
        Child.Draft(title: "baz", parentID: 3)
      }
    }

    try database.writeWithoutTransaction { db in
      try #sql("PRAGMA foreign_keys = OFF").execute(db)
      try #sql("BEGIN IMMEDIATE TRANSACTION").execute(db)
      try Parent.migratePrimaryKeyToUUID(db: db)
      try Child.migratePrimaryKeyToUUID(db: db)
      try #sql("COMMIT TRANSACTION").execute(db)
      try #sql("PRAGMA foreign_keys = ON").execute(db)
    }

    assertQuery(SQLiteSchema.where { !$0.name.hasPrefix("sqlite_") }, database: database) {
      #"""
      ┌───────────────────────────────────────────────────────────────────────────┐
      │ SQLiteSchema(                                                             │
      │   type: .table,                                                           │
      │   name: "parents",                                                        │
      │   tableName: "parents",                                                   │
      │   sql: """                                                                │
      │   CREATE TABLE "parents" (                                                │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),  │
      │     "title" TEXT NOT NULL                                                 │
      │   ) STRICT                                                                │
      │   """                                                                     │
      │ )                                                                         │
      ├───────────────────────────────────────────────────────────────────────────┤
      │ SQLiteSchema(                                                             │
      │   type: .table,                                                           │
      │   name: "children",                                                       │
      │   tableName: "children",                                                  │
      │   sql: """                                                                │
      │   CREATE TABLE "children" (                                               │
      │     "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),  │
      │     "title" TEXT NOT NULL,                                                │
      │     "parentID" TEXT NOT NULL REFERENCES "parents"("id") ON DELETE CASCADE │
      │   ) STRICT                                                                │
      │   """                                                                     │
      │ )                                                                         │
      └───────────────────────────────────────────────────────────────────────────┘
      """#
    }
    assertQuery(NewParent.all, database: database) {
      """
      ┌───────────────────────────────────────────────────┐
      │ PrimaryKeyMigrationTests.NewParent(               │
      │   id: UUID(00000000-0000-0000-0000-000000000001), │
      │   title: "foo"                                    │
      │ )                                                 │
      ├───────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.NewParent(               │
      │   id: UUID(00000000-0000-0000-0000-000000000002), │
      │   title: "bar"                                    │
      │ )                                                 │
      ├───────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.NewParent(               │
      │   id: UUID(00000000-0000-0000-0000-000000000003), │
      │   title: "baz"                                    │
      │ )                                                 │
      └───────────────────────────────────────────────────┘
      """
    }
    assertQuery(NewChild.all, database: database) {
      """
      ┌────────────────────────────────────────────────────────┐
      │ PrimaryKeyMigrationTests.NewChild(                     │
      │   id: UUID(00000000-0000-0000-0000-000000000001),      │
      │   title: "foo",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000001) │
      │ )                                                      │
      ├────────────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.NewChild(                     │
      │   id: UUID(00000000-0000-0000-0000-000000000002),      │
      │   title: "bar",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000002) │
      │ )                                                      │
      ├────────────────────────────────────────────────────────┤
      │ PrimaryKeyMigrationTests.NewChild(                     │
      │   id: UUID(00000000-0000-0000-0000-000000000003),      │
      │   title: "baz",                                        │
      │   parentID: UUID(00000000-0000-0000-0000-000000000003) │
      │ )                                                      │
      └────────────────────────────────────────────────────────┘
      """
    }
  }
}

extension PrimaryKeyedTable {
  public static func migratePrimaryKeyToUUID(db: Database) throws {
    let schema =
      try SQLiteSchema
      .select(\.sql)
      .where { $0.tableName.eq(Self.tableName) }
      .fetchOne(db)
      ?? nil
    guard let schema
    else {
      // TODO: throw error
      return
    }

    let tableInfo = try PragmaTableInfo<Self>.all.fetchAll(db)
    guard let primaryKey = tableInfo.first(where: { $0.isPrimaryKey })
    else {
      // TODO: validate exactly one primary key
      // TODO: throw error
      return
    }

    let foreignKeys = try PragmaForeignKeyList<Self>.all.fetchAll(db)

    var parts: [TablePart] = []
    var parensStack = 0
    var startIndex = schema.startIndex
    for (character, index) in zip(schema, schema.indices) {
      let previousParensStack = parensStack
      parensStack += character == "(" ? 1 : character == ")" ? -1 : 0
      // First paren: capture preamble
      if previousParensStack == 0 && parensStack == 1 {
        parts.append(.preamble(String(schema[startIndex...index])))
        startIndex = schema.index(after: index)
        continue
      }
      // Last paren: capture last column/constraint and table options
      if previousParensStack > 0 && parensStack == 0 {
        // TODO: also handle if its a constraint
        parts.append(.columnDefinition(String(schema[startIndex..<index])))
        parts.append(.tableOptions(String(schema[index...])))
        break
      }
      // End of column/constraint: capture
      if character == "," && parensStack == 1 {
        // TODO: also handle if its a constraint
        parts.append(.columnDefinition(String(schema[startIndex...index])))
        startIndex = schema.index(after: index)
        continue
      }
    }

    let newParts = parts.map { part in
      switch part {
      case .preamble(let text):
        var text = text
        text.replace(" \(Self.tableName) ", with: " new_\(Self.tableName) ")
        text.replace("\"\(Self.tableName)\"", with: "\"new_\(Self.tableName)\"")
        return TablePart.preamble(text)
      case .columnDefinition(let text):
        let columnName = columnName(definition: text)
        // TODO: support custom UUID function
        let leadingTrivia = text.prefix(while: \.isWhitespace)
        let trailingTrivia = String(
          text
            .reversed()
            .prefix(while: { $0.isWhitespace || $0 == "," })
            .reversed()
        )
        // TODO: case insensitive compare?
        guard columnName != primaryKey.name
        else {
          // TODO: Support when primary key is defined as a constraint instead of in a column definition
          return .columnDefinition(
          """
          \(leadingTrivia)\
          "\(primaryKey.name)" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid())\
          \(trailingTrivia)
          """
          )
        }
        // TODO: case insensitive compare?
        guard !foreignKeys.contains(where: { $0.from == columnName })
        else {
          var text = text
          guard let range = text.lowercased().firstRange(of: " integer ")
          else { return part }
          text.replaceSubrange(range, with: " TEXT ")
          return .columnDefinition(text)
        }
        return part

      case .tableConstraint:
        return part
      case .tableOptions:
        return part
      }
    }
    // TODO: throw error if no primary key rewritten
    // TODO: throw error if not all FK's handled

    let convertedColumns = tableInfo.map { tableInfo -> QueryFragment in
      // TODO: case insensitive compare?
      guard tableInfo.name != primaryKey.name
      else {
        return "'00000000-0000-0000-0000-' || printf('%012x', \(quote: tableInfo.name))"
      }
      // TODO: case insensitive compare?
      guard !foreignKeys.contains(where: { $0.from == tableInfo.name })
      else {
        return "'00000000-0000-0000-0000-' || printf('%012x', \(quote: tableInfo.name))"
      }
      return QueryFragment(quote: tableInfo.name)
    }

    let newSchema = newParts.map(\.description).joined()
    try SQLQueryExpression(QueryFragment(stringLiteral: newSchema)).execute(db)
    try #sql(
      """
      INSERT INTO \(quote: "new_" + Self.tableName)
      SELECT
      \(convertedColumns.joined(separator: ", "))
      FROM \(quote: Self.tableName) 
      """
    )
    .execute(db)
    try #sql(
      """
      DROP TABLE \(quote: Self.tableName)
      """
    )
    .execute(db)
    try #sql(
      """
      ALTER TABLE \(quote: "new_" + Self.tableName) RENAME TO \(quote: Self.tableName)
      """
    )
    .execute(db)
  }
}

private func columnName(definition: String) -> String {
  var substring = definition[...].drop(while: \.isWhitespace)
  if substring.first == "\"" {
    substring.removeFirst()
  }
  return String(substring.prefix(while: { $0 != " " && $0 != "\"" }))
}

private enum TablePart: CustomStringConvertible {
  case preamble(String)
  case columnDefinition(String)
  case tableConstraint(String)
  case tableOptions(String)
  var description: String {
    switch self {
    case .preamble(let s):
      return s
    case .columnDefinition(let s):
      return s
    case .tableConstraint(let s):
      return s
    case .tableOptions(let s):
      return s
    }
  }
}
