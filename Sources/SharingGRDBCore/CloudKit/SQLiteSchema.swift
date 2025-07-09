import StructuredQueriesCore

struct SQLiteSchema: QueryDecodable, QueryRepresentable {
  typealias QueryValue = Self

  let type: String
  let name: String
  let tableName: String
  let sql: String?

  init(decoder: inout some QueryDecoder) throws {
    guard
      let type = try decoder.decode(String.self),
      let name = try decoder.decode(String.self),
      let tableName = try decoder.decode(String.self)
    else {
      throw QueryDecodingError.missingRequiredColumn
    }
    self.type = type
    self.name = name
    self.tableName = tableName
    self.sql = try decoder.decode(String.self)
  }

  static var all: some StructuredQueriesCore.Statement<Self> {
    SQLQueryExpression(
      """
      SELECT \(columns) FROM "sqlite_schema"
      """,
      as: Self.self
    )
  }

  static var columns: QueryFragment {
    """
    "type", "name", "tbl_name", "sql" 
    """
  }
}
