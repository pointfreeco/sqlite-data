#if canImport(CloudKit)
  import Foundation
  public import StructuredQueries

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
