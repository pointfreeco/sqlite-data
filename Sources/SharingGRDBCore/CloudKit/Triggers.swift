#if canImport(CloudKit)
import CloudKit
import Foundation

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension PrimaryKeyedTable {
  static func metadataTriggers(parentForeignKey: ForeignKey?) -> [TemporaryTrigger<Self>] {
    [
      afterInsert(parentForeignKey: parentForeignKey),
      afterUpdate(parentForeignKey: parentForeignKey),
      afterDeleteFromUser,
      afterDeleteFromSyncEngine,
    ]
  }

  fileprivate static func afterInsert(parentForeignKey: ForeignKey?) -> TemporaryTrigger<Self> {
    createTemporaryTrigger(
      "\(String.sqliteDataCloudKitSchemaName)_after_insert_on_\(tableName)",
      ifNotExists: true,
      after: .insert { new in SyncMetadata.upsert(new: new, parentForeignKey: parentForeignKey) }
    )
  }

  fileprivate static func afterUpdate(parentForeignKey: ForeignKey?) -> TemporaryTrigger<Self> {
    createTemporaryTrigger(
      "\(String.sqliteDataCloudKitSchemaName)_after_update_on_\(tableName)",
      ifNotExists: true,
      after: .update { _, new in SyncMetadata.upsert(new: new, parentForeignKey: parentForeignKey) }
    )
  }

  fileprivate static var afterDeleteFromUser: TemporaryTrigger<Self> {
    createTemporaryTrigger(
      "\(String.sqliteDataCloudKitSchemaName)_after_delete_on_\(tableName)_from_user",
      ifNotExists: true,
      after: .delete { old in
        SyncMetadata
          .where {
            $0.recordPrimaryKey.eq(SQLQueryExpression("\(old.primaryKey)"))
            && $0.recordType.eq(tableName)
          }
          .update { $0.isDeleted = true }
      } when: { _ in
        !SyncEngine.isSynchronizingChanges()
      }
    )
  }

  fileprivate static var afterDeleteFromSyncEngine: TemporaryTrigger<Self> {
    createTemporaryTrigger(
      "\(String.sqliteDataCloudKitSchemaName)_after_delete_on_\(tableName)_from_sync_engine",
      ifNotExists: true,
      after: .delete { old in
        SyncMetadata
          .where {
            $0.recordPrimaryKey.eq(SQLQueryExpression("\(old.primaryKey)"))
            && $0.recordType.eq(tableName)
          }
          .delete()
      } when: { _ in
        SyncEngine.isSynchronizingChanges()
      }
    )
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncMetadata {
  fileprivate static func upsert<T: PrimaryKeyedTable>(
    new: TemporaryTrigger<T>.Operation.New,
    parentForeignKey: ForeignKey?,
  ) -> some StructuredQueriesCore.Statement {
    let (parentRecordPrimaryKey, parentRecordType): (QueryFragment, QueryFragment) =
      parentForeignKey
        .map { (#""new".\#(quote: $0.from)"#, "\(bind: $0.table)") }
        ?? ("NULL", "NULL")
    return insert {
      ($0.recordPrimaryKey, $0.recordType, $0.parentRecordPrimaryKey, $0.parentRecordType)
    } select: {
      Values(
        SQLQueryExpression("\(new.primaryKey)"),
        T.tableName,
        SQLQueryExpression(parentRecordPrimaryKey),
        SQLQueryExpression(parentRecordType)
      )
    } onConflict: {
      ($0.recordPrimaryKey, $0.recordType)
    } doUpdate: {
      $0.parentRecordPrimaryKey = $1.parentRecordPrimaryKey
      $0.parentRecordType = $1.parentRecordType
      $0.userModificationDate = $1.userModificationDate
    }
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncMetadata {
  static var callbackTriggers: [TemporaryTrigger<Self>] {
    [
      afterInsertTrigger,
      afterUpdateTrigger,
      afterDeleteTrigger,
    ]
  }

  private enum ParentSyncMetadata: AliasName {}

  fileprivate static let afterInsertTrigger = createTemporaryTrigger(
    "after_insert_on_sqlitedata_icloud_metadata",
    ifNotExists: true,
    after: .insert { new in
      Values(.didUpdate(new))
    } when: { _ in
      !SyncEngine.isSynchronizingChanges()
    }
  )

  fileprivate static let afterUpdateTrigger = createTemporaryTrigger(
    "after_update_on_sqlitedata_icloud_metadata",
    ifNotExists: true,
    after: .update { _, new in
      Values(.didUpdate(new))
    } when: { old, new in
      old.isDeleted.eq(new.isDeleted) && !SyncEngine.isSynchronizingChanges()
    }
  )

  fileprivate static let afterDeleteTrigger = createTemporaryTrigger(
    "after_delete_on_sqlitedata_icloud_metadata",
    ifNotExists: true,
    after: .update(of: \.isDeleted) { _, new in
      Values(.didDelete(
        recordName: new.recordName,
        lastKnownServerRecord: new.lastKnownServerRecord
        ?? rootServerRecord(recordName: new.recordName),
        share: new.share
      ))
    } when: { old, new in
      !old.isDeleted && new.isDeleted && !SyncEngine.isSynchronizingChanges()
    }
  )
}

extension QueryExpression where Self == SQLQueryExpression<()> {
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  fileprivate static func didUpdate(
    _ new: StructuredQueriesCore.TableAlias<
      SyncMetadata, TemporaryTrigger<SyncMetadata>.Operation._New
    >
    .TableColumns
  ) -> Self {
    .didUpdate(
      recordName: new.recordName,
      // TODO: separate lastKnownServerRecord from rootRecord
      lastKnownServerRecord: new.lastKnownServerRecord
      ?? rootServerRecord(recordName: new.recordName),
      share: new.share
    )
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  private static func didUpdate(
    recordName: some QueryExpression<String>,
    lastKnownServerRecord: some QueryExpression<CKRecord.SystemFieldsRepresentation?>,
    share: some QueryExpression<CKShare?.SystemFieldsRepresentation>
  ) -> Self {
    Self("\(raw: .sqliteDataCloudKitSchemaName)_didUpdate(\(recordName), \(lastKnownServerRecord), \(share))")
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  fileprivate static func didDelete(
    recordName: some QueryExpression<String>,
    lastKnownServerRecord: some QueryExpression<CKRecord.SystemFieldsRepresentation?>,
    share: some QueryExpression<CKShare?.SystemFieldsRepresentation>
  ) -> Self {
    Self("\(raw: .sqliteDataCloudKitSchemaName)_didDelete(\(recordName), \(lastKnownServerRecord), \(share))")
  }
}

private func isUpdatingWithServerRecord() -> SQLQueryExpression<Bool> {
  SQLQueryExpression("\(raw: .sqliteDataCloudKitSchemaName)_isUpdatingWithServerRecord()")
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
private func rootServerRecord(
  recordName: some QueryExpression<String>
) -> some QueryExpression<CKRecord?.SystemFieldsRepresentation> {
  With {
    SyncMetadata
      .where { $0.recordName.eq(recordName) }
      .select { AncestorMetadata.Columns($0) }
      .union(
        all: true,
        SyncMetadata
          .select { AncestorMetadata.Columns($0) }
          .join(AncestorMetadata.all) { $0.recordName.is($1.parentRecordName) }
      )
  } query: {
    AncestorMetadata
      .select(\.lastKnownServerRecord)
      .where { $0.parentRecordName.is(nil) }
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension AncestorMetadata.Columns {
  init(_ metadata: SyncMetadata.TableColumns) {
    self.init(
      recordName: metadata.recordName,
      parentRecordName: metadata.parentRecordName,
      lastKnownServerRecord: metadata.lastKnownServerRecord
    )
  }
}
#endif
