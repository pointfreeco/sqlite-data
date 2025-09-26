import CryptoKit
import Foundation

@available(iOS 17, macOS 14, tvOS 14, watchOS 10, *)
extension SyncEngine {
  /// Migrates integer primary-keyed tables and join tables to CloudKit-compatible, UUID primary
  /// keys.
  ///
  /// - Parameters:
  ///   - db: A database connection.
  ///   - tables: Tables to migrate.
  ///   - uuidFunction: A UUID function. If `nil`, SQLite's `uuid` function will be used.
  public static func migratePrimaryKeys<each T: PrimaryKeyedTable>(
    _ db: Database,
    tables: repeat (each T).Type,
    uuid uuidFunction: (any ScalarDatabaseFunction<(), UUID>)? = nil
  ) throws where repeat (each T).PrimaryKey.QueryOutput: IdentifierStringConvertible {
    db.add(function: $uuid)
    defer { db.remove(function: $uuid) }
    
    var migratedTableNames: [String] = []
    for table in repeat each tables {
      migratedTableNames.append(table.tableName)
    }
    let indicesAndTriggersSQL =
      try SQLiteSchema
      .select(\.sql)
      .where {
        $0.tableName.in(migratedTableNames)
          && $0.type.in([#bind(.index), #bind(.trigger)])
          && $0.sql.isNot(nil)
      }
      .fetchAll(db)
      .compactMap(\.self)
    for table in repeat each tables {
      try table.migratePrimaryKeyToUUID(
        db: db,
        uuidFunction: uuidFunction,
        migratedTableNames: migratedTableNames
      )
    }
    for sql in indicesAndTriggersSQL {
      try #sql(QueryFragment(stringLiteral: sql)).execute(db)
    }
  }
}

private struct MigrationError: Error {
}

@available(iOS 16, macOS 13, tvOS 13, watchOS 9, *)
extension PrimaryKeyedTable {
  fileprivate static func migratePrimaryKeyToUUID(
    db: Database,
    uuidFunction: (any ScalarDatabaseFunction<(), UUID>)? = nil,
    migratedTableNames: [String]
  ) throws {
    let schema =
      try SQLiteSchema
      .select(\.sql)
      .where { $0.type.eq(#bind(.table)) && $0.tableName.eq(tableName) }
      .fetchOne(db)
      ?? nil

    guard let schema
    else {
      throw MigrationError()
    }

    let tableInfo = try PragmaTableInfo<Self>.all.fetchAll(db)
    let primaryKeys = tableInfo.filter(\.isPrimaryKey)
    guard
      (primaryKeys.count == 1 && primaryKeys[0].isInt) || primaryKeys.isEmpty
    else {
      throw MigrationError()
    }

    let foreignKeys = try PragmaForeignKeyList<Self>.all.fetchAll(db)
    guard foreignKeys.allSatisfy({ migratedTableNames.contains($0.table) })
    else {
      throw MigrationError()
    }

    let newTableName = "new_\(tableName)"
    let uuidFunction = uuidFunction?.name ?? "uuid"
    let newSchema = try schema.rewriteSchema(
      oldPrimaryKey: primaryKeys.first?.name,
      newPrimaryKey: columns.primaryKey.name,
      foreignKeys: foreignKeys.map(\.from),
      uuidFunction: uuidFunction
    )

    var convertedColumns: [QueryFragment] = []
    if primaryKeys.first == nil {
      convertedColumns.append("NULL")
    }
    convertedColumns.append(
      contentsOf: tableInfo.map { tableInfo -> QueryFragment in
        guard
          tableInfo.name != primaryKey.name,
          !foreignKeys.contains(where: { $0.from == tableInfo.name })
        else {
          return """
          sqlitedata_icloud_uuidFromIDAndTable(\
          \(quote: tableInfo.name), \
          \(quote: tableName, delimiter: .text)\
          )
          """
        }
        return QueryFragment(quote: tableInfo.name)
      }
    )

    try #sql(QueryFragment(stringLiteral: newSchema)).execute(db)
    try #sql(
      """
      INSERT INTO \(quote: newTableName) \
      SELECT \(convertedColumns.joined(separator: ", ")) \
      FROM \(Self.self) 
      """
    )
    .execute(db)
    try #sql(
      """
      DROP TABLE \(Self.self)
      """
    )
    .execute(db)
    try #sql(
      """
      ALTER TABLE \(quote: newTableName) RENAME TO \(Self.self)
      """
    )
    .execute(db)
  }
}

extension StringProtocol {
  fileprivate func quoted() -> String {
    #"""# + replacingOccurrences(of: #"""#, with: #""""#) + #"""#
  }
}

extension String {
  func rewriteSchema(
    oldPrimaryKey: String?,
    newPrimaryKey: String,
    foreignKeys: [String],
    uuidFunction: String
  ) throws -> String {
    var substring = self[...]
    return try substring.rewriteSchema(
      oldPrimaryKey: oldPrimaryKey,
      newPrimaryKey: newPrimaryKey,
      foreignKeys: foreignKeys,
      uuidFunction: uuidFunction
    )
  }
}

extension Substring {
  mutating func rewriteSchema(
    oldPrimaryKey: String?,
    newPrimaryKey: String,
    foreignKeys: [String],
    uuidFunction: String
  ) throws -> String {
    var index = startIndex
    var newSchema = ""

    func flush() {
      newSchema.append(String(base[index..<startIndex]))
      index = startIndex
    }

    guard parseKeywords(["CREATE", "TABLE"]) else { throw SyntaxError() }
    parseKeywords(["IF", "NOT", "EXISTS"])
    parseTrivia()
    flush()
    guard let tableName = try parseIdentifier() else { throw SyntaxError() }
    newSchema.append("new_\(tableName)".quoted())
    index = startIndex
    parseTrivia()
    guard parseOpen() else { throw SyntaxError() }
    let trivia = parseTrivia()
    flush()
    if oldPrimaryKey == nil {
      newSchema.append(
        """
        \(newPrimaryKey.quoted()) TEXT PRIMARY KEY NOT NULL \
        ON CONFLICT REPLACE DEFAULT (\(uuidFunction.quoted())()),\(trivia)
        """
      )
    }
    func parseToNextColumnDefinitionOrTableConstraint(
      skipIf shouldSkip: Bool
    ) throws -> Bool {
      if (try? parseBalanced(upTo: ",")) != nil {
        if shouldSkip {
          index = startIndex
        }
        flush()
        removeFirst()
        return false
      } else {
        try parseBalanced(upTo: ")")
        if shouldSkip {
          index = startIndex
        }
        return true
      }
    }
    while try peek({ try !$0.parseTableConstraint() }), let columnName = try parseIdentifier() {
      parseTrivia()
      if columnName == oldPrimaryKey {
        newSchema.append(
          """
          \(columnName.quoted()) TEXT PRIMARY KEY NOT NULL \
          ON CONFLICT REPLACE DEFAULT (\(uuidFunction.quoted())())
          """
        )
      } else if foreignKeys.contains(columnName) {
        flush()
        if peek({ !$0.parseColumnConstraint() }), (try? parseIdentifier()) != nil {
          index = startIndex
          flush()
          newSchema.append("TEXT")
        }
      }
      if try parseToNextColumnDefinitionOrTableConstraint(
        skipIf: columnName == oldPrimaryKey
      ) {
        break
      }
    }
    while peek({ $0.parseColumnConstraint() }) {
      if try parseToNextColumnDefinitionOrTableConstraint(
        skipIf: parseKeywords(["PRIMARY", "KEY"])
      ) {
        break
      }
    }
    removeFirst(count)
    flush()
    return newSchema
  }

