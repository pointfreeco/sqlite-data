import StructuredQueriesCore

extension UnsyncedRecordID {
  public nonisolated struct TableColumns: StructuredQueriesCore.TableDefinition {
    public typealias QueryValue = UnsyncedRecordID
    public let recordName = StructuredQueriesCore.TableColumn<QueryValue, String>(
      "recordName",
      keyPath: \QueryValue.recordName
    )
    public let zoneName = StructuredQueriesCore.TableColumn<QueryValue, String>(
      "zoneName",
      keyPath: \QueryValue.zoneName
    )
    public let ownerName = StructuredQueriesCore.TableColumn<QueryValue, String>(
      "ownerName",
      keyPath: \QueryValue.ownerName
    )
    public static var allColumns: [any StructuredQueriesCore.TableColumnExpression] {
      [QueryValue.columns.recordName, QueryValue.columns.zoneName, QueryValue.columns.ownerName]
    }
    public static var writableColumns: [any StructuredQueriesCore.WritableTableColumnExpression] {
      [QueryValue.columns.recordName, QueryValue.columns.zoneName, QueryValue.columns.ownerName]
    }
    public var queryFragment: QueryFragment {
      "\(self.recordName), \(self.zoneName), \(self.ownerName)"
    }
  }
}

nonisolated extension UnsyncedRecordID: StructuredQueriesCore.Table {
  public nonisolated static var columns: TableColumns {
    TableColumns()
  }
  public nonisolated static var tableName: String {
    "sqlitedata_icloud_unsyncedRecordIDs"
  }
  public nonisolated init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
    let recordName = try decoder.decode(String.self)
    let zoneName = try decoder.decode(String.self)
    let ownerName = try decoder.decode(String.self)
    guard let recordName else {
      throw QueryDecodingError.missingRequiredColumn
    }
    guard let zoneName else {
      throw QueryDecodingError.missingRequiredColumn
    }
    guard let ownerName else {
      throw QueryDecodingError.missingRequiredColumn
    }
    self.recordName = recordName
    self.zoneName = zoneName
    self.ownerName = ownerName
  }
}
