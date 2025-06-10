import CloudKit

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
// @Table("\(String.sqliteDataCloudKitSchemaName)_metadata")
public struct Metadata: Hashable, Sendable {
  public var recordType: String
  // @Column(primaryKey: true)
  public var recordName: UUID
  public var zoneName: String
  public var ownerName: String
  public var parentRecordName: String?
  // @Column(as: CKRecord?.DataRepresentation.self)
  public var lastKnownServerRecord: CKRecord?
  // @Column(as: CKShare?.ShareDataRepresentation.self)
  public var share: CKShare?
  public var userModificationDate: Date?
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *) extension Metadata: StructuredQueriesCore.Table, StructuredQueriesCore.PrimaryKeyedTable {
  public struct TableColumns: StructuredQueriesCore.TableDefinition, StructuredQueriesCore.PrimaryKeyedTableDefinition {
    public typealias QueryValue = Metadata
    public let recordType = StructuredQueriesCore.TableColumn<QueryValue, String>("recordType", keyPath: \QueryValue.recordType)
    public let recordName = StructuredQueriesCore.TableColumn<QueryValue, UUID>("recordName", keyPath: \QueryValue.recordName)
    public let zoneName = StructuredQueriesCore.TableColumn<QueryValue, String>("zoneName", keyPath: \QueryValue.zoneName)
    public let ownerName = StructuredQueriesCore.TableColumn<QueryValue, String>("ownerName", keyPath: \QueryValue.ownerName)
    public let parentRecordName = StructuredQueriesCore.TableColumn<QueryValue, String?>("parentRecordName", keyPath: \QueryValue.parentRecordName)
    public let lastKnownServerRecord = StructuredQueriesCore.TableColumn<QueryValue, CKRecord?.DataRepresentation>("lastKnownServerRecord", keyPath: \QueryValue.lastKnownServerRecord)
    public let share = StructuredQueriesCore.TableColumn<QueryValue, CKShare?.ShareDataRepresentation>("share", keyPath: \QueryValue.share)
    public let userModificationDate = StructuredQueriesCore.TableColumn<QueryValue, Date?>("userModificationDate", keyPath: \QueryValue.userModificationDate)
    public var primaryKey: StructuredQueriesCore.TableColumn<QueryValue, UUID> {
      self.recordName
    }
    public static var allColumns: [any StructuredQueriesCore.TableColumnExpression] {
      [QueryValue.columns.recordType, QueryValue.columns.recordName, QueryValue.columns.zoneName, QueryValue.columns.ownerName, QueryValue.columns.parentRecordName, QueryValue.columns.lastKnownServerRecord, QueryValue.columns.share, QueryValue.columns.userModificationDate]
    }
  }
  public struct Draft: StructuredQueriesCore.TableDraft {
    public typealias PrimaryTable = Metadata
    public var recordType: String
    public var recordName: UUID?
    public var zoneName: String
    public var ownerName: String
    public var parentRecordName: String?
    public var lastKnownServerRecord: CKRecord?
    public var share: CKShare?
    public var userModificationDate: Date?
    public struct TableColumns: StructuredQueriesCore.TableDefinition {
      public typealias QueryValue = Metadata.Draft
      public let recordType = StructuredQueriesCore.TableColumn<QueryValue, String>("recordType", keyPath: \QueryValue.recordType)
      public let recordName = StructuredQueriesCore.TableColumn<QueryValue, UUID?>("recordName", keyPath: \QueryValue.recordName)
      public let zoneName = StructuredQueriesCore.TableColumn<QueryValue, String>("zoneName", keyPath: \QueryValue.zoneName)
      public let ownerName = StructuredQueriesCore.TableColumn<QueryValue, String>("ownerName", keyPath: \QueryValue.ownerName)
      public let parentRecordName = StructuredQueriesCore.TableColumn<QueryValue, String?>("parentRecordName", keyPath: \QueryValue.parentRecordName)
      public let lastKnownServerRecord = StructuredQueriesCore.TableColumn<QueryValue, CKRecord?.DataRepresentation>("lastKnownServerRecord", keyPath: \QueryValue.lastKnownServerRecord)
      public let share = StructuredQueriesCore.TableColumn<QueryValue, CKShare?.ShareDataRepresentation>("share", keyPath: \QueryValue.share)
      public let userModificationDate = StructuredQueriesCore.TableColumn<QueryValue, Date?>("userModificationDate", keyPath: \QueryValue.userModificationDate)
      public static var allColumns: [any StructuredQueriesCore.TableColumnExpression] {
        [QueryValue.columns.recordType, QueryValue.columns.recordName, QueryValue.columns.zoneName, QueryValue.columns.ownerName, QueryValue.columns.parentRecordName, QueryValue.columns.lastKnownServerRecord, QueryValue.columns.share, QueryValue.columns.userModificationDate]
      }
    }
    public static let columns = TableColumns()
    public static let tableName = Metadata.tableName
    public init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
      let recordType = try decoder.decode(String.self)
      self.recordName = try decoder.decode(UUID.self)
      let zoneName = try decoder.decode(String.self)
      let ownerName = try decoder.decode(String.self)
      self.parentRecordName = try decoder.decode(String.self)
      let lastKnownServerRecord = try decoder.decode(CKRecord?.DataRepresentation.self)
      let share = try decoder.decode(CKShare?.ShareDataRepresentation.self)
      self.userModificationDate = try decoder.decode(Date.self)
      guard let recordType else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let zoneName else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let ownerName else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let lastKnownServerRecord else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let share else {
        throw QueryDecodingError.missingRequiredColumn
      }
      self.recordType = recordType
      self.zoneName = zoneName
      self.ownerName = ownerName
      self.lastKnownServerRecord = lastKnownServerRecord
      self.share = share
    }
    public init(_ other: Metadata) {
      self.recordType = other.recordType
      self.recordName = other.recordName
      self.zoneName = other.zoneName
      self.ownerName = other.ownerName
      self.parentRecordName = other.parentRecordName
      self.lastKnownServerRecord = other.lastKnownServerRecord
      self.share = other.share
      self.userModificationDate = other.userModificationDate
    }
    public init(
      recordType: String,
      recordName: UUID? = nil,
      zoneName: String,
      ownerName: String,
      parentRecordName: String? = nil,
      lastKnownServerRecord: CKRecord? = nil,
      share: CKShare? = nil,
      userModificationDate: Date? = nil
    ) {
      self.recordType = recordType
      self.recordName = recordName
      self.zoneName = zoneName
      self.ownerName = ownerName
      self.parentRecordName = parentRecordName
      self.lastKnownServerRecord = lastKnownServerRecord
      self.share = share
      self.userModificationDate = userModificationDate
    }
  }
  public static let columns = TableColumns()
  public static let tableName = "sqlitedata_icloud_metadata"
  public init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
    let recordType = try decoder.decode(String.self)
    let recordName = try decoder.decode(UUID.self)
    let zoneName = try decoder.decode(String.self)
    let ownerName = try decoder.decode(String.self)
    self.parentRecordName = try decoder.decode(String.self)
    let lastKnownServerRecord = try decoder.decode(CKRecord?.DataRepresentation.self)
    let share = try decoder.decode(CKShare?.ShareDataRepresentation.self)
    self.userModificationDate = try decoder.decode(Date.self)
    guard let recordType else {
      throw QueryDecodingError.missingRequiredColumn
    }
    guard let recordName else {
      throw QueryDecodingError.missingRequiredColumn
    }
    guard let zoneName else {
      throw QueryDecodingError.missingRequiredColumn
    }
    guard let ownerName else {
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
    self.zoneName = zoneName
    self.ownerName = ownerName
    self.lastKnownServerRecord = lastKnownServerRecord
    self.share = share
  }
}
