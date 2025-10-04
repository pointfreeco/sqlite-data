#if canImport(CloudKit) && canImport(CryptoKit)
  import CryptoKit
  import Foundation

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SyncEngine {
    /// Migrates integer primary-keyed tables and tables without primary keys to
    /// CloudKit-compatible, UUID primary keys.
    ///
    /// To synchronize a table to CloudKit it must have a primary key, and that primary key must
    /// be a globally unique identifier, such as a UUID. However, changing the type of a column
    /// in SQLite is a [multi-step process] that must be followed very carefully, otherwise you run
    /// the risk of corrupting your users' data.
    ///
    /// [multi-step process]: https://sqlite.org/lang_altertable.html#making_other_kinds_of_table_schema_changes
    ///
    /// This method is a general purpose tool that analyzes a set of tables to try to automatically
    /// perform that migration for you. It performs the following steps:
    ///
    ///   * Computes a random salt to use for backfilling existing integer primary keys with UUIDs.
    ///   * For each table passed to this method:
    ///     * Creates a new table with essentially the same schema, but the following changes:
    ///       * A new temporary name is given to the table.
    ///       * If an integer primary key exists, it is changed to a "TEXT" column with a
    ///         "NOT NULL PRIMARY KEY ON CONFLICT REPLACE DEFAULT" constraint, and a default of
    ///         "uuid()" if no `uuid` argument is given, otherwise the argument is used.
    ///       * If no primary key exists, one is added with the same constraints as above.
    ///       * All integer foreign keys are changed to "TEXT" columns with no other changes.
    ///     * All data from the existing table is copied over into the new table, but all integer
    ///       IDs (both primary and foreign keys) are transformed into UUIDs by MD5 hashing the
    ///       integer, the table name, and the salt mentioned above, and turning that hash into a
    ///       UUID.
    ///     * The existing table is dropped.
    ///     * Thew new table is renamed to have the same name as the table just dropped.
    ///   * Any indexes and stored triggers that were removed from dropping tables in the steps
    ///     above are recreated.
    ///   * Executes a "PRAGMA foreign_key_check;" query to make sure that the integrity of the data
    ///     is preserved.
    ///
    /// If all of those steps are performed without throwing an error, then your schema and data
    /// should have been successfully migrated to UUIDs. If an error is thrown for any reason,
    /// then it means the tool was not able to safely migrate your data and so you will need to
    /// perform the migration [manually](<doc:ManuallyMigratingPrimaryKeys>).
    ///
    /// - Parameters:
    ///   - db: A database connection.
    ///   - tables: Tables to migrate.
    ///   - uuidFunction: A UUID function to use for the default value of primary keys in your
    ///     tables' schemas. If `nil`, SQLite's `uuid` function will be used.
    public static func migratePrimaryKeys<each T: PrimaryKeyedTable>(
      _ db: Database,
      tables: repeat (each T).Type,
      uuid uuidFunction: (any ScalarDatabaseFunction<(), UUID>)? = nil
    ) throws
    where
      repeat (each T).PrimaryKey.QueryOutput: IdentifierStringConvertible,
      repeat (each T).TableColumns.PrimaryColumn: TableColumnExpression
    {
      let salt =
        (try uuidFunction.flatMap { uuid -> UUID? in
          try #sql("SELECT \(quote: uuid.name)()", as: UUID.self).fetchOne(db)
        }
        ?? UUID()).uuidString

      db.add(function: $backfillUUID)
      defer { db.remove(function: $backfillUUID) }

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
          migratedTableNames: migratedTableNames,
          salt: salt
        )
      }
      for sql in indicesAndTriggersSQL {
        try #sql(QueryFragment(stringLiteral: sql)).execute(db)
      }

      let foreignKeyChecks = try PragmaForeignKeyCheck.all.fetchAll(db)
      if !foreignKeyChecks.isEmpty {
        throw ForeignKeyCheckError(checks: foreignKeyChecks)
      }
    }
  }

  private struct MigrationError: LocalizedError {
    let reason: Reason
    enum Reason {
      case tableNotFound(String)
      case invalidPrimaryKey
      case invalidForeignKey
    }
    var errorDescription: String? {
      switch reason {
      case .tableNotFound(let tableName):
        return "Table not found. The table '\(tableName)' does not exist in the database."
      case .invalidPrimaryKey:
        return """
          Invalid primary key. The table must have either no primary key or a single integer \
          primary key to migrate.
          """
      case .invalidForeignKey:
        return """
          Invalid foreign key. All foreign keys must reference tables included in this migration.
          """
      }
    }
  }

  @available(iOS 16, macOS 13, tvOS 13, watchOS 9, *)
  extension PrimaryKeyedTable where TableColumns.PrimaryColumn: TableColumnExpression {
    fileprivate static func migratePrimaryKeyToUUID(
      db: Database,
      uuidFunction: (any ScalarDatabaseFunction<(), UUID>)? = nil,
      migratedTableNames: [String],
      salt: String
    ) throws {
      let schema =
        try SQLiteSchema
        .select(\.sql)
        .where { $0.type.eq(#bind(.table)) && $0.tableName.eq(tableName) }
        .fetchOne(db)
        ?? nil

      guard let schema
      else {
        throw MigrationError(reason: .tableNotFound(tableName))
      }

      let tableInfo = try PragmaTableInfo<Self>.all.fetchAll(db)
      let primaryKeys = tableInfo.filter(\.isPrimaryKey)
      guard
        (primaryKeys.count == 1 && primaryKeys[0].isInt)
          || primaryKeys.isEmpty
      else {
        throw MigrationError(reason: .invalidPrimaryKey)
      }
      guard primaryKeys.count <= 1
      else {
        throw MigrationError(reason: .invalidPrimaryKey)
      }

      let foreignKeys = try PragmaForeignKeyList<Self>.all.fetchAll(db)
      guard foreignKeys.allSatisfy({ migratedTableNames.contains($0.table) })
      else {
        throw MigrationError(reason: .invalidForeignKey)
      }

      let newTableName = "new_\(tableName)"
      let uuidFunction = uuidFunction?.name ?? "uuid"
      let newSchema = try schema.rewriteSchema(
        oldPrimaryKey: primaryKeys.first?.name,
        newPrimaryKey: columns.primaryKey.name,
        foreignKeys: foreignKeys.map(\.from),
        uuidFunction: uuidFunction
      )

      var newColumns: [String] = []
      var convertedColumns: [QueryFragment] = []
      if primaryKeys.first == nil {
        convertedColumns.append("NULL")
        newColumns.append(columns.primaryKey.name)
      }
      newColumns.append(contentsOf: tableInfo.map(\.name))
      convertedColumns.append(
        contentsOf: tableInfo.map { tableInfo -> QueryFragment in
          if tableInfo.name == primaryKey.name, tableInfo.isInt {
            return $backfillUUID(id: #sql("\(quote: tableInfo.name)"), table: tableName, salt: salt)
              .queryFragment
          } else if tableInfo.isInt,
            let foreignKey = foreignKeys.first(where: { $0.from == tableInfo.name })
          {
            return $backfillUUID(
              id: #sql("\(quote: foreignKey.from)"),
              table: foreignKey.table,
              salt: salt
            )
            .queryFragment
          } else {
            return QueryFragment(quote: tableInfo.name)
          }
        }
      )

      try #sql(QueryFragment(stringLiteral: newSchema)).execute(db)
      try #sql(
        """
        INSERT INTO \(quote: newTableName) \
        ("rowid", \(newColumns.map { "\(quote: $0)" }.joined(separator: ", ")))
        SELECT "rowid", \(convertedColumns.joined(separator: ", ")) \
        FROM \(Self.self)
        ORDER BY "rowid"
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

    mutating func parseIntegerAffinity() throws -> Bool {
      for type in intTypes {
        guard parseKeyword(type)
        else { continue }
        return true
      }
      return false
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
      intTypes.contains(type.uppercased())
    }
    var isText: Bool {
      textTypes.contains(type.uppercased())
    }
  }

  private let intTypes: Set<String> = [
    "INT", "INTEGER", "BIGINT",
  ]

  private let textTypes: Set<String> = [
    "TEXT", "VARCHAR",
  ]

  @DatabaseFunction("sqlitedata_icloud_backfillUUID")
  private func backfillUUID(id: Int, table: String, salt: String) -> UUID {
    return Insecure.MD5.hash(data: Data("\(table):\(id):\(salt)".utf8)).withUnsafeBytes { ptr in
      UUID(
        uuid: (
          ptr[0], ptr[1], ptr[2], ptr[3], ptr[4], ptr[5], ptr[6], ptr[7], ptr[8],
          ptr[9], ptr[10], ptr[11], ptr[12], ptr[13], ptr[14], ptr[15]
        )
      )
    }
  }

  struct ForeignKeyCheckError: LocalizedError {
    let checks: [PragmaForeignKeyCheck]
    var errorDescription: String? {
      checks.map {
        """
        \($0.table)'s reference to \($0.parent) has a violation.
        """
      }
      .joined(separator: "\n")
    }
  }
#endif
