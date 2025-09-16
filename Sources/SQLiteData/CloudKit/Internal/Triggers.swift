#if canImport(CloudKit)
  import CloudKit
  import Foundation

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension PrimaryKeyedTable {
    static func metadataTriggers(
      parentForeignKey: ForeignKey?,
      defaultZone: CKRecordZone
    ) -> [TemporaryTrigger<Self>] {
      [
        afterInsert(parentForeignKey: parentForeignKey, defaultZone: defaultZone),
        afterUpdate(parentForeignKey: parentForeignKey, defaultZone: defaultZone),
        afterDeleteFromUser(parentForeignKey: parentForeignKey, defaultZone: defaultZone),
        afterDeleteFromSyncEngine,
        afterPrimaryKeyChange(parentForeignKey: parentForeignKey, defaultZone: defaultZone),
      ]
    }

    fileprivate static func afterPrimaryKeyChange(
      parentForeignKey: ForeignKey?,
      defaultZone: CKRecordZone
    ) -> TemporaryTrigger<Self> {
      createTemporaryTrigger(
        "\(String.sqliteDataCloudKitSchemaName)_after_primary_key_change_on_\(tableName)",
        ifNotExists: true,
        after: .update(of: \.primaryKey) { old, new in
          checkWritePermissions(
            alias: new,
            parentForeignKey: parentForeignKey,
            defaultZone: defaultZone
          )
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

    fileprivate static func afterInsert(
      parentForeignKey: ForeignKey?,
      defaultZone: CKRecordZone
    ) -> TemporaryTrigger<Self> {
      createTemporaryTrigger(
        "\(String.sqliteDataCloudKitSchemaName)_after_insert_on_\(tableName)",
        ifNotExists: true,
        after: .insert { new in
          checkWritePermissions(
            alias: new,
            parentForeignKey: parentForeignKey,
            defaultZone: defaultZone
          )
          SyncMetadata.upsert(
            new: new,
            parentForeignKey: parentForeignKey,
            defaultZone: defaultZone
          )
        }
      )
    }

    fileprivate static func afterUpdate(
      parentForeignKey: ForeignKey?,
      defaultZone: CKRecordZone
    ) -> TemporaryTrigger<Self> {
      createTemporaryTrigger(
        "\(String.sqliteDataCloudKitSchemaName)_after_update_on_\(tableName)",
        ifNotExists: true,
        after: .update { _, new in
          checkWritePermissions(
            alias: new,
            parentForeignKey: parentForeignKey,
            defaultZone: defaultZone
          )
          SyncMetadata.upsert(
            new: new,
            parentForeignKey: parentForeignKey,
            defaultZone: defaultZone
          )
        }
      )
    }

    fileprivate static func afterDeleteFromUser(
      parentForeignKey: ForeignKey?,
      defaultZone: CKRecordZone
    ) -> TemporaryTrigger<
      Self
    > {
      createTemporaryTrigger(
        "\(String.sqliteDataCloudKitSchemaName)_after_delete_on_\(tableName)_from_user",
        ifNotExists: true,
        after: .delete { old in
          checkWritePermissions(
            alias: old,
            parentForeignKey: parentForeignKey,
            defaultZone: defaultZone
          )
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
      defaultZone: CKRecordZone
    ) -> some StructuredQueriesCore.Statement {
      let (parentRecordPrimaryKey, parentRecordType, zoneName, ownerName) = parentFields(
        alias: new,
        parentForeignKey: parentForeignKey,
        defaultZone: defaultZone
      )
      return insert {
        (
          $0.recordPrimaryKey,
          $0.recordType,
          $0.zoneName,
          $0.ownerName,
          $0.parentRecordPrimaryKey,
          $0.parentRecordType
        )
      } select: {
        Values(
          #sql("\(new.primaryKey)"),
          T.tableName,
          zoneName,
          ownerName,
          parentRecordPrimaryKey,
          parentRecordType
        )
      } onConflict: {
        ($0.recordPrimaryKey, $0.recordType)
      } doUpdate: {
        $0.zoneName = Case($1.zoneName)
          .when(defaultZone.zoneID.zoneName, then: $0.zoneName)
          .else($1.zoneName)
        $0.ownerName = Case($1.ownerName)
          .when(defaultZone.zoneID.ownerName, then: $0.ownerName)
          .else($1.ownerName)
        $0.parentRecordPrimaryKey = $1.parentRecordPrimaryKey
        $0.parentRecordType = $1.parentRecordType
        $0.userModificationTime = $1.userModificationTime
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
              zoneName: new.zoneName,
              ownerName: new.ownerName,
              oldZoneName: new.zoneName,
              oldOwnerName: new.ownerName,
              descendantRecordNames: #bind(nil)
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
        after: .update { old, new in
          let zoneChanged = new.zoneName.neq(old.zoneName) || new.ownerName.neq(old.ownerName)
          let selfAndDescendantRecordNames = descendantRecordNames(
            recordName: new.recordName,
            includeSelf: true
          ) {
            $0.select(\.recordName)
          }
          let descendantRecordNamesJSON = descendantRecordNames(
            recordName: new.recordName,
            includeSelf: false
          ) {
            $0.select { $0.recordName.jsonGroupArray() }
          }

          validate(recordName: new.recordName)
          SyncMetadata
            .where {
              zoneChanged && $0.recordName.in(selfAndDescendantRecordNames)
            }
            .update {
              $0.zoneName = new.zoneName
              $0.ownerName = new.ownerName
              $0.lastKnownServerRecord = nil
              $0._lastKnownServerRecordAllFields = nil
            }
          Values(
            syncEngine.$didUpdate(
              recordName: new.recordName,
              zoneName: new.zoneName,
              ownerName: new.ownerName,
              oldZoneName: old.zoneName,
              oldOwnerName: old.ownerName,
              descendantRecordNames: Case().when(zoneChanged, then: descendantRecordNamesJSON)
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

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  private func parentFields<Base, Name>(
    alias: StructuredQueriesCore.TableAlias<Base, Name>.TableColumns,
    parentForeignKey: ForeignKey?,
    defaultZone: CKRecordZone
  ) -> (
    parentRecordPrimaryKey: SQLQueryExpression<String>?,
    parentRecordType: SQLQueryExpression<String>?,
    zoneName: SQLQueryExpression<String>,
    ownerName: SQLQueryExpression<String>
  ) {
    let defaultZoneName = #sql(
      "\(quote: defaultZone.zoneID.zoneName, delimiter: .text)",
      as: String.self
    )
    let defaultOwnerName = #sql(
      "\(quote: defaultZone.zoneID.ownerName, delimiter: .text)",
      as: String.self
    )
    return
      parentForeignKey
      .map { foreignKey in
        let parentRecordPrimaryKey = #sql(
          #"\#(type(of: alias).QueryValue.self).\#(quote: foreignKey.from)"#,
          as: String.self
        )
        let parentRecordType = #sql("\(bind: foreignKey.table)", as: String.self)
        let parentMetadata =
          SyncMetadata
          .where {
            $0.recordPrimaryKey.eq(parentRecordPrimaryKey)
              && $0.recordType.eq(parentRecordType)
          }
        return (
          parentRecordPrimaryKey,
          parentRecordType,
          #sql(
            "coalesce(\($currentZoneName()), (\(parentMetadata.select(\.zoneName))), \(defaultZoneName))"
          ),
          #sql(
            "coalesce(\($currentOwnerName()), (\(parentMetadata.select(\.ownerName))), \(defaultOwnerName))"
          )
        )
      }
      ?? (
        nil,
        nil,
        #sql("coalesce(\($currentZoneName()), \(defaultZoneName))"),
        #sql("coalesce(\($currentOwnerName()), \(defaultOwnerName))")
      )
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
    parentForeignKey: ForeignKey?,
    defaultZone: CKRecordZone
  ) -> some StructuredQueriesCore.Statement<Never> {
    let (parentRecordPrimaryKey, parentRecordType, _, _) = parentFields(
      alias: alias,
      parentForeignKey: parentForeignKey,
      defaultZone: defaultZone
    )

    return With {
      SyncMetadata
        .where {
          $0.recordPrimaryKey.is(parentRecordPrimaryKey)
            && $0.recordType.is(parentRecordType)
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
  private func descendantRecordNames<T>(
    recordName: some QueryExpression<String>,
    includeSelf: Bool,
    select: (Where<DescendantMetadata>) -> Select<T, DescendantMetadata, ()>
  ) -> some Statement<T> {
    With {
      SyncMetadata
        .where { $0.recordName.eq(recordName) }
        .select {
          DescendantMetadata.Columns(recordName: $0.recordName, parentRecordName: #bind(nil))
        }
        .union(
          all: true,
          SyncMetadata
            .select {
              DescendantMetadata.Columns(
                recordName: $0.recordName,
                parentRecordName: $0.parentRecordName
              )
            }
            .join(DescendantMetadata.all) { $0.parentRecordName.eq($1.recordName) }
        )
    } query: {
      select(
        DescendantMetadata.where {
          if !includeSelf {
            $0.recordName.neq(recordName)
          }
        }
      )
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
  private func parentLastKnownServerRecord(
    parentRecordPrimaryKey: some QueryExpression<String?>,
    parentRecordType: some QueryExpression<String?>
  ) -> some QueryExpression<CKRecord?.SystemFieldsRepresentation> {
    SyncMetadata
      .select(\.lastKnownServerRecord)
      .where {
        $0.recordPrimaryKey.is(parentRecordPrimaryKey)
          && $0.recordType.is(parentRecordType)
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

  @Table @Selection
  private struct DescendantMetadata {
    let recordName: String
    let parentRecordName: String?
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Table @Selection
  private struct AncestorMetadata {
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
  private struct RootShare {
    let parentRecordName: String?
    @Column(as: CKShare?.SystemFieldsRepresentation.self)
    let share: CKShare?
  }
#endif
