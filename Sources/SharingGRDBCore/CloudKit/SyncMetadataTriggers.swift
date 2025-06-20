import CloudKit
import StructuredQueriesCore

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncMetadata {
  fileprivate static let afterInsertTrigger = createTemporaryTrigger(
    "after_insert_on_sqlitedata_icloud_metadata",
    ifNotExists: true,
    after: .insert {
      SQLQueryExpression(
        "SELECT \(raw: .sqliteDataCloudKitSchemaName)_didUpdate(\($0.recordName))"
      )
    } when: { _ in
      SQLQueryExpression("NOT \(raw: .sqliteDataCloudKitSchemaName)_isUpdatingWithServerRecord()")
    }
  )

  fileprivate static let afterUpdateTrigger = createTemporaryTrigger(
    "after_update_on_sqlitedata_icloud_metadata",
    ifNotExists: true,
    after: .update { _, new in
      SQLQueryExpression(
        "SELECT \(raw: .sqliteDataCloudKitSchemaName)_didUpdate(\(new.recordName))"
      )
    } when: { _, _ in
      SQLQueryExpression("NOT \(raw: .sqliteDataCloudKitSchemaName)_isUpdatingWithServerRecord()")
    }
  )

  fileprivate static let afterDeleteTrigger = createTemporaryTrigger(
    "after_delete_on_sqlitedata_icloud_metadata",
    ifNotExists: true,
    after: .delete {
      SQLQueryExpression(
        "SELECT \(raw: .sqliteDataCloudKitSchemaName)_didDelete(\($0.recordName))"
      )
    } when: { _ in
      SQLQueryExpression("NOT \(raw: .sqliteDataCloudKitSchemaName)_isUpdatingWithServerRecord()")
    }
  )

  static func createTriggers(
    tables: [any PrimaryKeyedTable.Type],
    db: Database
  ) throws {
    try afterInsertTrigger.execute(db)
    try afterUpdateTrigger.execute(db)
    try afterDeleteTrigger.execute(db)
  }

  static func dropTriggers(
    tables: [any PrimaryKeyedTable.Type],
    db: Database
  ) throws {
    try afterDeleteTrigger.drop().execute(db)
    try afterUpdateTrigger.drop().execute(db)
    try afterInsertTrigger.drop().execute(db)
  }

  static func createTriggers<T: PrimaryKeyedTable<UUID>>(
    for _: T.Type,
    parentForeignKey: ForeignKey?,
    db: Database
  ) throws {
    let foreignKey = parentForeignKey.map {
      #"'\#($0.table)' || ':' ||  "new"."\#($0.from)""#
    } ?? "NULL"

    let upsert: QueryFragment = """
      INSERT INTO \(Self.self)
        (
          \(quote: recordType.name),
          \(quote: recordName.name),
          \(quote: parentRecordName.name),
          \(quote: userModificationDate.name)
        )
      SELECT
        \(quote: T.tableName, delimiter: .text),
        \(quote: T.tableName, delimiter: .text) || ':' || "new".\(quote: T.columns.primaryKey.name),
        \(raw: foreignKey) AS "foreignKey",
        datetime('subsec')
      ON CONFLICT(\(quote: SyncMetadata.recordName.name)) DO UPDATE
      SET
        \(quote: recordType.name) = "excluded".\(quote: recordType.name),
        \(quote: parentRecordName.name) = "excluded".\(quote: parentRecordName.name),
        \(quote: userModificationDate.name)  = "excluded".\(quote: userModificationDate.name)
      """

    try SQLQueryExpression(
      """
      CREATE TEMPORARY TRIGGER IF NOT EXISTS \(insertTriggerName(for: T.self))
      AFTER INSERT ON \(T.self) FOR EACH ROW BEGIN
        \(upsert);
      END
      """
    )
    .execute(db)
    try SQLQueryExpression(
      """
      CREATE TEMPORARY TRIGGER IF NOT EXISTS \(updateTriggerName(for: T.self))
      AFTER UPDATE ON \(T.self) FOR EACH ROW BEGIN
        \(upsert);
      END
      """
    )
    .execute(db)

    try T.createDeleteTrigger.execute(db)
  }

  static func dropTriggers<T: PrimaryKeyedTable<UUID>>(
    for _: T.Type,
    db: Database
  ) throws {
    try T.createDeleteTrigger.drop().execute(db)
    try SQLQueryExpression(
      """
      DROP TRIGGER \(updateTriggerName(for: T.self))
      """
    )
    .execute(db)
    try SQLQueryExpression(
      """
      DROP TRIGGER \(insertTriggerName(for: T.self))
      """
    )
    .execute(db)
  }

  private static func insertTriggerName<T: PrimaryKeyedTable>(
    for _: T.Type
  ) -> SQLQueryExpression<Void> {
    SQLQueryExpression(
      "\(quote: "\(String.sqliteDataCloudKitSchemaName)_\(T.tableName)_metadataInserts")"
    )
  }

  private static func updateTriggerName<T: PrimaryKeyedTable>(
    for _: T.Type
  ) -> SQLQueryExpression<Void> {
    SQLQueryExpression(
      "\(quote: "\(String.sqliteDataCloudKitSchemaName)_\(T.tableName)_metadataUpdates")"
    )
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension PrimaryKeyedTable<UUID> {
  fileprivate static var createDeleteTrigger: TemporaryTrigger<Self> {
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
