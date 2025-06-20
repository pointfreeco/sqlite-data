import Foundation

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension PrimaryKeyedTable<UUID> {
  static func metadataTriggers(foreignKey: ForeignKey?) -> [TemporaryTrigger<Self>] {
    [
      afterInsert(foreignKey: foreignKey),
      afterUpdate(foreignKey: foreignKey),
      afterDelete,
    ]
  }

  fileprivate static func afterInsert(foreignKey: ForeignKey?) -> TemporaryTrigger<Self> {
    createTemporaryTrigger(
      "\(String.sqliteDataCloudKitSchemaName)_after_insert_on_\(tableName)",
      after: .insert { new in SyncMetadata.insert(new: new, foreignKey: foreignKey) }
    )
  }

  fileprivate static func afterUpdate(foreignKey: ForeignKey?) -> TemporaryTrigger<Self> {
    createTemporaryTrigger(
      "\(String.sqliteDataCloudKitSchemaName)_after_update_on_\(tableName)",
      after: .update { _, new in SyncMetadata.insert(new: new, foreignKey: foreignKey) }
    )
  }

  fileprivate static var afterDelete: TemporaryTrigger<Self> {
    createTemporaryTrigger(
      "\(String.sqliteDataCloudKitSchemaName)_after_delete_on_\(tableName)",
      ifNotExists: true,
      after: .delete { old in
        SyncMetadata
          .where { $0.recordName.eq(old.recordName) }
          .delete()
      }
    )
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncMetadata {
  fileprivate static func insert<T: PrimaryKeyedTable<UUID>>(
    new: TemporaryTrigger<T>.Operation.New,
    foreignKey: ForeignKey?,
  ) -> some StructuredQueriesCore.Statement {
    let foreignKey = foreignKey.map {
      #""new"."\#($0.from)" || ':' || '\#($0.table)'"#
    } ?? "NULL"
    return insert {
      ($0.recordType, $0.recordName, $0.parentRecordName, $0.userModificationDate)
    } select: {
      Values(
        T.tableName,
        new.recordName,
        SQLQueryExpression(#"\#(raw: foreignKey) AS "foreignKey""#),
        .datetime("subsec")
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

  fileprivate static let afterInsertTrigger = createTemporaryTrigger(
    "after_insert_on_sqlitedata_icloud_metadata",
    ifNotExists: true,
    after: .insert {
      Values(.didUpdate($0.recordName))
    } when: { _ in
      !isUpdatingWithServerRecord()
    }
  )

  fileprivate static let afterUpdateTrigger = createTemporaryTrigger(
    "after_update_on_sqlitedata_icloud_metadata",
    ifNotExists: true,
    after: .update { _, new in
      Values(.didUpdate(new.recordName))
    } when: { _, _ in
      !isUpdatingWithServerRecord()
    }
  )

  fileprivate static let afterDeleteTrigger = createTemporaryTrigger(
    "after_delete_on_sqlitedata_icloud_metadata",
    ifNotExists: true,
    after: .delete {
      Values(.didDelete($0.recordName))
    } when: { _ in
      !isUpdatingWithServerRecord()
    }
  )
}


extension QueryExpression where Self == SQLQueryExpression<()> {
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  fileprivate static func didUpdate(_ expression: some QueryExpression<SyncMetadata.RecordName>) -> Self {
    Self("\(raw: .sqliteDataCloudKitSchemaName)_didUpdate(\(expression))")
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  fileprivate static func didDelete(_ expression: some QueryExpression<SyncMetadata.RecordName>) -> Self {
    Self("\(raw: .sqliteDataCloudKitSchemaName)_didDelete(\(expression))")
  }
}

private func isUpdatingWithServerRecord() -> SQLQueryExpression<Bool> {
  SQLQueryExpression("\(raw: .sqliteDataCloudKitSchemaName)_isUpdatingWithServerRecord()")
}

extension QueryExpression {
  fileprivate static func datetime<D: _OptionalPromotable<Date?>>(_ string: String) -> Self
  where Self == SQLQueryExpression<D> {
    Self("datetime(\(quote: string, delimiter: .text))")
  }
}
