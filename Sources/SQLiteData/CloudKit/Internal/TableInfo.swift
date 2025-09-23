import StructuredQueriesCore

@Selection
package struct TableInfo: Codable, Hashable, QueryDecodable, QueryRepresentable {
  let defaultValue: String?
  let isPrimaryKey: Bool
  package let name: String
  let isNotNull: Bool
  let type: String
}
