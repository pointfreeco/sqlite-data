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
    @Column(generated: .virtual)
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
    @Column(generated: .virtual)
    public let parentRecordName: String?

    /// The last known `CKRecord` received from the server.
    ///
    /// This record holds only the fields that are archived when using `encodeSystemFields(with:)`.
    @Column(as: CKRecord?.SystemFieldsRepresentation.self)
    public var lastKnownServerRecord: CKRecord?

    /// The last known `CKRecord` received from the server with all fields archived.
    @Column(as: CKRecord?._AllFieldsRepresentation.self)
    public var _lastKnownServerRecordAllFields: CKRecord?

    /// The `CKShare` associated with this record, if it is shared.
    @Column(as: CKShare?.SystemFieldsRepresentation.self)
    public var share: CKShare?

    /// Determines if the metadata has been "soft" deleted. It will be fully deleted once the
    /// next batch of pending changes is processed.
    public var _isDeleted = false

    @Column(generated: .virtual)
    public let hasLastKnownServerRecord: Bool

    /// Determines if the record associated with this metadata is currently shared in CloudKit.
    ///
    /// This can only return `true` for root records. For example, the metadata associated with a
    /// `RemindersList` can have `isShared == true`, but a `Reminder` associated with the list
    /// will have `isShared == false`.
    @Column(generated: .virtual)
    public let isShared: Bool

    /// The date the user last modified the record.
    public var userModificationDate: Date
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Table @Selection
  struct AncestorMetadata {
    let recordName: String
    let parentRecordName: String?
    @Column(as: CKRecord?.SystemFieldsRepresentation.self)
    let lastKnownServerRecord: CKRecord?
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Table @Selection
  struct RecordWithRoot {
    let parentRecordName: String?
    let recordName: String
    @Column(as: CKRecord?.SystemFieldsRepresentation.self)
    let lastKnownServerRecord: CKRecord?
    let rootRecordName: String
    @Column(as: CKRecord?.SystemFieldsRepresentation.self)
    let rootLastKnownServerRecord: CKRecord?
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Table @Selection
  struct RootShare {
    let parentRecordName: String?
    @Column(as: CKShare?.SystemFieldsRepresentation.self)
    let share: CKShare?
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SyncMetadata {
    package init(
      recordPrimaryKey: String,
      recordType: String,
      parentRecordPrimaryKey: String? = nil,
      parentRecordType: String? = nil,
      lastKnownServerRecord: CKRecord? = nil,
      _lastKnownServerRecordAllFields: CKRecord? = nil,
      share: CKShare? = nil,
      userModificationDate: Date
    ) {
      self.recordPrimaryKey = recordPrimaryKey
      self.recordType = recordType
      self.recordName = "\(recordPrimaryKey):\(recordType)"
      self.parentRecordPrimaryKey = parentRecordPrimaryKey
      self.parentRecordType = parentRecordType
      if let parentRecordPrimaryKey, let parentRecordType {
        self.parentRecordName = "\(parentRecordPrimaryKey):\(parentRecordType)"
      } else {
        self.parentRecordName = nil
      }
      self.lastKnownServerRecord = lastKnownServerRecord
      self._lastKnownServerRecordAllFields = _lastKnownServerRecordAllFields
      self.share = share
      self.hasLastKnownServerRecord = lastKnownServerRecord != nil
      self.isShared = share != nil
      self.userModificationDate = userModificationDate
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension PrimaryKeyedTable where PrimaryKey: IdentifierStringConvertible {
    /// A query for finding the metadata associated with a record.
    ///
    /// - Parameter primaryKey: The primary key of the record whose metadata to look up.
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
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension PrimaryKeyedTable where PrimaryKey.QueryOutput: IdentifierStringConvertible {
    /// Constructs a ``SyncMetadata/RecordName-swift.struct`` for a primary keyed table give an ID.
    ///
    /// - Parameter id: The ID of the record.
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
    public func hasMetadata(in metadata: SyncMetadata.TableColumns) -> some QueryExpression<Bool> {
      metadata.recordType.eq(QueryValue.tableName)
        && #sql("\(primaryKey)").eq(metadata.recordPrimaryKey)
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension PrimaryKeyedTableDefinition {
    var _recordName: some QueryExpression<String> {
      #sql("\(primaryKey) || ':' || \(quote: QueryValue.tableName, delimiter: .text)")
    }
  }
#endif
