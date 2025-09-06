#if canImport(CloudKit)
  import Foundation
  import StructuredQueriesCore

  @Selection
  package struct ForeignKey {
    let table: String
    let from: String
    let to: String
    let onUpdate: ForeignKeyAction
    let onDelete: ForeignKeyAction
    let isNotNull: Bool
  }
#endif
