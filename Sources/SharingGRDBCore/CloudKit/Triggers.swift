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
          .where {
            $0.recordPrimaryKey.eq(SQLQueryExpression("\(old.primaryKey)"))
              && $0.recordType.eq(tableName)
          }
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
      $0.parentRecordPrimaryKey = SQLQueryExpression(#""excluded"."parentRecordPrimaryKey""#)
      $0.parentRecordType = SQLQueryExpression(#""excluded"."parentRecordType""#)
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

//extension StructuredQueriesCore.TableAlias.TableColumns {
//  public subscript<Member>(
//    dynamicMember keyPath: KeyPath<Base.TableColumns, Member>
//  ) -> Member {
//    Base.columns[keyPath: keyPath]
//  }
//}

extension QueryExpression where Self == SQLQueryExpression<()> {
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  fileprivate static func didUpdate(
    _ new: StructuredQueriesCore.TableAlias<SyncMetadata, TemporaryTrigger<SyncMetadata>.Operation._New>.TableColumns
  ) -> Self {
    .didUpdate(
      recordName: SQLQueryExpression(#""new"."recordName""#),
      lastKnownServerRecord: new.lastKnownServerRecord
      ?? SyncMetadata
        .where { $0.recordName.is(SQLQueryExpression(#""new"."parentRecordName""#)) }
        .select(\.lastKnownServerRecord)
    )
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  fileprivate static func didDelete(
    _ old: StructuredQueriesCore.TableAlias<SyncMetadata, TemporaryTrigger<SyncMetadata>.Operation._Old>.TableColumns
  )
  -> Self
  {
    .didDelete(
      recordName: SQLQueryExpression(#""old"."recordName""#),
      lastKnownServerRecord: old.lastKnownServerRecord
      ?? SyncMetadata
        .where { $0.recordName.is(SQLQueryExpression(#""old"."parentRecordName""#)) }
        .select(\.lastKnownServerRecord)
    )
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  private static func didUpdate(
    recordName: some QueryExpression<String>,
    lastKnownServerRecord: some QueryExpression<CKRecord.SystemFieldsRepresentation?>
  ) -> Self {
    Self("\(raw: .sqliteDataCloudKitSchemaName)_didUpdate(\(recordName), \(lastKnownServerRecord))")
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  private static func didDelete(
    recordName: some QueryExpression<String>,
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
