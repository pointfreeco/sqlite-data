#if canImport(CloudKit)
  import CloudKit
  import StructuredQueriesCore

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension StateSerialization {
    public nonisolated struct TableColumns: StructuredQueriesCore.TableDefinition,
      StructuredQueriesCore.PrimaryKeyedTableDefinition
    {
      public typealias QueryValue = StateSerialization
      public let scope = StructuredQueriesCore.TableColumn<
        QueryValue, CKDatabase.Scope.RawValueRepresentation
      >("scope", keyPath: \QueryValue.scope)
      public let data = StructuredQueriesCore.TableColumn<
        QueryValue, CKSyncEngine.State.Serialization.JSONRepresentation
      >("data", keyPath: \QueryValue.data)
      public var primaryKey:
        StructuredQueriesCore.TableColumn<QueryValue, CKDatabase.Scope.RawValueRepresentation>
      {
        self.scope
      }
      public static var allColumns: [any StructuredQueriesCore.TableColumnExpression] {
        [QueryValue.columns.scope, QueryValue.columns.data]
      }
      public static var writableColumns: [any StructuredQueriesCore.WritableTableColumnExpression] {
        [QueryValue.columns.scope, QueryValue.columns.data]
      }
      public var queryFragment: QueryFragment {
        "\(self.scope), \(self.data)"
      }
    }

    public struct Draft: StructuredQueriesCore.TableDraft {
      public typealias PrimaryTable = StateSerialization
      package var scope: CKDatabase.Scope?
      package var data: CKSyncEngine.State.Serialization
      public nonisolated struct TableColumns: StructuredQueriesCore.TableDefinition {
        public typealias QueryValue = Draft
        public let scope = StructuredQueriesCore.TableColumn<
          QueryValue, CKDatabase.Scope.RawValueRepresentation?
        >("scope", keyPath: \QueryValue.scope)
        public let data = StructuredQueriesCore.TableColumn<
          QueryValue, CKSyncEngine.State.Serialization.JSONRepresentation
        >("data", keyPath: \QueryValue.data)
        public static var allColumns: [any StructuredQueriesCore.TableColumnExpression] {
          [QueryValue.columns.scope, QueryValue.columns.data]
        }
        public static var writableColumns: [any StructuredQueriesCore.WritableTableColumnExpression]
        {
          [QueryValue.columns.scope, QueryValue.columns.data]
        }
        public var queryFragment: QueryFragment {
          "\(self.scope), \(self.data)"
        }
      }
      public nonisolated static var columns: TableColumns {
        TableColumns()
      }

      public nonisolated static var tableName: String {
        StateSerialization.tableName
      }

      public nonisolated init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
        self.scope = try decoder.decode(CKDatabase.Scope.RawValueRepresentation.self)
        let data = try decoder.decode(CKSyncEngine.State.Serialization.JSONRepresentation.self)
        guard let data else {
          throw QueryDecodingError.missingRequiredColumn
        }
        self.data = data
      }

      public nonisolated init(_ other: StateSerialization) {
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
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  nonisolated extension StateSerialization: StructuredQueriesCore.Table, StructuredQueriesCore
      .PrimaryKeyedTable
  {
    public nonisolated static var columns: TableColumns {
      TableColumns()
    }
    public nonisolated static var tableName: String {
      "sqlitedata_icloud_stateSerialization"
    }
    public nonisolated init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
      let scope = try decoder.decode(CKDatabase.Scope.RawValueRepresentation.self)
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
#endif
