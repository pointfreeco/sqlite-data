#if canImport(CloudKit)
  import StructuredQueriesCore

  extension RecordType {
    public struct TableColumns: StructuredQueriesCore.TableDefinition, StructuredQueriesCore
        .PrimaryKeyedTableDefinition
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
      public struct TableColumns: StructuredQueriesCore.TableDefinition {
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
      nonisolated(unsafe) public static let columns = TableColumns()

      public static let tableName = RecordType.tableName

      public init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
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

      public init(_ other: RecordType) {
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

  extension RecordType: StructuredQueriesCore.Table, StructuredQueriesCore.PrimaryKeyedTable {
    nonisolated(unsafe) public static let columns = TableColumns()
    public static let tableName = "sqlitedata_icloud_recordTypes"
    public init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
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
