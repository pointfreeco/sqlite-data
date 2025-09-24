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
      // TODO: throw error
      return
    }

    let tableInfo = try PragmaTableInfo<Self>.all.fetchAll(db)
    guard let primaryKey = tableInfo.first(where: \.isPrimaryKey)
    else {
      // TODO: validate exactly one primary key
      // TODO: if no primary key, need to add one
      return
    }

    let foreignKeys = try PragmaForeignKeyList<Self>.all.fetchAll(db)
    // TODO: capture indices, triggers and views
    defer {
      // TODO: restore indices, triggers and views
    }

    var parts: [TablePart] = []
    var parenDepth = 0
    var currentScope: Scope?
    var startIndex = schema.startIndex
    var index = startIndex
    while index < schema.endIndex {
      func advance() {
        index = schema.index(after: index)
      }
      var peek: Character? {
        schema.index(index, offsetBy: 1, limitedBy: schema.endIndex).map { schema[$0] }
      }
      defer { advance() }

      let character = schema[index]
      switch (currentScope, character) {
      case (nil, "-") where peek == "-":
        currentScope = .comment
      case (.comment, "\n"):
        currentScope = nil
        startIndex = index
      case (nil, "'"),
        (nil, #"""#),
        (nil, "`"),
        (nil, "["):
        currentScope = .quote(character)
      case (.quote("'"), "'") where peek == "'",
        (.quote(#"""#), #"""#) where peek == #"""#,
        (.quote("`"), "`") where peek == "`":
        advance()
        continue
      case (.quote("'"), "'"),
        (.quote(#"""#), #"""#),
        (.quote("`"), "`"),
        (.quote("["), "]"):
        currentScope = nil
      case (.some, _):
        continue
      case (nil, "("):
        defer { parenDepth += 1 }
        if parenDepth == 0 {
          parts.append(.preamble(String(schema[startIndex...index])))
          startIndex = schema.index(after: index)
        }
      case (nil, ")"):
        defer { parenDepth -= 1 }
        if parenDepth == 1 {
          // TODO: also handle if its a constraint
          parts.append(.columnDefinition(String(schema[startIndex..<index])))
          parts.append(.tableOptions(String(schema[index...])))
        }
      case (nil, ","):
        // TODO: also handle if its a constraint
        parts.append(.columnDefinition(String(schema[startIndex...index])))
        startIndex = schema.index(after: index)
        continue
      default:
        continue
      }
    }

    let newTableName = "new_\(tableName)"
    let uuidFunction = uuidFunction?.name.quoted() ?? "uuid"
    let newParts = parts.map { part in
      switch part {
      case .preamble(var text):
        text.replace(" \(tableName) ", with: " \(newTableName) ")
        text.replace("\"\(tableName)\"", with: "\"\(newTableName)\"")
        return TablePart.preamble(text)
      case .columnDefinition(let text):
        let columnName = columnName(definition: text)
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
            "\(primaryKey.name)" \
            TEXT \
            PRIMARY KEY \
            NOT NULL \
            ON CONFLICT REPLACE \
            DEFAULT (\(uuidFunction)())\
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

private enum Scope {
  case comment
  case quote(Character)
}

extension StringProtocol {
  fileprivate func quoted() -> String {
    #"""# + replacingOccurrences(of: #"""#, with: #""""#) + #"""#
  }

  fileprivate func unquoted() -> String? {
    guard hasPrefix(#"""#), hasSuffix(#"""#) else { return nil }
    return dropFirst().dropLast().replacingOccurrences(of: #""""#, with: #"""#)
  }
}
