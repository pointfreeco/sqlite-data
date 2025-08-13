#if canImport(CloudKit)
  import CloudKit

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SyncMetadata {
    public nonisolated struct TableColumns: StructuredQueriesCore.TableDefinition {
      public typealias QueryValue = SyncMetadata
      public let recordPrimaryKey = StructuredQueriesCore.TableColumn<QueryValue, String>(
        "recordPrimaryKey",
        keyPath: \QueryValue.recordPrimaryKey
      )
      public let recordType = StructuredQueriesCore.TableColumn<QueryValue, String>(
        "recordType",
        keyPath: \QueryValue.recordType
      )
      public var recordName: StructuredQueriesCore.GeneratedColumn<QueryValue, String> {
        StructuredQueriesCore.GeneratedColumn<QueryValue, String>(
          "recordName",
          keyPath: \QueryValue.recordName
        )
      }
      public let parentRecordPrimaryKey = StructuredQueriesCore.TableColumn<QueryValue, String?>(
        "parentRecordPrimaryKey",
        keyPath: \QueryValue.parentRecordPrimaryKey
      )
      public let parentRecordType = StructuredQueriesCore.TableColumn<QueryValue, String?>(
        "parentRecordType",
        keyPath: \QueryValue.parentRecordType
      )
      public var parentRecordName: StructuredQueriesCore.GeneratedColumn<QueryValue, String?> {
        StructuredQueriesCore.GeneratedColumn<QueryValue, String?>(
          "parentRecordName",
          keyPath: \QueryValue.parentRecordName
        )
      }
      public let lastKnownServerRecord = StructuredQueriesCore.TableColumn<
        QueryValue, CKRecord?.SystemFieldsRepresentation
      >("lastKnownServerRecord", keyPath: \QueryValue.lastKnownServerRecord)
      package let _lastKnownServerRecordAllFields = StructuredQueriesCore.TableColumn<
        QueryValue, CKRecord?.AllFieldsRepresentation
      >("_lastKnownServerRecordAllFields", keyPath: \QueryValue._lastKnownServerRecordAllFields)
      public let share = StructuredQueriesCore.TableColumn<
        QueryValue, CKShare?.SystemFieldsRepresentation
      >("share", keyPath: \QueryValue.share)
      public var isShared: StructuredQueriesCore.GeneratedColumn<QueryValue, Bool> {
        StructuredQueriesCore.GeneratedColumn<QueryValue, Bool>(
          "isShared",
          keyPath: \QueryValue.isShared
        )
      }
      public var isDeleted: StructuredQueriesCore.TableColumn<QueryValue, Bool> {
        StructuredQueriesCore.TableColumn<QueryValue, Bool>(
          "isDeleted",
          keyPath: \QueryValue.isDeleted
        )
      }
      public let userModificationDate = StructuredQueriesCore.TableColumn<QueryValue, Date>(
        "userModificationDate",
        keyPath: \QueryValue.userModificationDate
      )
      public static var allColumns: [any StructuredQueriesCore.TableColumnExpression] {
        [
          QueryValue.columns.recordPrimaryKey, QueryValue.columns.recordType,
          QueryValue.columns.recordName, QueryValue.columns.parentRecordPrimaryKey,
          QueryValue.columns.parentRecordType, QueryValue.columns.parentRecordName,
          QueryValue.columns.lastKnownServerRecord,
          QueryValue.columns._lastKnownServerRecordAllFields, QueryValue.columns.share,
          QueryValue.columns.isShared, QueryValue.columns.isDeleted, QueryValue.columns.userModificationDate,
        ]
      }
      public static var writableColumns: [any StructuredQueriesCore.WritableTableColumnExpression] {
        [
          QueryValue.columns.recordPrimaryKey, QueryValue.columns.recordType,
          QueryValue.columns.parentRecordPrimaryKey, QueryValue.columns.parentRecordType,
          QueryValue.columns.lastKnownServerRecord,
          QueryValue.columns._lastKnownServerRecordAllFields, QueryValue.columns.share,
          QueryValue.columns.isDeleted,
          QueryValue.columns.userModificationDate,
        ]
      }
      public var queryFragment: QueryFragment {
        "\(self.recordPrimaryKey), \(self.recordType), \(self.recordName), \(self.parentRecordPrimaryKey), \(self.parentRecordType), \(self.parentRecordName), \(self.lastKnownServerRecord), \(self._lastKnownServerRecordAllFields), \(self.share), \(self.isShared), \(self.isDeleted), \(self.userModificationDate)"
      }
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  nonisolated extension SyncMetadata: StructuredQueriesCore.Table {
    public nonisolated static var columns: TableColumns {
      TableColumns()
    }
    public nonisolated static var tableName: String {
      "sqlitedata_icloud_metadata"
    }
    public nonisolated init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
      let recordPrimaryKey = try decoder.decode(String.self)
      let recordType = try decoder.decode(String.self)
      let recordName = try decoder.decode(String.self)
      self.parentRecordPrimaryKey = try decoder.decode(String.self)
      self.parentRecordType = try decoder.decode(String.self)
      self.parentRecordName = try decoder.decode(String.self)
      let lastKnownServerRecord = try decoder.decode(CKRecord?.SystemFieldsRepresentation.self)
      let _lastKnownServerRecordAllFields = try decoder.decode(
        CKRecord?.AllFieldsRepresentation.self
      )
      let share = try decoder.decode(CKShare?.SystemFieldsRepresentation.self)
      let isShared = try decoder.decode(Bool.self)
      let isDeleted = try decoder.decode(Bool.self)
      let userModificationDate = try decoder.decode(Date.self)
      guard let recordPrimaryKey else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let recordType else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let recordName else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let lastKnownServerRecord else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let _lastKnownServerRecordAllFields else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let share else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let isShared else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let isDeleted else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let userModificationDate else {
        throw QueryDecodingError.missingRequiredColumn
      }
      self.recordPrimaryKey = recordPrimaryKey
      self.recordType = recordType
      self.recordName = recordName
      self.lastKnownServerRecord = lastKnownServerRecord
      self._lastKnownServerRecordAllFields = _lastKnownServerRecordAllFields
      self.share = share
      self.isShared = isShared
      self.isDeleted = isDeleted
      self.userModificationDate = userModificationDate
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension AncestorMetadata {
    public struct Columns: StructuredQueriesCore.QueryExpression {
      public typealias QueryValue = AncestorMetadata
      public let queryFragment: StructuredQueriesCore.QueryFragment
      public init(
        recordName: some StructuredQueriesCore.QueryExpression<String>,
        parentRecordName: some StructuredQueriesCore.QueryExpression<String?>,
        lastKnownServerRecord: some StructuredQueriesCore.QueryExpression<
          CKRecord?.SystemFieldsRepresentation
        >
      ) {
        self.queryFragment = """
          \(recordName.queryFragment) AS "recordName", \(parentRecordName.queryFragment) AS "parentRecordName", \(lastKnownServerRecord.queryFragment) AS "lastKnownServerRecord"
          """
      }
    }

    public nonisolated struct TableColumns: StructuredQueriesCore.TableDefinition {
      public typealias QueryValue = AncestorMetadata
      public let recordName = StructuredQueriesCore.TableColumn<QueryValue, String>(
        "recordName",
        keyPath: \QueryValue.recordName
      )
      public let parentRecordName = StructuredQueriesCore.TableColumn<QueryValue, String?>(
        "parentRecordName",
        keyPath: \QueryValue.parentRecordName
      )
      public let lastKnownServerRecord = StructuredQueriesCore.TableColumn<
        QueryValue, CKRecord?.SystemFieldsRepresentation
      >("lastKnownServerRecord", keyPath: \QueryValue.lastKnownServerRecord)
      public static var allColumns: [any StructuredQueriesCore.TableColumnExpression] {
        [
          QueryValue.columns.recordName, QueryValue.columns.parentRecordName,
          QueryValue.columns.lastKnownServerRecord,
        ]
      }
      public static var writableColumns: [any StructuredQueriesCore.WritableTableColumnExpression] {
        [
          QueryValue.columns.recordName, QueryValue.columns.parentRecordName,
          QueryValue.columns.lastKnownServerRecord,
        ]
      }
      public var queryFragment: QueryFragment {
        "\(self.recordName), \(self.parentRecordName), \(self.lastKnownServerRecord)"
      }
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  nonisolated extension AncestorMetadata: StructuredQueriesCore.Table, StructuredQueriesCore
      .PartialSelectStatement
  {
    public typealias QueryValue = Self
    public typealias From = Swift.Never
    public nonisolated static var columns: TableColumns {
      TableColumns()
    }
    public nonisolated static var tableName: String {
      "ancestorMetadatas"
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension AncestorMetadata: StructuredQueriesCore.QueryRepresentable {
    public init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
      let recordName = try decoder.decode(String.self)
      let parentRecordName = try decoder.decode(String.self)
      let lastKnownServerRecord = try decoder.decode(CKRecord?.SystemFieldsRepresentation.self)
      guard let recordName else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let lastKnownServerRecord else {
        throw QueryDecodingError.missingRequiredColumn
      }
      self.recordName = recordName
      self.parentRecordName = parentRecordName
      self.lastKnownServerRecord = lastKnownServerRecord
    }
  }
#endif
