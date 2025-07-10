import CloudKit
import Foundation

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension PrimaryKeyedTable<UUID> {
  static func metadataTriggers(parentForeignKey: ForeignKey?) -> [TemporaryTrigger<Self>] {
    [
      afterInsert(parentForeignKey: parentForeignKey),
      afterUpdate(parentForeignKey: parentForeignKey),
      afterDelete,
    ]
  }

  fileprivate static func afterInsert(parentForeignKey: ForeignKey?) -> TemporaryTrigger<Self> {
    createTemporaryTrigger(
      "\(String.sqliteDataCloudKitSchemaName)_after_insert_on_\(tableName)",
      ifNotExists: true,
      after: .insert { new in SyncMetadata.insert(new: new, parentForeignKey: parentForeignKey) }
    )
  }

  fileprivate static func afterUpdate(parentForeignKey: ForeignKey?) -> TemporaryTrigger<Self> {
    createTemporaryTrigger(
      "\(String.sqliteDataCloudKitSchemaName)_after_update_on_\(tableName)",
      ifNotExists: true,
      after: .update { _, new in SyncMetadata.insert(new: new, parentForeignKey: parentForeignKey) }
    )
  }

  fileprivate static var afterDelete: TemporaryTrigger<Self> {
    createTemporaryTrigger(
      "\(String.sqliteDataCloudKitSchemaName)_after_delete_on_\(tableName)",
      ifNotExists: true,
      after: .delete { old in
        SyncMetadata
          .find(old.recordName)
          .delete()
      }
    )
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncMetadata {
  fileprivate static func insert<T: PrimaryKeyedTable<UUID>>(
    new: TemporaryTrigger<T>.Operation.New,
    parentForeignKey: ForeignKey?,
  ) -> some StructuredQueriesCore.Statement {
    let parentForeignKey =
      parentForeignKey.map {
        #""new"."\#($0.from)" || ':' || '\#($0.table)'"#
      } ?? "NULL"
    return insert {
      ($0.recordType, $0.recordName, $0.parentRecordName)
    } select: {
      Values(
        T.tableName,
        new.recordName,
        SQLQueryExpression(#"\#(raw: parentForeignKey) AS "foreignKey""#)
      )
    } onConflict: {
      $0.recordName
    } doUpdate: {
      $0.recordName = SQLQueryExpression(#""excluded"."recordName""#)
      $0.parentRecordName = SQLQueryExpression(#""excluded"."parentRecordName""#)
      $0.userModificationDate = SQLQueryExpression(#""excluded"."userModificationDate""#)
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
      !SyncEngine.isUpdatingRecord()
    }
  )

  fileprivate static let afterUpdateTrigger = createTemporaryTrigger(
    "after_update_on_sqlitedata_icloud_metadata",
    ifNotExists: true,
    after: .update { _, new in
      Values(.didUpdate(new))
    } when: { _, _ in
      !SyncEngine.isUpdatingRecord()
    }
  )

  fileprivate static let afterDeleteTrigger = createTemporaryTrigger(
    "after_delete_on_sqlitedata_icloud_metadata",
    ifNotExists: true,
    after: .delete { old in
      Values(.didDelete(old))
    } when: { _ in
      !SyncEngine.isUpdatingRecord()
    }
  )
}


@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
func rootServerRecord(
  recordName: some QueryExpression<SyncMetadata.RecordName>
) -> some QueryExpression<CKRecord?.SystemFieldsRepresentation> {
  With {
    SyncMetadata
      .find(recordName)
      .select {
        SyncMetadata.AncestorMetadata.Columns(
          recordName: $0.recordName,
          parentRecordName: $0.parentRecordName,
          lastKnownServerRecord: $0.lastKnownServerRecord
        )
      }
      .union(
        all: true,
        SyncMetadata
          .select {
            SyncMetadata.AncestorMetadata.Columns(
              recordName: $0.recordName,
              parentRecordName: $0.parentRecordName,
              lastKnownServerRecord: $0.lastKnownServerRecord
            )
          }
          .join(SyncMetadata.AncestorMetadata.all) { $0.recordName.is($1.parentRecordName) }
      )
  } query: {
    SyncMetadata.AncestorMetadata
      .select(\.lastKnownServerRecord)
      .where { $0.parentRecordName.is(nil) }
  }
}

/*
 WITH RECURSIVE ancestry(recordName, parentRecordName) AS (
 SELECT recordName, parentRecordName FROM sqlitedata_icloud_metadata WHERE recordName = 'fadbb91c-4565-4292-aa6e-579957f82371:modelCs'
 UNION ALL
 SELECT u.recordName, u.parentRecordName FROM sqlitedata_icloud_metadata u
 JOIN ancestry a ON u.recordName = a.parentRecordName
 )
 SELECT recordName FROM ancestry
 WHERE parentRecordName IS NULL;
 */





// TODO: can we remove a layer of didUpdate/didDelete?
extension QueryExpression where Self == SQLQueryExpression<()> {
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  fileprivate static func didUpdate(
    _ new: StructuredQueriesCore.TableAlias<SyncMetadata, TemporaryTrigger<SyncMetadata>.Operation._New>.TableColumns
  ) -> Self {
    .didUpdate(
      recordName: new.recordName,
      lastKnownServerRecord: new.lastKnownServerRecord
      ?? rootServerRecord(recordName: new.recordName)
    )
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  fileprivate static func didDelete(
    _ old: StructuredQueriesCore.TableAlias<SyncMetadata, TemporaryTrigger<SyncMetadata>.Operation._Old>.TableColumns
  )
  -> Self
  {
    .didDelete(
      recordName: old.recordName,
      lastKnownServerRecord: old.lastKnownServerRecord
      ?? rootServerRecord(recordName: old.recordName)
    )
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  private static func didUpdate(
    recordName: some QueryExpression<SyncMetadata.RecordName>,
    lastKnownServerRecord: some QueryExpression<CKRecord.SystemFieldsRepresentation?>
  ) -> Self {
    Self("\(raw: .sqliteDataCloudKitSchemaName)_didUpdate(\(recordName), \(lastKnownServerRecord))")
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  private static func didDelete(
    recordName: some QueryExpression<SyncMetadata.RecordName>,
    lastKnownServerRecord: some QueryExpression<CKRecord.SystemFieldsRepresentation?>
  )
  -> Self
  {
    Self("\(raw: .sqliteDataCloudKitSchemaName)_didDelete(\(recordName), \(lastKnownServerRecord))")
  }
}

private func isUpdatingWithServerRecord() -> SQLQueryExpression<Bool> {
  SQLQueryExpression("\(raw: .sqliteDataCloudKitSchemaName)_isUpdatingWithServerRecord()")
}
