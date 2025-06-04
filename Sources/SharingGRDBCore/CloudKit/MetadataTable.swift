import CloudKit

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
// @Table("\(String.sqliteDataCloudKitSchemaName)_metadata")
package struct Metadata: Hashable {
  package var recordType: String
  package var recordName: String
  package var zoneName: String
  package var ownerName: String
  package var parentRecordName: String?
  // @Column(as: CKRecord?.DataRepresentation.self)
  package var lastKnownServerRecord: CKRecord?
  // @Column(as: CKShare?.ShareDataRepresentation.self)
  package var share: CKShare?
  package var userModificationDate: Date?
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *) extension Metadata: StructuredQueriesCore.Table {
  public struct TableColumns: StructuredQueriesCore.TableDefinition {
    public typealias QueryValue = Metadata
    public let recordType = StructuredQueriesCore.TableColumn<QueryValue, String>("recordType", keyPath: \QueryValue.recordType)
    public let recordName = StructuredQueriesCore.TableColumn<QueryValue, String>("recordName", keyPath: \QueryValue.recordName)
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
  public static let tableName = "sqlitedata_icloud_metadata"
  public init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
    let recordType = try decoder.decode(String.self)
    let recordName = try decoder.decode(String.self)
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

