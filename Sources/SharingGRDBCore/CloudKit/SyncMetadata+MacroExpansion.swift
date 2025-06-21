#if canImport(CloudKit)
import CloudKit

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncMetadata {
  public struct TableColumns: StructuredQueriesCore.TableDefinition, StructuredQueriesCore.PrimaryKeyedTableDefinition {
    public typealias QueryValue = SyncMetadata
    public let recordType = StructuredQueriesCore.TableColumn<QueryValue, String>("recordType", keyPath: \QueryValue.recordType)
    public let recordName = StructuredQueriesCore.TableColumn<QueryValue, RecordName>("recordName", keyPath: \QueryValue.recordName)
    public let parentRecordName = StructuredQueriesCore.TableColumn<QueryValue, RecordName?>("parentRecordName", keyPath: \QueryValue.parentRecordName)
    public let lastKnownServerRecord = StructuredQueriesCore.TableColumn<QueryValue, CKRecord?.DataRepresentation>("lastKnownServerRecord", keyPath: \QueryValue.lastKnownServerRecord)
    public let share = StructuredQueriesCore.TableColumn<QueryValue, CKShare?.ShareDataRepresentation>("share", keyPath: \QueryValue.share)
    public let userModificationDate = StructuredQueriesCore.TableColumn<QueryValue, Date?>("userModificationDate", keyPath: \QueryValue.userModificationDate)
    public var primaryKey: StructuredQueriesCore.TableColumn<QueryValue, RecordName> {
      self.recordName
    }
    public static var allColumns: [any StructuredQueriesCore.TableColumnExpression] {
      [QueryValue.columns.recordType, QueryValue.columns.recordName, QueryValue.columns.parentRecordName, QueryValue.columns.lastKnownServerRecord, QueryValue.columns.share, QueryValue.columns.userModificationDate]
    }
  }

  public struct Draft: StructuredQueriesCore.TableDraft {
    public typealias PrimaryTable = SyncMetadata
    public var recordType: String
    public var recordName: RecordName?
    public var parentRecordName: RecordName?
    public var lastKnownServerRecord: CKRecord?
    public var share: CKShare?
    public var userModificationDate: Date?
    public struct TableColumns: StructuredQueriesCore.TableDefinition {
      public typealias QueryValue = Draft
      public let recordType = StructuredQueriesCore.TableColumn<QueryValue, String>("recordType", keyPath: \QueryValue.recordType)
      public let recordName = StructuredQueriesCore.TableColumn<QueryValue, RecordName?>("recordName", keyPath: \QueryValue.recordName)
      public let parentRecordName = StructuredQueriesCore.TableColumn<QueryValue, RecordName?>("parentRecordName", keyPath: \QueryValue.parentRecordName)
      public let lastKnownServerRecord = StructuredQueriesCore.TableColumn<QueryValue, CKRecord?.DataRepresentation>("lastKnownServerRecord", keyPath: \QueryValue.lastKnownServerRecord)
      public let share = StructuredQueriesCore.TableColumn<QueryValue, CKShare?.ShareDataRepresentation>("share", keyPath: \QueryValue.share)
      public let userModificationDate = StructuredQueriesCore.TableColumn<QueryValue, Date?>("userModificationDate", keyPath: \QueryValue.userModificationDate)
      public static var allColumns: [any StructuredQueriesCore.TableColumnExpression] {
        [QueryValue.columns.recordType, QueryValue.columns.recordName, QueryValue.columns.parentRecordName, QueryValue.columns.lastKnownServerRecord, QueryValue.columns.share, QueryValue.columns.userModificationDate]
      }
    }
    public static let columns = TableColumns()

    public static let tableName = SyncMetadata.tableName

    public init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
      let recordType = try decoder.decode(String.self)
      self.recordName = try decoder.decode(RecordName.self)
      self.parentRecordName = try decoder.decode(RecordName.self)
      let lastKnownServerRecord = try decoder.decode(CKRecord?.DataRepresentation.self)
      let share = try decoder.decode(CKShare?.ShareDataRepresentation.self)
      self.userModificationDate = try decoder.decode(Date.self)
      guard let recordType else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let lastKnownServerRecord else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let share else {
        throw QueryDecodingError.missingRequiredColumn
      }
      self.recordType = recordType
      self.lastKnownServerRecord = lastKnownServerRecord
      self.share = share
    }

    public init(_ other: SyncMetadata) {
      self.recordType = other.recordType
      self.recordName = other.recordName
      self.parentRecordName = other.parentRecordName
      self.lastKnownServerRecord = other.lastKnownServerRecord
      self.share = other.share
      self.userModificationDate = other.userModificationDate
    }
    public init(
      recordType: String,
      recordName: RecordName? = nil,
      parentRecordName: RecordName? = nil,
      lastKnownServerRecord: CKRecord? = nil,
      share: CKShare? = nil,
      userModificationDate: Date? = nil
    ) {
      self.recordType = recordType
      self.recordName = recordName
      self.parentRecordName = parentRecordName
      self.lastKnownServerRecord = lastKnownServerRecord
      self.share = share
      self.userModificationDate = userModificationDate
    }
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *) extension SyncMetadata: StructuredQueriesCore.Table, StructuredQueriesCore.PrimaryKeyedTable {
  public static let columns = TableColumns()
  public static let tableName = "sqlitedata_icloud_metadata"
  public init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
    let recordType = try decoder.decode(String.self)
    let recordName = try decoder.decode(RecordName.self)
    self.parentRecordName = try decoder.decode(RecordName.self)
    let lastKnownServerRecord = try decoder.decode(CKRecord?.DataRepresentation.self)
    let share = try decoder.decode(CKShare?.ShareDataRepresentation.self)
    self.userModificationDate = try decoder.decode(Date.self)
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
    self.recordType = recordType
    self.recordName = recordName
    self.lastKnownServerRecord = lastKnownServerRecord
    self.share = share
  }
}
#endif
