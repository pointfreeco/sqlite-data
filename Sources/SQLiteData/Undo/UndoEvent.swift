import Foundation
import StructuredQueriesCore

public struct UndoAffectedRow: Sendable, Hashable {
  public let tableName: String
  public let rowID: Int

  package init(tableName: String, rowID: Int) {
    self.tableName = tableName
    self.rowID = rowID
  }

  public init<T: Table>(table: T.Type, rowID: Int) {
    self.tableName = T.tableName
    self.rowID = rowID
  }

  public func id<T: Table & Identifiable>(
    as type: T.Type
  ) -> T.ID? where T.ID: BinaryInteger {
    tableName == T.tableName ? T.ID(rowID) : nil
  }
}

public struct UndoEvent: Sendable, Equatable {
  public enum Kind: Sendable, Equatable {
    case undo
    case redo
  }

  public let kind: Kind
  public let group: UndoGroup
  public let affectedRows: Set<UndoAffectedRow>

  public init(kind: Kind, group: UndoGroup, affectedRows: Set<UndoAffectedRow>) {
    self.kind = kind
    self.group = group
    self.affectedRows = affectedRows
  }

  public func ids<T: Table & Identifiable>(
    for type: T.Type
  ) -> Set<T.ID>? where T.ID: BinaryInteger {
    let ids = Set(affectedRows.compactMap { $0.id(as: type) })
    return ids.isEmpty ? nil : ids
  }
}
