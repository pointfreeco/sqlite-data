import StructuredQueries

struct ForeignKey: QueryDecodable, QueryRepresentable {
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

  static var columns: QueryFragment {
    """
    "table", "from", "to", "on_update", "on_delete", "notnull"
    """
  }
}
