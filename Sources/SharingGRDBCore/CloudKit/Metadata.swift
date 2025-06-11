import CloudKit
import StructuredQueriesCore

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension Metadata {
  static func createTriggers(
    tables: [any PrimaryKeyedTable.Type],
    db: Database
  ) throws {
    try SQLQueryExpression(
      """
      CREATE TEMPORARY TRIGGER IF NOT EXISTS
      "\(raw: .sqliteDataCloudKitSchemaName)_metadata_inserts"
      AFTER INSERT ON \(Metadata.self)
      FOR EACH ROW
      WHEN NOT \(raw: .sqliteDataCloudKitSchemaName)_isUpdatingWithServerRecord()
      BEGIN
        SELECT 
          \(raw: .sqliteDataCloudKitSchemaName)_didUpdate("new"."recordName");
      END
      """
    )
    .execute(db)

    try SQLQueryExpression(
      """
      CREATE TEMPORARY TRIGGER IF NOT EXISTS
      "\(raw: .sqliteDataCloudKitSchemaName)_metadata_updates"
      AFTER UPDATE ON \(Metadata.self)
      FOR EACH ROW
      WHEN NOT \(raw: .sqliteDataCloudKitSchemaName)_isUpdatingWithServerRecord()
      BEGIN
        SELECT 
          \(raw: .sqliteDataCloudKitSchemaName)_didUpdate("new"."recordName");
      END
      """
    )
    .execute(db)
    try SQLQueryExpression(
      """
      CREATE TEMPORARY TRIGGER IF NOT EXISTS
      "\(raw: .sqliteDataCloudKitSchemaName)_metadata_deletes"
      BEFORE DELETE ON \(Metadata.self)
      FOR EACH ROW
      WHEN NOT \(raw: .sqliteDataCloudKitSchemaName)_isUpdatingWithServerRecord()
      BEGIN
        SELECT 
          \(raw: .sqliteDataCloudKitSchemaName)_willDelete("old"."recordName");
      END
      """
    )
    .execute(db)
  }

  static func createTriggers<T: PrimaryKeyedTable>(
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
      FROM (SELECT 1) 
      LEFT JOIN \(Metadata.self) ON \(Metadata.recordName) = "foreignKey"
      ON CONFLICT(\(quote: Metadata.recordName.name)) DO UPDATE
      SET
        \(quote: Metadata.recordType.name) = "excluded".\(quote: Metadata.recordType.name),
        \(quote: Metadata.parentRecordName.name) = "excluded".\(quote: Metadata.parentRecordName.name),
        \(quote: Metadata.recordType.name) = "excluded".\(quote: Metadata.recordType.name),
        \(quote: Metadata.userModificationDate.name)  = "excluded".\(quote: Metadata.userModificationDate.name)
      """

    try SQLQueryExpression(
      """
      CREATE TEMPORARY TRIGGER IF NOT EXISTS \(Self.insertTriggerName(for: T.self))
      AFTER INSERT ON \(T.self) FOR EACH ROW BEGIN
        \(upsert);
      END
      """
    )
    .execute(db)
    try SQLQueryExpression(
      """
      CREATE TEMPORARY TRIGGER IF NOT EXISTS \(Self.updateTriggerName(for: T.self))
      AFTER UPDATE ON \(T.self) FOR EACH ROW BEGIN
        \(upsert);
      END
      """
    )
    .execute(db)
    try SQLQueryExpression(
      """
      CREATE TEMPORARY TRIGGER IF NOT EXISTS \(Self.deleteTriggerName(for: T.self))
      AFTER DELETE ON \(T.self) FOR EACH ROW BEGIN
        DELETE FROM \(Metadata.self)
        WHERE "recordName" = "old".\(quote: T.columns.primaryKey.name);
      END
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

  private static func deleteTriggerName<T: PrimaryKeyedTable>(
    for _: T.Type
  ) -> SQLQueryExpression<Void> {
    SQLQueryExpression(
      #""\#(raw: .sqliteDataCloudKitSchemaName)_\#(raw: T.tableName)_metadataDeletes""#
    )
  }
}
