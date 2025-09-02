#if canImport(CloudKit)
  import CloudKit

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension PendingRecordZoneChange {
    public nonisolated struct TableColumns: StructuredQueriesCore.TableDefinition {
      public typealias QueryValue = PendingRecordZoneChange
      public let pendingRecordZoneChange = StructuredQueriesCore.TableColumn<
        QueryValue, CKSyncEngine.PendingRecordZoneChange.DataRepresentation
      >("pendingRecordZoneChange", keyPath: \QueryValue.pendingRecordZoneChange)
      public static var allColumns: [any StructuredQueriesCore.TableColumnExpression] {
        [QueryValue.columns.pendingRecordZoneChange]
      }
      public static var writableColumns: [any StructuredQueriesCore.WritableTableColumnExpression] {
        [QueryValue.columns.pendingRecordZoneChange]
      }
      public var queryFragment: QueryFragment {
        "\(self.pendingRecordZoneChange)"
      }
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  nonisolated extension PendingRecordZoneChange: StructuredQueriesCore.Table {
    public nonisolated static var columns: TableColumns {
      TableColumns()
    }
    public nonisolated static var tableName: String {
      "sqlitedata_icloud_pendingRecordZoneChanges"
    }
    public nonisolated init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
      let pendingRecordZoneChange = try decoder.decode(
        CKSyncEngine.PendingRecordZoneChange.DataRepresentation.self
      )
      guard let pendingRecordZoneChange else {
        throw QueryDecodingError.missingRequiredColumn
      }
      self.pendingRecordZoneChange = pendingRecordZoneChange
    }
  }
#endif
