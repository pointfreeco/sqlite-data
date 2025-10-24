#if canImport(CloudKit)
  import CloudKit

  /// A table that tracks metadata related to synchronized data.
  ///
  /// Each row of this table represents a synchronized record across all tables synchronized with
  /// CloudKit. This means that the sum of the count of rows across all synchronized tables in your
  /// application is the number of rows this one single table holds. However, this table is held
  /// in a database separate from your app's database.
  ///
  /// See <doc:CloudKit#Accessing-CloudKit-metadata> for more info.
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Table("sqlitedata_icloud_metadata")
  public struct SyncMetadata: Hashable, Identifiable, Sendable {
    /// A selection of columns representing a synchronized record's unique identifier and type.
    @Selection
    public struct ID: Hashable, Sendable {
      /// The unique identifier of the record synchronized.
      public let recordPrimaryKey: String

      /// The type of the record synchronized, _i.e._ its table name.
      public let recordType: String
    }

    /// The unique identifier and type of the record synchronized.
    public let id: ID

    /// The unique identifier of the record synchronized.
    public var recordPrimaryKey: String { id.recordPrimaryKey }

    /// The type of the record synchronized, _i.e._ its table name.
    public var recordType: String { id.recordType }

    /// The record zone name.
    public let zoneName: String

    /// The record owner name.
    public let ownerName: String

    /// The name of the record synchronized.
    ///
    /// This field encodes both the table name and primary key of the record synchronized in
    /// the format "primaryKey:tableName", for example:
    ///
    /// ```swift
    /// "8c4d1e4e-49b2-4f60-b6df-3c23881b87c6:reminders"
    /// ```
    @Column(generated: .virtual)
    public let recordName: String

    /// A selection of columns representing a synchronized parent record's unique identifier and
    /// type.
    @Selection
    public struct ParentID: Hashable, Sendable {
      /// The unique identifier of the parent record synchronized.
      public let parentRecordPrimaryKey: String

      /// The type of the parent record synchronized, _i.e._ its table name.
      public let parentRecordType: String
    }

    /// The identifier and type of this record's parent, if any.
    public let parentRecordID: ParentID?

    /// The unique identifier of this record's parent, if any.
    public var parentRecordPrimaryKey: String? { parentRecordID?.parentRecordPrimaryKey }

    /// The type of this record's parent, _i.e._ its table name, if any.
    public var parentRecordType: String? { parentRecordID?.parentRecordType }

    /// The name of this record's parent, if any.
    ///
    /// This field encodes both the table name and primary key of the parent record in the format
    /// "primaryKey:tableName", for example:
    ///
    /// ```swift
    /// "d35e1f81-46e4-45d1-904b-2b7df1661e3e:remindersLists"
    /// ```
    @Column(generated: .virtual)
    public let parentRecordName: String?

    /// The last known `CKRecord` received from the server.
    ///
    /// This record holds only the fields that are archived when using `encodeSystemFields(with:)`.
    @Column(as: CKRecord?.SystemFieldsRepresentation.self)
    public let lastKnownServerRecord: CKRecord?

    /// The last known `CKRecord` received from the server with all fields archived.
    @Column(as: CKRecord?._AllFieldsRepresentation.self)
    public let _lastKnownServerRecordAllFields: CKRecord?

    /// The `CKShare` associated with this record, if it is shared.
    @Column(as: CKShare?.SystemFieldsRepresentation.self)
    public let share: CKShare?

    /// Determines if the metadata has been "soft" deleted. It will be fully deleted once the
    /// next batch of pending changes is processed.
    public let _isDeleted: Bool

    @Column(generated: .virtual)
    public let hasLastKnownServerRecord: Bool

    /// Determines if the record associated with this metadata is currently shared in CloudKit.
    ///
    /// This can only return `true` for root records. For example, the metadata associated with a
    /// `RemindersList` can have `isShared == true`, but a `Reminder` associated with the list
    /// will have `isShared == false`.
    @Column(generated: .virtual)
    public let isShared: Bool

    /// The time the user last modified the record.
    public let userModificationTime: Int64
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SyncMetadata.TableColumns {
    public var recordPrimaryKey: TableColumn<SyncMetadata, String> {
      id.recordPrimaryKey
    }

    public var recordType: TableColumn<SyncMetadata, String> {
      id.recordType
    }

    public var parentRecordPrimaryKey: TableColumn<SyncMetadata, String?> {
      parentRecordID.parentRecordPrimaryKey
    }

    public var parentRecordType: TableColumn<SyncMetadata, String?> {
      parentRecordID.parentRecordType
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SyncMetadata {
    package init(
      recordPrimaryKey: String,
      recordType: String,
      zoneName: String,
      ownerName: String,
      parentRecordPrimaryKey: String? = nil,
      parentRecordType: String? = nil,
      lastKnownServerRecord: CKRecord? = nil,
      _lastKnownServerRecordAllFields: CKRecord? = nil,
      share: CKShare? = nil,
      userModificationTime: Int64
    ) {
      self.id = ID(recordPrimaryKey: recordPrimaryKey, recordType: recordType)
      self.recordName = "\(recordPrimaryKey):\(recordType)"
      self.zoneName = zoneName
      self.ownerName = ownerName
      if let parentRecordPrimaryKey, let parentRecordType {
        self.parentRecordID = ParentID(
          parentRecordPrimaryKey: parentRecordPrimaryKey,
          parentRecordType: parentRecordType
        )
        self.parentRecordName = "\(parentRecordPrimaryKey):\(parentRecordType)"
      } else {
        self.parentRecordID = nil
        self.parentRecordName = nil
      }
      self.lastKnownServerRecord = lastKnownServerRecord
      self._lastKnownServerRecordAllFields = _lastKnownServerRecordAllFields
      self.share = share
      self.hasLastKnownServerRecord = lastKnownServerRecord != nil
      self.isShared = share != nil
      self.userModificationTime = userModificationTime
      self._isDeleted = false
    }

    package static func find(_ recordID: CKRecord.ID) -> Where<Self> {
      Self.where {
        $0.recordName.eq(recordID.recordName)
          && $0.zoneName.eq(recordID.zoneID.zoneName)
          && $0.ownerName.eq(recordID.zoneID.ownerName)
      }
    }

    package static func findAll(_ recordIDs: some Collection<CKRecord.ID>) -> Where<Self> {
      let condition: QueryFragment = recordIDs.map {
        "(\(bind: $0.recordName), \(bind: $0.zoneID.zoneName), \(bind: $0.zoneID.ownerName))"
      }
      .joined(separator: ", ")
      return Self.where {
        #sql("(\($0.recordName), \($0.zoneName), \($0.ownerName)) IN (\(condition))")
      }
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension PrimaryKeyedTable where PrimaryKey.QueryOutput: IdentifierStringConvertible {
    /// A query for finding the metadata associated with a record.
    ///
    /// - Parameter primaryKey: The primary key of the record whose metadata to look up.
    @available(*, deprecated, message: "Use 'SyncMetadata.find(record.syncMetadataID)', instead")
    public static func metadata(for primaryKey: PrimaryKey.QueryOutput) -> Where<SyncMetadata> {
      SyncMetadata.where {
        #sql(
          """
          \($0.recordPrimaryKey) = \(PrimaryKey(queryOutput: primaryKey)) \
          AND \($0.recordType) = \(bind: tableName)
          """
        )
      }
    }

    /// An identifier representing any associated synchronization metadata.
    public var syncMetadataID: SyncMetadata.ID {
      SyncMetadata.ID(
        recordPrimaryKey: primaryKey.rawIdentifier,
        recordType: Self.tableName
      )
    }

    package static func recordName(for id: PrimaryKey.QueryOutput) -> String {
      "\(id.rawIdentifier):\(tableName)"
    }

    var recordName: String {
      Self.recordName(for: self[keyPath: Self.columns.primaryKey.keyPath])
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension PrimaryKeyedTableDefinition where PrimaryKey.QueryOutput: IdentifierStringConvertible {
    /// A query expression for whether or not this row has associated sync metadata.
    ///
    /// This helper can be useful when joining your tables to the ``SyncMetadata`` table:
    ///
    /// ```swift
    /// RemindersList
    ///   .leftJoin(SyncMetadata.all) { $0.hasMetadata.in($1) }
    /// ```
    @available(
      *,
      deprecated,
      message: """
        Join the 'SyncMetadata' table using 'SyncMetadata.id' and 'Table.syncMetadataID', instead.
        """
    )
    public func hasMetadata(in metadata: SyncMetadata.TableColumns) -> some QueryExpression<Bool> {
      metadata.recordType.eq(QueryValue.tableName)
        && #sql("\(primaryKey)").eq(metadata.recordPrimaryKey)
    }

    /// An identifier representing any associated synchronization metadata.
    ///
    /// This helper can be useful when joining your tables to the ``SyncMetadata`` table:
    ///
    /// ```swift
    /// RemindersList
    ///   .leftJoin(SyncMetadata.all) { $0.syncMetadataID.eq($1.id) }
    /// ```
    public var syncMetadataID: some QueryExpression<SyncMetadata.ID> {
      #sql("\(primaryKey), \(bind: QueryValue.tableName)")
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension PrimaryKeyedTableDefinition {
    var _recordName: some QueryExpression<String> {
      #sql("\(primaryKey) || ':' || \(quote: QueryValue.tableName, delimiter: .text)")
    }
  }
#endif
