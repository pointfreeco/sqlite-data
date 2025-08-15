#if canImport(CloudKit)
  import CloudKit
  import Foundation

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension PrimaryKeyedTable {
    static func metadataTriggers(parentForeignKey: ForeignKey?) -> [TemporaryTrigger<Self>] {
      [
        afterInsert(parentForeignKey: parentForeignKey),
        afterUpdate(parentForeignKey: parentForeignKey),
        afterDeleteFromUser(parentForeignKey: parentForeignKey),
        afterDeleteFromSyncEngine,
      ]
    }

    fileprivate static func afterInsert(parentForeignKey: ForeignKey?) -> TemporaryTrigger<Self> {
      createTemporaryTrigger(
        "\(String.sqliteDataCloudKitSchemaName)_after_insert_on_\(tableName)",
        ifNotExists: true,
        after: .insert { new in
          checkWritePermissions(alias: new, parentForeignKey: parentForeignKey)
          SyncMetadata.upsert(new: new, parentForeignKey: parentForeignKey)
        }
      )
    }

    fileprivate static func afterUpdate(parentForeignKey: ForeignKey?) -> TemporaryTrigger<Self> {
      createTemporaryTrigger(
        "\(String.sqliteDataCloudKitSchemaName)_after_update_on_\(tableName)",
        ifNotExists: true,
        after: .update { _, new in
          checkWritePermissions(alias: new, parentForeignKey: parentForeignKey)
          SyncMetadata.upsert(new: new, parentForeignKey: parentForeignKey)
        }
      )
    }

    fileprivate static func afterDeleteFromUser(parentForeignKey: ForeignKey?) -> TemporaryTrigger<
      Self
    > {
      createTemporaryTrigger(
        "\(String.sqliteDataCloudKitSchemaName)_after_delete_on_\(tableName)_from_user",
        ifNotExists: true,
        after: .delete { old in
          checkWritePermissions(alias: old, parentForeignKey: parentForeignKey)
          SyncMetadata
            .where {
              $0.recordPrimaryKey.eq(SQLQueryExpression("\(old.primaryKey)"))
                && $0.recordType.eq(tableName)
            }
            .update { $0._isDeleted = true }
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
    fileprivate static func upsert<T: PrimaryKeyedTable, Name>(
      new: StructuredQueriesCore.TableAlias<T, Name>.TableColumns,
      parentForeignKey: ForeignKey?,
    ) -> some StructuredQueriesCore.Statement {
      let (parentRecordPrimaryKey, parentRecordType) = parentFields(
        alias: new,
        parentForeignKey: parentForeignKey
      )
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
        afterSoftDeleteTrigger,
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
        old._isDeleted.eq(new._isDeleted) && !SyncEngine.isSynchronizingChanges()
      }
    )

    fileprivate static let afterSoftDeleteTrigger = createTemporaryTrigger(
      "after_delete_on_sqlitedata_icloud_metadata",
      ifNotExists: true,
      after: .update(of: \._isDeleted) { _, new in
        Values(
          .didDelete(
            recordName: new.recordName,
            lastKnownServerRecord: new.lastKnownServerRecord
              ?? rootServerRecord(recordName: new.recordName),
            share: new.share
          )
        )
      } when: { old, new in
        !old._isDeleted && new._isDeleted && !SyncEngine.isSynchronizingChanges()
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
      Self(
        "\(raw: .sqliteDataCloudKitSchemaName)_didUpdate(\(recordName), \(lastKnownServerRecord), \(share))"
      )
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    fileprivate static func didDelete(
      recordName: some QueryExpression<String>,
      lastKnownServerRecord: some QueryExpression<CKRecord.SystemFieldsRepresentation?>,
      share: some QueryExpression<CKShare?.SystemFieldsRepresentation>
    ) -> Self {
      Self(
        "\(raw: .sqliteDataCloudKitSchemaName)_didDelete(\(recordName), \(lastKnownServerRecord), \(share))"
      )
    }
  }

  private func isUpdatingWithServerRecord() -> SQLQueryExpression<Bool> {
    SQLQueryExpression("\(raw: .sqliteDataCloudKitSchemaName)_isUpdatingWithServerRecord()")
  }

  private func parentFields<Base, Name>(
    alias: StructuredQueriesCore.TableAlias<Base, Name>.TableColumns,
    parentForeignKey: ForeignKey?
  ) -> (parentRecordPrimaryKey: QueryFragment, parentRecordType: QueryFragment) {
    parentForeignKey
      .map { (#"\#(type(of: alias).QueryValue.self).\#(quote: $0.from)"#, "\(bind: $0.table)") }
      ?? ("NULL", "NULL")
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  private func checkWritePermissions<Base, Name>(
    alias: StructuredQueriesCore.TableAlias<Base, Name>.TableColumns,
    parentForeignKey: ForeignKey?
  ) -> some StructuredQueriesCore.Statement<Never> {
    let (parentRecordPrimaryKey, parentRecordType) = parentFields(
      alias: alias,
      parentForeignKey: parentForeignKey
    )

    return With {
      SyncMetadata
        .where {
          $0.recordPrimaryKey.is(SQLQueryExpression(parentRecordPrimaryKey))
            && $0.recordType.is(SQLQueryExpression(parentRecordType))
        }
        .select { RootShare.Columns(parentRecordName: $0.parentRecordName, share: $0.share) }
        .union(
          all: true,
          SyncMetadata
            .select {
              RootShare.Columns(parentRecordName: $0.parentRecordName, share: $0.share)
            }
            .join(RootShare.all) { $0.recordName.is($1.parentRecordName) }
        )
    } query: {
      RootShare
        .select { _ in
          SQLQueryExpression(
            "RAISE(ABORT, \(quote: SyncEngine.writePermissionError, delimiter: .text))",
            as: Never.self
          )
        }
        .where {
          $0.parentRecordName.is(nil)
            && !SQLQueryExpression(
              "\(raw: String.sqliteDataCloudKitSchemaName)_hasPermission(\($0.share))"
            )
        }
    }
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
