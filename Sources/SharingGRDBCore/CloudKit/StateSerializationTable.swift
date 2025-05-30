import CloudKit
import StructuredQueries

// @Table("\(String.sqliteDataCloudKitSchemaName)_stateSerialization")
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
package struct StateSerialization {
  // @Column(primaryKey: true)
  package var scope: CKDatabase.Scope
  // @Column(as: CKSyncEngine.State.Serialization.JSONRepresentation.self)
  package var data: CKSyncEngine.State.Serialization
}

extension CKDatabase.Scope: @retroactive QueryBindable {
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *) extension StateSerialization: StructuredQueriesCore.Table, StructuredQueriesCore.PrimaryKeyedTable {
  public struct TableColumns: StructuredQueriesCore.TableDefinition, StructuredQueriesCore.PrimaryKeyedTableDefinition {
    public typealias QueryValue = StateSerialization
    public let scope = StructuredQueriesCore.TableColumn<QueryValue, CKDatabase.Scope>("scope", keyPath: \QueryValue.scope)
    public let data = StructuredQueriesCore.TableColumn<QueryValue, CKSyncEngine.State.Serialization.JSONRepresentation>("data", keyPath: \QueryValue.data)
    public var primaryKey: StructuredQueriesCore.TableColumn<QueryValue, CKDatabase.Scope> {
      self.scope
    }
    public static var allColumns: [any StructuredQueriesCore.TableColumnExpression] {
      [QueryValue.columns.scope, QueryValue.columns.data]
    }
  }
  public struct Draft: StructuredQueriesCore.TableDraft {
    public typealias PrimaryTable = StateSerialization
    package var scope: CKDatabase.Scope?
    package var data: CKSyncEngine.State.Serialization
    public struct TableColumns: StructuredQueriesCore.TableDefinition {
      public typealias QueryValue = StateSerialization.Draft
      public let scope = StructuredQueriesCore.TableColumn<QueryValue, CKDatabase.Scope?>("scope", keyPath: \QueryValue.scope)
      public let data = StructuredQueriesCore.TableColumn<QueryValue, CKSyncEngine.State.Serialization.JSONRepresentation>("data", keyPath: \QueryValue.data)
      public static var allColumns: [any StructuredQueriesCore.TableColumnExpression] {
        [QueryValue.columns.scope, QueryValue.columns.data]
      }
    }
    public static let columns = TableColumns()
    public static let tableName = StateSerialization.tableName
    public init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
      self.scope = try decoder.decode(CKDatabase.Scope.self)
      let data = try decoder.decode(CKSyncEngine.State.Serialization.JSONRepresentation.self)
      guard let data else {
        throw QueryDecodingError.missingRequiredColumn
      }
      self.data = data
    }
    public init(_ other: StateSerialization) {
      self.scope = other.scope
      self.data = other.data
    }
    public init(
      scope: CKDatabase.Scope? = nil,
      data: CKSyncEngine.State.Serialization
    ) {
      self.scope = scope
      self.data = data
    }
  }
  public static let columns = TableColumns()
  public static let tableName = "sqlitedata_icloud_stateSerialization"
  public init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
    let scope = try decoder.decode(CKDatabase.Scope.self)
    let data = try decoder.decode(CKSyncEngine.State.Serialization.JSONRepresentation.self)
    guard let scope else {
      throw QueryDecodingError.missingRequiredColumn
    }
    guard let data else {
      throw QueryDecodingError.missingRequiredColumn
    }
    self.scope = scope
    self.data = data
  }
}