  func peek<R>(_ body: (inout Self) throws -> R) rethrows -> R {
    var substring = self
    return try body(&substring)
  }

  mutating func parseBalanced(upTo endCharacter: Character = ",") throws {
    let substring = self
    parseTrivia()
    var parenDepth = 0
    while let character = first {
      defer { parseTrivia() }
      switch character {
      case endCharacter where parenDepth == 0:
        return
      case "(":
        parenDepth += 1
        removeFirst()
      case ")":
        parenDepth -= 1
        removeFirst()
      case #"""#, "`", "[":
        _ = try parseIdentifier()
      case "'":
        _ = try parseText()
      default:
        removeFirst()
        continue
      }
    }
    self = substring
    throw SyntaxError()
  }

  mutating func parseTableConstraint() throws -> Bool {
    if parseKeyword("CONSTRAINT")
      || parseKeywords(["PRIMARY", "KEY"])
      || parseKeyword("UNIQUE")
      || parseKeyword("CHECK")
      || parseKeywords(["FOREIGN", "KEY"])
    {
      try parseBalanced(upTo: ",")
      return true
    } else {
      return false
    }
  }

  mutating func parseColumnConstraint() -> Bool {
    parseKeyword("CONSTRAINT")
      || parseKeywords(["PRIMARY", "KEY"])
      || parseKeywords(["NOT", "NULL"])
      || parseKeyword("UNIQUE")
      || parseKeyword("CHECK")
      || parseKeyword("DEFAULT")
      || parseKeyword("COLLATE")
      || parseKeywords(["REFERENCES"])
      || parseKeywords(["GENERATED", "ALWAYS"])
      || parseKeyword("AS")
  }

