#if canImport(CloudKit)
  import Foundation
  import StructuredQueriesCore

  package struct ForeignKey: QueryDecodable, QueryRepresentable {
    typealias QueryValue = Self

    let table: String
    let from: String
    let to: String
    let onUpdate: Action
    let onDelete: Action
    let notnull: Bool

    package init(decoder: inout some QueryDecoder) throws {
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

    static func all(
      _ tableName: String
    ) -> some StructuredQueriesCore.Statement<Self> {
      #sql(
        """
        SELECT \(columns)
        FROM pragma_foreign_key_list(\(bind: tableName)) AS "foreign_keys"
        JOIN pragma_table_info(\(bind: tableName)) AS "table_info"
          ON "foreign_keys"."from" = "table_info"."name"
        """
      )
    }

    static var columns: QueryFragment {
      """
      "table", "from", "to", "on_update", "on_delete", "notnull"
      """
    }
  }
#endif
