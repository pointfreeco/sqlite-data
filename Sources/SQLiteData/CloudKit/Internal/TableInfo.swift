#if canImport(CloudKit)
  import StructuredQueries
  #if EXCLUDE_EXPORTS
    package import StructuredQueriesCore
  #endif

  @Table
  package struct TableInfo: Codable, Hashable {
    let defaultValue: String?
    let isPrimaryKey: Bool
    package let name: String
    let isNotNull: Bool
    let type: String
  }
#endif
