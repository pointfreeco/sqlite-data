#if canImport(CloudKit)
import CloudKit

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
// @Table("\(String.sqliteDataCloudKitSchemaName)_metadata")
public struct SyncMetadata: Hashable, Sendable {
  public var recordType: String
  // @Column(primaryKey: true)
  public var recordName: RecordName
  public var parentRecordName: RecordName?
  // @Column(as: CKRecord?.DataRepresentation.self)
  public var lastKnownServerRecord: CKRecord?
  // @Column(as: CKShare?.ShareDataRepresentation.self)
  public var share: CKShare?
  public var userModificationDate: Date?
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncMetadata {
  public struct RecordName: RawRepresentable, Sendable, Hashable, QueryBindable {
    public var recordType: String
    public var id: UUID

    public init<T: PrimaryKeyedTable<UUID>>(_ table: T.Type, id: UUID) {
      recordType = T.tableName
      self.id = id
    }

    public init?(rawValue: String) {
      guard let colonIndex = rawValue.firstIndex(of: ":")
      else {
        return nil
      }
      guard let id = UUID(uuidString: String(rawValue[rawValue.startIndex..<colonIndex]))
      else {
        return nil
      }

      recordType = String(rawValue[rawValue.index(after: colonIndex)...])
      self.id = id
    }

    public init<T: PrimaryKeyedTable<UUID>>(record: T) {
      recordType = T.tableName
      id = record[keyPath: T.columns.primaryKey.keyPath]
    }

    public init?(recordID: CKRecord.ID) {
      self.init(rawValue: recordID.recordName)
    }

    public var rawValue: String {
      "\(id.uuidString.lowercased()):\(recordType)"
    }
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension PrimaryKeyedTable<UUID> {
  public static func recordName(for id: UUID) -> SyncMetadata.RecordName {
    SyncMetadata.RecordName(Self.self, id: id)
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension PrimaryKeyedTableDefinition<UUID> {
  public var recordName: some QueryExpression<SyncMetadata.RecordName> {
    SQLQueryExpression(" \(primaryKey) || ':' || \(quote: QueryValue.tableName, delimiter: .text)")
  }
}
#endif
