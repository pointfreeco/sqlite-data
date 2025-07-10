#if canImport(CloudKit)
  import CloudKit

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SyncMetadata {
    public struct TableColumns: StructuredQueriesCore.TableDefinition {
      public typealias QueryValue = SyncMetadata
      public let recordPrimaryKey = StructuredQueriesCore.TableColumn<QueryValue, String>(
        "recordPrimaryKey",
        keyPath: \QueryValue.recordPrimaryKey
      )
      public let recordType = StructuredQueriesCore.TableColumn<QueryValue, String>(
        "recordType",
        keyPath: \QueryValue.recordType
      )
      public var recordName: some StructuredQueriesCore.QueryExpression<String> {
        StructuredQueriesCore.TableColumn<QueryValue, String>(
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
      public var parentRecordName: some StructuredQueriesCore.QueryExpression<String?> {
        StructuredQueriesCore.TableColumn<QueryValue, String?>(
          "parentRecordName",
          keyPath: \QueryValue.parentRecordName
        )
      }
      public let lastKnownServerRecord = StructuredQueriesCore.TableColumn<
        QueryValue, CKRecord?.SystemFieldsRepresentation
      >("lastKnownServerRecord", keyPath: \QueryValue.lastKnownServerRecord)
      public let share = StructuredQueriesCore.TableColumn<
        QueryValue, CKShare?.SystemFieldsRepresentation
      >("share", keyPath: \QueryValue.share)
      public let userModificationDate = StructuredQueriesCore.TableColumn<QueryValue, Date>(
        "userModificationDate",
        keyPath: \QueryValue.userModificationDate
      )
      public static var allColumns: [any StructuredQueriesCore.TableColumnExpression] {
        [
          QueryValue.columns.recordPrimaryKey, QueryValue.columns.recordType,
          QueryValue.columns.parentRecordPrimaryKey, QueryValue.columns.parentRecordType,
          QueryValue.columns.lastKnownServerRecord, QueryValue.columns.share,
          QueryValue.columns.userModificationDate,
        ]
      }
      public var queryFragment: QueryFragment {
        "\(self.recordPrimaryKey), \(self.recordType), \(self.recordName), \(self.parentRecordPrimaryKey), \(self.parentRecordType), \(self.parentRecordName), \(self.lastKnownServerRecord), \(self.share), \(self.userModificationDate)"
      }
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SyncMetadata: StructuredQueriesCore.Table {
    public static let columns = TableColumns()
    public static let tableName = "sqlitedata_icloud_metadata"
    public init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
      let recordPrimaryKey = try decoder.decode(String.self)
      let recordType = try decoder.decode(String.self)
      let recordName = try decoder.decode(String.self)
      self.parentRecordPrimaryKey = try decoder.decode(String.self)
      self.parentRecordType = try decoder.decode(String.self)
      self.parentRecordName = try decoder.decode(String.self)
      let lastKnownServerRecord = try decoder.decode(CKRecord?.SystemFieldsRepresentation.self)
      let share = try decoder.decode(CKShare?.SystemFieldsRepresentation.self)
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
      guard let share else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let userModificationDate else {
        throw QueryDecodingError.missingRequiredColumn
      }
      self.recordPrimaryKey = recordPrimaryKey
      self.recordType = recordType
      self.recordName = recordName
      self.lastKnownServerRecord = lastKnownServerRecord
      self.share = share
      self.userModificationDate = userModificationDate
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SyncMetadata.AncestorMetadata: StructuredQueriesCore.Table {
    public struct Columns: StructuredQueriesCore.QueryExpression {
      public typealias QueryValue = SyncMetadata.AncestorMetadata
      public let queryFragment: StructuredQueriesCore.QueryFragment
      public init(
        recordName: some StructuredQueriesCore.QueryExpression<String>,
        parentRecordName: some StructuredQueriesCore.QueryExpression<String?>,
        lastKnownServerRecord: some StructuredQueriesCore.QueryExpression<CKRecord?.SystemFieldsRepresentation>
      ) {
        self.queryFragment = """
          \(recordName.queryFragment) AS "recordName", \(parentRecordName.queryFragment) AS "parentRecordName", \(lastKnownServerRecord.queryFragment) AS "lastKnownServerRecord"
          """
      }
    }

    public struct TableColumns: StructuredQueriesCore.TableDefinition {
      public typealias QueryValue = SyncMetadata.AncestorMetadata
      public let recordName = StructuredQueriesCore.TableColumn<
        QueryValue, String
      >("recordName", keyPath: \QueryValue.recordName)
      public let parentRecordName = StructuredQueriesCore.TableColumn<
        QueryValue, String?
      >("parentRecordName", keyPath: \QueryValue.parentRecordName)
      public let lastKnownServerRecord = StructuredQueriesCore.TableColumn<QueryValue, CKRecord?.SystemFieldsRepresentation>(
        "lastKnownServerRecord",
        keyPath: \QueryValue.lastKnownServerRecord
      )
      public static var allColumns: [any StructuredQueriesCore.TableColumnExpression] {
        [QueryValue.columns.recordName, QueryValue.columns.parentRecordName]
      }
    }

    public static let columns = TableColumns()
    public static let tableName = "ancestorMetadatas"
    public init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
      let recordName = try decoder.decode(String.self)
      let parentRecordName = try decoder.decode(String?.self)
      let lastKnownServerRecord = try decoder.decode(CKRecord?.SystemFieldsRepresentation.self)
      guard let recordName else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let parentRecordName else {
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
