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
      public var _isDeleted: StructuredQueriesCore.TableColumn<QueryValue, Bool> {
        StructuredQueriesCore.TableColumn<QueryValue, Bool>(
          "_isDeleted",
          keyPath: \QueryValue._isDeleted
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
          QueryValue.columns.isShared, QueryValue.columns._isDeleted,
          QueryValue.columns.userModificationDate,
        ]
      }
      public static var writableColumns: [any StructuredQueriesCore.WritableTableColumnExpression] {
        [
          QueryValue.columns.recordPrimaryKey, QueryValue.columns.recordType,
          QueryValue.columns.parentRecordPrimaryKey, QueryValue.columns.parentRecordType,
          QueryValue.columns.lastKnownServerRecord,
          QueryValue.columns._lastKnownServerRecordAllFields, QueryValue.columns.share,
          QueryValue.columns._isDeleted,
          QueryValue.columns.userModificationDate,
        ]
      }
      public var queryFragment: QueryFragment {
        "\(self.recordPrimaryKey), \(self.recordType), \(self.recordName), \(self.parentRecordPrimaryKey), \(self.parentRecordType), \(self.parentRecordName), \(self.lastKnownServerRecord), \(self._lastKnownServerRecordAllFields), \(self.share), \(self.isShared), \(self._isDeleted), \(self.userModificationDate)"
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
      let _isDeleted = try decoder.decode(Bool.self)
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
      guard let _isDeleted else {
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
      self._isDeleted = _isDeleted
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

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension RecordWithRoot {
    public struct Columns: StructuredQueriesCore.QueryExpression {
      public typealias QueryValue = RecordWithRoot
      public let queryFragment: StructuredQueriesCore.QueryFragment
      public init(
        parentRecordName: some StructuredQueriesCore.QueryExpression<String?>,
        recordName: some StructuredQueriesCore.QueryExpression<String>,
        lastKnownServerRecord: some StructuredQueriesCore.QueryExpression<
          CKRecord?.SystemFieldsRepresentation
        >,
        rootRecordName: some StructuredQueriesCore.QueryExpression<String>,
        rootLastKnownServerRecord: some StructuredQueriesCore.QueryExpression<
          CKRecord?.SystemFieldsRepresentation
        >
      ) {
        self.queryFragment = """
          \(parentRecordName.queryFragment) AS "parentRecordName", \(recordName.queryFragment) AS "recordName", \(lastKnownServerRecord.queryFragment) AS "lastKnownServerRecord", \(rootRecordName.queryFragment) AS "rootRecordName", \(rootLastKnownServerRecord.queryFragment) AS "rootLastKnownServerRecord"
          """
      }
    }
    public nonisolated struct TableColumns: StructuredQueriesCore.TableDefinition {
      public typealias QueryValue = RecordWithRoot
      public let parentRecordName = StructuredQueriesCore.TableColumn<QueryValue, String?>(
        "parentRecordName",
        keyPath: \QueryValue.parentRecordName
      )
      public let recordName = StructuredQueriesCore.TableColumn<QueryValue, String>(
        "recordName",
        keyPath: \QueryValue.recordName
      )
      public let lastKnownServerRecord = StructuredQueriesCore.TableColumn<
        QueryValue, CKRecord?.SystemFieldsRepresentation
      >("lastKnownServerRecord", keyPath: \QueryValue.lastKnownServerRecord)
      public let rootRecordName = StructuredQueriesCore.TableColumn<QueryValue, String>(
        "rootRecordName",
        keyPath: \QueryValue.rootRecordName
      )
      public let rootLastKnownServerRecord = StructuredQueriesCore.TableColumn<
        QueryValue, CKRecord?.SystemFieldsRepresentation
      >("rootLastKnownServerRecord", keyPath: \QueryValue.rootLastKnownServerRecord)
      public static var allColumns: [any StructuredQueriesCore.TableColumnExpression] {
        [
          QueryValue.columns.parentRecordName, QueryValue.columns.recordName,
          QueryValue.columns.lastKnownServerRecord, QueryValue.columns.rootRecordName,
          QueryValue.columns.rootLastKnownServerRecord,
        ]
      }
      public static var writableColumns: [any StructuredQueriesCore.WritableTableColumnExpression] {
        [
          QueryValue.columns.parentRecordName, QueryValue.columns.recordName,
          QueryValue.columns.lastKnownServerRecord, QueryValue.columns.rootRecordName,
          QueryValue.columns.rootLastKnownServerRecord,
        ]
      }
      public var queryFragment: QueryFragment {
        "\(self.parentRecordName), \(self.recordName), \(self.lastKnownServerRecord), \(self.rootRecordName), \(self.rootLastKnownServerRecord)"
      }
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  nonisolated extension RecordWithRoot: StructuredQueriesCore.Table {
    public nonisolated static var columns: TableColumns {
      TableColumns()
    }
    public nonisolated static var tableName: String {
      "recordWithRoots"
    }
    public nonisolated init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
      self.parentRecordName = try decoder.decode(String.self)
      let recordName = try decoder.decode(String.self)
      let lastKnownServerRecord = try decoder.decode(CKRecord?.SystemFieldsRepresentation.self)
      let rootRecordName = try decoder.decode(String.self)
      let rootLastKnownServerRecord = try decoder.decode(CKRecord?.SystemFieldsRepresentation.self)
      guard let recordName else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let lastKnownServerRecord else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let rootRecordName else {
        throw QueryDecodingError.missingRequiredColumn
      }
      guard let rootLastKnownServerRecord else {
        throw QueryDecodingError.missingRequiredColumn
      }
      self.recordName = recordName
      self.lastKnownServerRecord = lastKnownServerRecord
      self.rootRecordName = rootRecordName
      self.rootLastKnownServerRecord = rootLastKnownServerRecord
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension RootShare {
    public struct Columns: StructuredQueriesCore.QueryExpression {
      public typealias QueryValue = RootShare
      public let queryFragment: StructuredQueriesCore.QueryFragment
      public init(
        parentRecordName: some StructuredQueriesCore.QueryExpression<String?>,
        share: some StructuredQueriesCore.QueryExpression<CKShare?.SystemFieldsRepresentation>
      ) {
        self.queryFragment = """
          \(parentRecordName.queryFragment) AS "parentRecordName", \(share.queryFragment) AS "share"
          """
      }
    }

    public nonisolated struct TableColumns: StructuredQueriesCore.TableDefinition {
      public typealias QueryValue = RootShare
      public let parentRecordName = StructuredQueriesCore.TableColumn<QueryValue, String?>(
        "parentRecordName",
        keyPath: \QueryValue.parentRecordName
      )
      public let share = StructuredQueriesCore.TableColumn<
        QueryValue, CKShare?.SystemFieldsRepresentation
      >("share", keyPath: \QueryValue.share)
      public static var allColumns: [any StructuredQueriesCore.TableColumnExpression] {
        [QueryValue.columns.parentRecordName, QueryValue.columns.share]
      }
      public static var writableColumns: [any StructuredQueriesCore.WritableTableColumnExpression] {
        [QueryValue.columns.parentRecordName, QueryValue.columns.share]
      }
      public var queryFragment: QueryFragment {
        "\(self.parentRecordName), \(self.share)"
      }
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  nonisolated extension RootShare: StructuredQueriesCore.Table {
    public nonisolated static var columns: TableColumns {
      TableColumns()
    }
    public nonisolated static var tableName: String {
      "rootShares"
    }
    public nonisolated init(decoder: inout some StructuredQueriesCore.QueryDecoder) throws {
      self.parentRecordName = try decoder.decode(String.self)
      let share = try decoder.decode(CKShare?.SystemFieldsRepresentation.self)
      guard let share else {
        throw QueryDecodingError.missingRequiredColumn
      }
      self.share = share
    }
  }

#endif
