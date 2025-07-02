#if canImport(CloudKit)
import CloudKit

/// A table that tracks metadata related to synchronized data.
///
/// Each row of this table represents a synchronized record across all tables synchronized with
/// CloudKit. This means that the sum of the count of rows across all synchronized tables in your
/// application is the number of rows this one single table holds. However, this table is held
/// in a database separate from your app's database.
///
///
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
// @Table("\(String.sqliteDataCloudKitSchemaName)_metadata")
public struct SyncMetadata: Hashable, Sendable {
  /// The type of the record synchronized, i.e. the table name.
  public var recordType: String

  /// The name of the record synchronized.
  ///
  /// This field encodes both the table name and primary key of the record synchronized in
  /// the format "tableName:primaryKey", for example:
  ///
  /// ```swift
  /// "8c4d1e4e-49b2-4f60-b6df-3c23881b87c6:reminders"
  /// ```
  // @Column(primaryKey: true)
  public var recordName: RecordName

  /// The name of the record that this record belongs to.
  ///
  /// This field encodes both the table name and primary key of the parent record in the format
  /// "tableName:primaryKey", for example:
  ///
  /// ```swift
  /// "d35e1f81-46e4-45d1-904b-2b7df1661e3e:remindersLists"
  /// ```
  public var parentRecordName: RecordName?

  /// The last known `CKRecord` received from the server.
  // @Column(as: CKRecord?.DataRepresentation.self)
  public var lastKnownServerRecord: CKRecord?

  /// The `CKShare` associated with this record, if it is shared.
  // @Column(as: CKShare?.ShareDataRepresentation.self)
  public var share: CKShare?

  /// The date the user last modified the record.
  public var userModificationDate: Date?

  package init(
    recordType: String,
    recordName: RecordName,
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
      guard
        let colonIndex = rawValue.firstIndex(of: ":"),
        let id = UUID(uuidString: String(rawValue[rawValue.startIndex..<colonIndex]))
      else {
        reportIssue(
          """
          'recordName' in invalid format: \(rawValue.debugDescription)
          'recordName' should be formatted as "uuid:tableName". 
          """
        )
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
extension SyncMetadata.TableColumns {
  public var parentRecordPrimaryKey: some QueryExpression<UUID?> {
    SQLQueryExpression("substr(\(parentRecordName), 1, 36)")
  }

  public var recordPrimaryKey: some QueryExpression<UUID> {
    SQLQueryExpression("substr(\(recordName), 1, 36)")
  }

  public var parentRecordType: some QueryExpression<String?> {
    SQLQueryExpression("substr(\(parentRecordName), 38)")
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension PrimaryKeyedTable<UUID> {
  /// Constructs a ``SyncMetadata/RecordName-swift.struct`` for a primary keyed table give an ID.
  ///
  /// - Parameter id: The ID of the record.
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
