#if canImport(CloudKit)
  import StructuredQueriesCore

  extension RecordType {
    public nonisolated struct TableColumns: StructuredQueriesCore.TableDefinition,
      StructuredQueriesCore.PrimaryKeyedTableDefinition
    {
      public typealias QueryValue = RecordType
      public let tableName = StructuredQueriesCore.TableColumn<QueryValue, String>(
        "tableName",
        keyPath: \QueryValue.tableName
      )
      public let schema = StructuredQueriesCore.TableColumn<QueryValue, String>(
        "schema",
        keyPath: \QueryValue.schema
      )
      public let tableInfo = StructuredQueriesCore.TableColumn<
        QueryValue, Set<TableInfo>.JSONRepresentation
      >("tableInfo", keyPath: \QueryValue.tableInfo)
      public var primaryKey: StructuredQueriesCore.TableColumn<QueryValue, String> {
        self.tableName
      }
      public static var allColumns: [any StructuredQueriesCore.TableColumnExpression] {
        [QueryValue.columns.tableName, QueryValue.columns.schema, QueryValue.columns.tableInfo]
      }
      public static var writableColumns: [any StructuredQueriesCore.WritableTableColumnExpression] {
        [QueryValue.columns.tableName, QueryValue.columns.schema, QueryValue.columns.tableInfo]
      }
      public var queryFragment: QueryFragment {
        "\(self.tableName), \(self.schema), \(self.tableInfo)"
      }
    }

    public struct Draft: StructuredQueriesCore.TableDraft {
      public typealias PrimaryTable = RecordType
      package let tableName: String?
      package let schema: String
      package let tableInfo: Set<TableInfo>
      public nonisolated struct TableColumns: StructuredQueriesCore.TableDefinition {
        public typealias QueryValue = Draft
        public let tableName = StructuredQueriesCore.TableColumn<QueryValue, String?>(
          "tableName",
          keyPath: \QueryValue.tableName
        )
        public let schema = StructuredQueriesCore.TableColumn<QueryValue, String>(
          "schema",
          keyPath: \QueryValue.schema
        )
        public let tableInfo = StructuredQueriesCore.TableColumn<
          QueryValue, Set<TableInfo>.JSONRepresentation
        >("tableInfo", keyPath: \QueryValue.tableInfo)
        public static var allColumns: [any StructuredQueriesCore.TableColumnExpression] {
          [QueryValue.columns.tableName, QueryValue.columns.schema, QueryValue.columns.tableInfo]
        }
        public static var writableColumns: [any StructuredQueriesCore.WritableTableColumnExpression]
        {
          [QueryValue.columns.tableName, QueryValue.columns.schema, QueryValue.columns.tableInfo]
        }
        public var queryFragment: QueryFragment {
          "\(self.tableName), \(self.schema), \(self.tableInfo)"
        }
      }
      public nonisolated static var columns: TableColumns {
        TableColumns()
      }

      public nonisolated static var tableName: String {
        RecordType.tableName
      }

      public nonisolated init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
        self.tableName = try decoder.decode(String.self)
        let schema = try decoder.decode(String.self)
        let tableInfo = try decoder.decode(Set<TableInfo>.JSONRepresentation.self)
        guard let schema else {
          throw QueryDecodingError.missingRequiredColumn
        }
        guard let tableInfo else {
          throw QueryDecodingError.missingRequiredColumn
        }
        self.schema = schema
        self.tableInfo = tableInfo
      }

      public nonisolated init(_ other: RecordType) {
        self.tableName = other.tableName
        self.schema = other.schema
        self.tableInfo = other.tableInfo
      }
      public init(
        tableName: String? = nil,
        schema: String,
        tableInfo: Set<TableInfo>
      ) {
        self.tableName = tableName
        self.schema = schema
        self.tableInfo = tableInfo
      }
    }
  }

  nonisolated extension RecordType: StructuredQueriesCore.Table, StructuredQueriesCore
      .PrimaryKeyedTable
  {
    public nonisolated static var columns: TableColumns {
      TableColumns()
    }
    public nonisolated static var tableName: String {
      "sqlitedata_icloud_recordTypes"
    }
    public nonisolated init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
      let tableName = try decoder.decode(String.self)
      let schema = try decoder.decode(String.self)
      let tableInfo = try decoder.decode(Set<TableInfo>.JSONRepresentation.self)
      guard let tableName else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let schema else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let tableInfo else {
        throw QueryDecodingError.missingRequiredColumn
      }
      self.tableName = tableName
      self.schema = schema
      self.tableInfo = tableInfo
    }
  }
#endif
