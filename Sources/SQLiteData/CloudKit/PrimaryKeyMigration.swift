import Foundation

@available(iOS 16, macOS 13, tvOS 13, watchOS 9, *)
extension Database {
  public func migrateToSyncEnginePrimaryKeys<each T: PrimaryKeyedTable>(
    _ tables: repeat (each T).Type,
    uuidFunction: (any ScalarDatabaseFunction<(), UUID>)? = nil
  ) throws where repeat (each T).PrimaryKey.QueryOutput: IdentifierStringConvertible {
    for table in repeat each tables {
      try table.migratePrimaryKeyToUUID(db: self, uuidFunction: uuidFunction)
    }
  }
}

private struct MigrationError: Error {
}

@available(iOS 16, macOS 13, tvOS 13, watchOS 9, *)
extension PrimaryKeyedTable {
  fileprivate static func migratePrimaryKeyToUUID(
    db: Database,
    uuidFunction: (any ScalarDatabaseFunction<(), UUID>)? = nil
  ) throws {
    let schema =
      try SQLiteSchema
      .select(\.sql)
      .where { $0.tableName.eq(tableName) }
      .fetchOne(db)
      ?? nil

    guard let schema
    else {
      throw MigrationError()
    }

    let tableInfo = try PragmaTableInfo<Self>.all.fetchAll(db)
    let primaryKeys = tableInfo.filter(\.isPrimaryKey)
    guard primaryKeys.count <= 1
    else {
      throw MigrationError()
    }

    let foreignKeys = try PragmaForeignKeyList<Self>.all.fetchAll(db)
    // TODO: capture indices, triggers and views
    defer {
      // TODO: restore indices, triggers and views
    }

    let newTableName = "new_\(tableName)"
    let uuidFunction = uuidFunction?.name ?? "uuid"
    // TODO: Validate foreign key tables are accounted for in migration
    let newSchema = try schema.rewriteSchema(
      primaryKey: primaryKeys.first?.name,
      foreignKeys: foreignKeys.map(\.from),
      uuidFunction: uuidFunction
    )
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
    primaryKey: String?,
    foreignKeys: [String],
    uuidFunction: String
  ) throws -> String {
    var substring = self[...]
    return try substring.rewriteSchema(
      primaryKey: primaryKey,
      foreignKeys: foreignKeys,
      uuidFunction: uuidFunction
    )
  }
}

extension Substring {
  mutating func rewriteSchema(
    primaryKey: String?,
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
    if primaryKey == nil {
      newSchema.append(
        """
        "id" TEXT PRIMARY KEY NOT NULL \
        ON CONFLICT REPLACE DEFAULT (\(uuidFunction.quoted())()),\(trivia)
        """
      )
    }
    while try !parseTableConstraint(), let columnName = try parseIdentifier() {
      parseTrivia()
      if columnName == primaryKey {
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
      if (try? parseBalanced(upTo: ",")) != nil {
        if columnName == primaryKey {
          index = startIndex
        }
        removeFirst()
      } else {
        try parseBalanced(upTo: ")")
        if columnName == primaryKey {
          index = startIndex
        }
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
