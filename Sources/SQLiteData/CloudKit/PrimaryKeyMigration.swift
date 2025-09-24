@available(iOS 16, macOS 13, tvOS 13, watchOS 9, *)
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
      // TODO: if no primary key, need to add one
      return
    }

    let foreignKeys = try PragmaForeignKeyList<Self>.all.fetchAll(db)
    // TODO: capture indices, triggers and views
    defer {
      // TODO: restore indices, triggers and views
    }

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