  mutating func parseOpen() -> Bool {
    guard first == "(" else { return false }
    removeFirst()
    return true
  }

  mutating func parseText() throws -> String? {
    guard first == "'" else { return nil }
    let quote = removeFirst()
    return try parseQuoted(quote)
  }

  mutating func parseIdentifier() throws -> String? {
    parseTrivia()
    guard let firstCharacter = first else { return nil }
    switch firstCharacter {
    case #"""#, "`", "[":
      removeFirst()
      return try parseQuoted(firstCharacter)

    default:
      let identifier = prefix { !$0.isWhitespace }
      removeFirst(identifier.count)
      return String(identifier)
    }
  }

  mutating func parseQuoted(_ startDelimiter: Character) throws -> String? {
    let endDelimiter: Character = startDelimiter == "[" ? "]" : startDelimiter
    var identifier = ""
    while !isEmpty {
      let character = removeFirst()
      if character == startDelimiter {
        if startDelimiter == endDelimiter, first == startDelimiter {
          identifier.append(character)
          removeFirst()
        } else {
          return identifier
        }
      } else {
        identifier.append(character)
      }
    }
    throw SyntaxError()
  }

  @discardableResult
  mutating func parseKeywords(_ keywords: [String]) -> Bool {
    let substring = self
    guard keywords.allSatisfy({ parseKeyword($0) })
    else {
      self = substring
      return false
    }
    return true
  }

  @discardableResult
  mutating func parseKeyword(_ keyword: String) -> Bool {
    parseTrivia()
    let count = keyword.count
    guard prefix(count).uppercased() == keyword
    else {
      return false
    }
    removeFirst(count)
    return true
  }

  @discardableResult
  mutating func parseTrivia() -> String {
    var trivia = ""
    while !isEmpty {
      if hasPrefix("--") {
        guard let endIndex = firstIndex(of: "\n")
        else {
          removeAll()
          continue
        }
        removeFirst(distance(from: startIndex, to: endIndex))
        continue
      } else if let endIndex = firstIndex(where: { !$0.isWhitespace }), endIndex != startIndex {
        trivia.append(contentsOf: self[..<endIndex])
        removeFirst(distance(from: startIndex, to: endIndex))
        continue
      } else {
        break
      }
    }
    return trivia
  }
}

private struct SyntaxError: Error {}

extension PragmaTableInfo {
  var isInt: Bool {
    intTypes.contains(type.lowercased())
  }
}

private let intTypes: Set<String> = [
  "int", "integer", "bigint",
]

@DatabaseFunction("sqlitedata_icloud_uuidFromIDAndTable")
private func uuid(id: Int, table: String) -> UUID {
  Insecure.MD5.hash(data: Data("\(table):\(id)".utf8)).withUnsafeBytes { ptr in
    UUID(
      uuid: (
        ptr[0], ptr[1], ptr[2], ptr[3], ptr[4], ptr[5], ptr[6], ptr[7], ptr[8],
        ptr[9], ptr[10], ptr[11], ptr[12], ptr[13], ptr[14], ptr[15]
      )
    )
  }
}
