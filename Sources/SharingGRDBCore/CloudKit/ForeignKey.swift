import StructuredQueries

struct ForeignKey: QueryDecodable, QueryRepresentable {
  typealias QueryValue = Self

  let table: String
  let from: String
  let to: String
  let onUpdate: Action
  let onDelete: Action
  let notnull: Bool

  init(decoder: inout some QueryDecoder) throws {
    guard
      let table = try decoder.decode(String.self),
      let from = try decoder.decode(String.self),
      let to = try decoder.decode(String.self),
      let onUpdate = try decoder.decode(Action.self),
      let onDelete = try decoder.decode(Action.self),
      let notnull = try decoder.decode(Bool.self)
    else {
      throw QueryDecodingError.missingRequiredColumn
    }
    self.table = table
    self.from = from
    self.to = to
    self.onUpdate = onUpdate
    self.onDelete = onDelete
    self.notnull = notnull
  }

  enum Action: String, QueryBindable {
    case cascade = "CASCADE"
    case restrict = "RESTRICT"
    case setDefault = "SET DEFAULT"
    case setNull = "SET NULL"
    case noAction = "NO ACTION"
  }

  static func all<T: StructuredQueriesCore.Table>(
    _ table: T.Type
  ) -> some StructuredQueriesCore.Statement<Self> {
    SQLQueryExpression(
      """
      SELECT \(ForeignKey.columns) 
      FROM pragma_foreign_key_list(\(bind: table.tableName)) AS "foreign_keys"
      JOIN pragma_table_info(\(bind: table.tableName)) AS "table_info" 
        ON "foreign_keys"."from" = "table_info"."name"
      """,
      as: ForeignKey.self
    )
  }

  static var columns: QueryFragment {
    """
    "table", "from", "to", "on_update", "on_delete", "notnull"
    """
  }

  func createTriggers<T: PrimaryKeyedTable>(for _: T.Type, db: Database) throws {
    switch onDelete {
    case .cascade:
      try SQLQueryExpression(
        """
        CREATE TEMPORARY TRIGGER
          "\(raw: .sqliteDataCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: table)_onDeleteCascade"
        AFTER DELETE ON \(quote: table)
        FOR EACH ROW BEGIN
          DELETE FROM \(T.self)
          WHERE \(quote: from) = "old".\(quote: to);
        END
        """
      )
      .execute(db)

    case .restrict:
      try SQLQueryExpression(
        """
        CREATE TEMPORARY TRIGGER
          "\(raw: .sqliteDataCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: table)_onDeleteRestrict"
        AFTER DELETE ON \(quote: table)
        FOR EACH ROW BEGIN
          SELECT RAISE(ABORT, 'FOREIGN KEY constraint failed')
          FROM \(T.self)
          WHERE \(quote: from) = "old".\(quote: to);
        END
        """
      )
      .execute(db)

    case .setDefault:
      let defaultValue =
        try SQLQueryExpression(
          """
          SELECT "dflt_value"
          FROM pragma_table_info(\(bind: T.tableName))
          WHERE "name" = \(bind: from)
          """,
          as: String?.self
        )
        .fetchOne(db) ?? nil

      try SQLQueryExpression(
        """
        CREATE TEMPORARY TRIGGER
          "\(raw: .sqliteDataCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: table)_onDeleteSetDefault"
        AFTER DELETE ON \(quote: table)
        FOR EACH ROW BEGIN
          UPDATE \(T.self)
          SET \(quote: from) = \(raw: defaultValue ?? "NULL")
          WHERE \(quote: from) = "old".\(quote: to);
        END
        """
      )
      .execute(db)

    case .setNull:
      try SQLQueryExpression(
        """
        CREATE TEMPORARY TRIGGER
          "\(raw: .sqliteDataCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: table)_onDeleteSetNull"
        AFTER DELETE ON \(quote: table)
        FOR EACH ROW BEGIN
          UPDATE \(T.self)
          SET \(quote: from) = NULL
          WHERE \(quote: from) = "old".\(quote: to);
        END
        """
      )
      .execute(db)
    case .noAction:
      break
    }

    switch onUpdate {
    case .cascade:
      try SQLQueryExpression(
        """
        CREATE TEMPORARY TRIGGER
          "\(raw: .sqliteDataCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: table)_onUpdateCascade"
        AFTER UPDATE ON \(quote: table)
        FOR EACH ROW BEGIN
          UPDATE \(T.self)
          SET \(quote: from) = "new".\(quote: to)
          WHERE \(quote: from) = "old".\(quote: to);
        END
        """
      )
      .execute(db)

    case .restrict:
      try SQLQueryExpression(
        """
        CREATE TEMPORARY TRIGGER
          "\(raw: .sqliteDataCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: table)_onUpdateRestrict"
        AFTER UPDATE ON \(quote: table)
        FOR EACH ROW BEGIN
          SELECT RAISE(ABORT, 'FOREIGN KEY constraint failed')
          FROM \(T.self)
          WHERE \(quote: from) = "old".\(quote: to);
        END
        """
      )
      .execute(db)

    case .setDefault:
      let defaultValue =
        try SQLQueryExpression(
          """
          SELECT "dflt_value"
          FROM pragma_table_info(\(bind: T.tableName))
          WHERE "name" = \(bind: from)
          """,
          as: String?.self
        )
        .fetchOne(db) ?? nil

      try SQLQueryExpression(
        """
        CREATE TEMPORARY TRIGGER
          "\(raw: .sqliteDataCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: table)_onUpdateSetDefault"
        AFTER UPDATE ON \(quote: table)
        FOR EACH ROW BEGIN
          UPDATE \(T.self)
          SET \(quote: from) = \(raw: defaultValue ?? "NULL")
          WHERE \(quote: from) = "old".\(quote: to);
        END
        """
      )
      .execute(db)

    case .setNull:
      try SQLQueryExpression(
        """
        CREATE TEMPORARY TRIGGER
          "\(raw: .sqliteDataCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: table)_onUpdateSetNull"
        AFTER UPDATE ON \(quote: table)
        FOR EACH ROW BEGIN
          UPDATE \(T.self)
          SET \(quote: from) = NULL
          WHERE \(quote: from) = "old".\(quote: to);
        END
        """
      )
      .execute(db)
    case .noAction:
      break
    }
  }

