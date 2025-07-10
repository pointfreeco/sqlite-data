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
  /// The unique identifier of the record synchronized.
  public var recordPrimaryKey: String

  /// The type of the record synchronized, _i.e._ its table name.
  public var recordType: String

  /// The name of the record synchronized.
  ///
  /// This field encodes both the table name and primary key of the record synchronized in
  /// the format "primaryKey:tableName", for example:
  ///
  /// ```swift
  /// "8c4d1e4e-49b2-4f60-b6df-3c23881b87c6:reminders"
  /// ```
  // @Column(generated: .virtual)
  public let recordName: String

  /// The unique identifier of this record's parent, if any.
  public var parentRecordPrimaryKey: String?

  /// The type of this record's parent, _i.e._ its table name, if any.
  public var parentRecordType: String?

  /// The name of this record's parent, if any.
  ///
  /// This field encodes both the table name and primary key of the parent record in the format
  /// "primaryKey:tableName", for example:
  ///
  /// ```swift
  /// "d35e1f81-46e4-45d1-904b-2b7df1661e3e:remindersLists"
  /// ```
  public let parentRecordName: String?

  /// The last known `CKRecord` received from the server.
  // @Column(as: CKRecord?.SystemFieldsRepresentation.self)
  public var lastKnownServerRecord: CKRecord?

  /// The `CKShare` associated with this record, if it is shared.
  // @Column(as: CKShare?.SystemFieldsRepresentation.self)
  public var share: CKShare?

  /// The date the user last modified the record.
  public var userModificationDate: Date

  package init(
    recordPrimaryKey: String,
    recordType: String,
    recordName: String,
    parentRecordPrimaryKey: String? = nil,
    parentRecordType: String? = nil,
    parentRecordName: String?,
    lastKnownServerRecord: CKRecord? = nil,
    share: CKShare? = nil,
    userModificationDate: Date
  ) {
    self.recordPrimaryKey = recordPrimaryKey
    self.recordType = recordType
    self.recordName = recordName
    self.parentRecordPrimaryKey = parentRecordPrimaryKey
    self.parentRecordType = parentRecordType
    self.parentRecordName = parentRecordName
    self.lastKnownServerRecord = lastKnownServerRecord
    self.share = share
    self.userModificationDate = userModificationDate
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncMetadata.TableColumns {
  package var _lastKnownServerRecordAllFields: StructuredQueriesCore.TableColumn<
    SyncMetadata,
    CKRecord?.AllFieldsRepresentation
  > {
    StructuredQueriesCore.TableColumn(
      "_lastKnownServerRecordAllFields",
      keyPath: \._lastKnownServerRecordAllFields
    )
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncMetadata {
  fileprivate var _lastKnownServerRecordAllFields: CKRecord? {
    fatalError(
      """
      Never invoke this directly. Use 'SyncMetadata.TableColumns._lastKnownServerRecordAllFields' \
      instead.
      """
    )
  }

  package static func find<T: PrimaryKeyedTable>(
    _ primaryKey: T.PrimaryKey.QueryOutput,
    table _: T.Type,
  ) -> Where<Self> {
    Self.where {
      SQLQueryExpression(
        """
        \($0.recordPrimaryKey) = \(T.PrimaryKey(queryOutput: primaryKey)) \
        AND \($0.recordType) = \(bind: T.tableName)
        """
      )
    }
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension PrimaryKeyedTable<UUID> {
  /// Constructs a ``SyncMetadata/RecordName-swift.struct`` for a primary keyed table give an ID.
  ///
  /// - Parameter id: The ID of the record.
  public static func recordName(for id: UUID) -> String {
    "\(id.uuidString.lowercased()):\(tableName)"
  }

  var recordName: String {
    Self.recordName(for: self[keyPath: Self.columns.primaryKey.keyPath])
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension PrimaryKeyedTableDefinition<UUID> {
  public var recordName: some QueryExpression<String> {
    SQLQueryExpression(" \(primaryKey) || ':' || \(quote: QueryValue.tableName, delimiter: .text)")
  }
}
#endif
