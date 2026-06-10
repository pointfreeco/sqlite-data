#if canImport(CloudKit)
  import Foundation
  import StructuredQueries
  #if EXCLUDE_EXPORTS
    public import StructuredQueriesCore
  #else
    import StructuredQueriesCore
  #endif

  @Table
  package struct ForeignKey {
    let table: String
    let from: String
    let to: String
    let onUpdate: ForeignKeyAction
    let onDelete: ForeignKeyAction
    let isNotNull: Bool
  }
#endif
