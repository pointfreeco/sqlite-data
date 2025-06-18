import CloudKit
import StructuredQueriesCore

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension Metadata {
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
    let foreignKey = (parentForeignKey?.from).map { #""new"."\#($0)""# } ?? "NULL"

    let upsert: QueryFragment = """
      INSERT INTO \(Metadata.self)
        (
          \(quote: Metadata.recordType.name),
          \(quote: Metadata.recordName.name),
          \(quote: Metadata.parentRecordName.name),
          \(quote: Metadata.userModificationDate.name)
        )
      SELECT
        \(quote: T.tableName, delimiter: .text),
        "new".\(quote: T.columns.primaryKey.name),
        \(raw: foreignKey) AS "foreignKey",
        datetime('subsec')
      ON CONFLICT(\(quote: Metadata.recordName.name)) DO UPDATE
      SET
        \(quote: Metadata.recordType.name) = "excluded".\(quote: Metadata.recordType.name),
        \(quote: Metadata.parentRecordName.name) = "excluded".\(quote: Metadata.parentRecordName.name),
        \(quote: Metadata.userModificationDate.name)  = "excluded".\(quote: Metadata.userModificationDate.name)
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
      #""\#(raw: .sqliteDataCloudKitSchemaName)_\#(raw: T.tableName)_metadataInserts""#
    )
  }

  private static func updateTriggerName<T: PrimaryKeyedTable>(
    for _: T.Type
  ) -> SQLQueryExpression<Void> {
    SQLQueryExpression(
      #""\#(raw: .sqliteDataCloudKitSchemaName)_\#(raw: T.tableName)_metadataUpdates""#
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
        Metadata
          .where { $0.recordName.eq(old.primaryKey) }
          .delete()
      }
    )
  }
}
