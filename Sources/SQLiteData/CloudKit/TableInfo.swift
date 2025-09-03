import StructuredQueriesCore

package struct TableInfo: Codable, Hashable, QueryDecodable, QueryRepresentable {
  typealias QueryValue = Self

  let defaultValue: String?
  let isPrimaryKey: Bool
  let name: String
  let notNull: Bool
  let type: String

  package init(decoder: inout some QueryDecoder) throws {
    self.defaultValue = try decoder.decode(String.self)
    guard
      let isPrimaryKey = try decoder.decode(Bool.self),
      let name = try decoder.decode(String.self),
      let notNull = try decoder.decode(Bool.self),
      let type = try decoder.decode(String.self)
    else {
      throw QueryDecodingError.missingRequiredColumn
    }
    self.isPrimaryKey = isPrimaryKey
    self.name = name
    self.notNull = notNull
    self.type = type
  }

  static func all(
    _ tableName: String
  ) -> some StructuredQueriesCore.Statement<Self> {
    #sql(
      """
      SELECT \(columns) FROM pragma_table_info(\(bind: tableName))
      """,
      as: Self.self
    )
  }

  static var columns: QueryFragment {
    """
    "dflt_value", "pk", "name", "notnull", "type" 
    """
  }
}