  func dropTriggers<T: PrimaryKeyedTable>(for _: T.Type, db: Database) throws {
    switch onDelete {
    case .cascade:
      try SQLQueryExpression(
        """
        DROP TRIGGER
          "\(raw: .sqliteDataCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: table)_onDeleteCascade"
        """
      )
      .execute(db)

    case .setNull:
      try SQLQueryExpression(
        """
        DROP TRIGGER
          "\(raw: .sqliteDataCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: table)_onDeleteSetNull"
        """
      )
      .execute(db)

    case .setDefault:
      try SQLQueryExpression(
        """
        DROP TRIGGER
          "\(raw: .sqliteDataCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: table)_onDeleteSetDefault"
        """
      )
      .execute(db)

    case .restrict:
      try SQLQueryExpression(
        """
        DROP TRIGGER
          "\(raw: .sqliteDataCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: table)_onDeleteRestrict"
        """
      )
      .execute(db)

    case .noAction:
      break
    }

    switch onUpdate {
    case .cascade:
      try SQLQueryExpression(
        """
        DROP TRIGGER
          "\(raw: .sqliteDataCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: table)_onUpdateCascade"
        """
      )
      .execute(db)

    case .setNull:
      try SQLQueryExpression(
        """
        DROP TRIGGER
          "\(raw: .sqliteDataCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: table)_onUpdateSetNull"
        """
      )
      .execute(db)

    case .setDefault:
      try SQLQueryExpression(
        """
        DROP TRIGGER
          "\(raw: .sqliteDataCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: table)_onUpdateSetDefault"
        """
      )
      .execute(db)

    case .restrict:
      try SQLQueryExpression(
        """
        DROP TRIGGER
          "\(raw: .sqliteDataCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: table)_onUpdateRestrict"
        """
      )
      .execute(db)

    case .noAction:
      break
    }
  }
}
