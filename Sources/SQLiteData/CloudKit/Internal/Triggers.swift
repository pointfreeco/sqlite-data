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
        afterPrimaryKeyChange(parentForeignKey: parentForeignKey),
      ]
    }

    fileprivate static func afterPrimaryKeyChange(parentForeignKey: ForeignKey?)
      -> TemporaryTrigger<Self>
    {
      createTemporaryTrigger(
        "\(String.sqliteDataCloudKitSchemaName)_after_primary_key_change_on_\(tableName)",
        ifNotExists: true,
        after: .update(of: \.primaryKey) { old, new in
          checkWritePermissions(alias: new, parentForeignKey: parentForeignKey)
          SyncMetadata
            .where {
              $0.recordPrimaryKey.eq(#sql("\(old.primaryKey)"))
                && $0.recordType.eq(tableName)
            }
            .update { $0._isDeleted = true }
        } when: { old, new in
          old.primaryKey.neq(new.primaryKey)
        }
      )
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
              $0.recordPrimaryKey.eq(#sql("\(old.primaryKey)"))
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
              $0.recordPrimaryKey.eq(#sql("\(old.primaryKey)"))
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
          #sql("\(new.primaryKey)"),
          T.tableName,
          #sql(parentRecordPrimaryKey),
          #sql(parentRecordType)
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
    static func callbackTriggers(for syncEngine: SyncEngine) -> [TemporaryTrigger<Self>] {
      [
        afterInsertTrigger(for: syncEngine),
        afterUpdateTrigger(for: syncEngine),
        afterSoftDeleteTrigger(for: syncEngine),
      ]
    }

    private enum ParentSyncMetadata: AliasName {}

    fileprivate static func afterInsertTrigger(for syncEngine: SyncEngine) -> TemporaryTrigger<Self>
    {
      createTemporaryTrigger(
        "after_insert_on_sqlitedata_icloud_metadata",
        ifNotExists: true,
        after: .insert { new in
          validate(recordName: new.recordName)
          Values(
            syncEngine.$didUpdate(
              recordName: new.recordName,
              record: new.lastKnownServerRecord
                ?? rootServerRecord(recordName: new.recordName)
            )
          )
        } when: { _ in
          !SyncEngine.isSynchronizingChanges()
        }
      )
    }

    fileprivate static func afterUpdateTrigger(for syncEngine: SyncEngine) -> TemporaryTrigger<Self>
    {
      createTemporaryTrigger(
        "after_update_on_sqlitedata_icloud_metadata",
        ifNotExists: true,
        after: .update { _, new in
          validate(recordName: new.recordName)
          Values(
            syncEngine.$didUpdate(
              recordName: new.recordName,
              record: new.lastKnownServerRecord
                ?? rootServerRecord(recordName: new.recordName)
            )
          )
        } when: { old, new in
          old._isDeleted.eq(new._isDeleted) && !SyncEngine.isSynchronizingChanges()
        }
      )
    }

    fileprivate static func afterSoftDeleteTrigger(for syncEngine: SyncEngine) -> TemporaryTrigger<
      Self
    > {
      createTemporaryTrigger(
        "after_delete_on_sqlitedata_icloud_metadata",
        ifNotExists: true,
        after: .update(of: \._isDeleted) { _, new in
          Values(
            syncEngine.$didDelete(
              recordName: new.recordName,
              record: new.lastKnownServerRecord
                ?? rootServerRecord(recordName: new.recordName),
              share: new.share
            )
          )
        } when: { old, new in
          !old._isDeleted && new._isDeleted && !SyncEngine.isSynchronizingChanges()
        }
      )
    }
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
  private func validate(
    recordName: some QueryExpression<String>
  ) -> some StructuredQueriesCore.Statement<Never> {
    #sql(
      """
      SELECT RAISE(ABORT, \(quote: SyncEngine.invalidRecordNameError, delimiter: .text))
      WHERE NOT \(recordName.isValidCloudKitRecordName)
      """,
      as: Never.self
    )
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
          $0.recordPrimaryKey.is(#sql(parentRecordPrimaryKey))
            && $0.recordType.is(#sql(parentRecordType))
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
          #sql(
            "RAISE(ABORT, \(quote: SyncEngine.writePermissionError, delimiter: .text))",
            as: Never.self
          )
        }
        .where {
          !SyncEngine.isSynchronizingChanges()
            && $0.parentRecordName.is(nil)
            && !$hasPermission($0.share)
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

  extension QueryExpression<String> {
    fileprivate var isValidCloudKitRecordName: some QueryExpression<Bool> {
      substr(1, 1).neq("_") && octetLength().lte(255) && octetLength().eq(length())
    }
  }
#endif
