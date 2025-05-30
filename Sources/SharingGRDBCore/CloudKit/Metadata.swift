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
      CREATE TEMPORARY TRIGGER IF NOT EXISTS "metadata_inserts"
      AFTER INSERT ON \(Metadata.self)
      FOR EACH ROW 
      BEGIN
        SELECT 
          \(raw: String.sqliteDataCloudKitSchemaName)_didUpdate(
            "new"."recordName",
            "new"."zoneName",
            "new"."ownerName"
          )
        WHERE NOT \(raw: String.sqliteDataCloudKitSchemaName)_isUpdatingWithServerRecord();
      END
      """
    )
    .execute(db)

    try SQLQueryExpression(
      """
      CREATE TEMPORARY TRIGGER IF NOT EXISTS "metadata_updates"
      AFTER UPDATE ON \(Metadata.self)
      FOR EACH ROW 
      BEGIN
        SELECT 
          \(raw: String.sqliteDataCloudKitSchemaName)_didUpdate(
            "new"."recordName",
            "new"."zoneName",
            "new"."ownerName"
          )
        WHERE NOT \(raw: String.sqliteDataCloudKitSchemaName)_isUpdatingWithServerRecord()
      ;
      END
      """
    )
    .execute(db)
    try SQLQueryExpression(
      """
      CREATE TEMPORARY TRIGGER IF NOT EXISTS "metadata_deletes"
      BEFORE DELETE ON \(Metadata.self)
      FOR EACH ROW 
      BEGIN
        SELECT 
          \(raw: String.sqliteDataCloudKitSchemaName)_willDelete(
            "old"."recordName",
            "old"."zoneName",
            "old"."ownerName"
          )
        WHERE NOT \(raw: String.sqliteDataCloudKitSchemaName)_isUpdatingWithServerRecord();
      END
      """
    )
    .execute(db)
  }

  static func dropTriggers(db: Database) throws {
    try SQLQueryExpression(#"DROP TRIGGER "metadata_deletes""#).execute(db)
    try SQLQueryExpression(#"DROP TRIGGER "metadata_updates""#).execute(db)
    try SQLQueryExpression(#"DROP TRIGGER "metadata_inserts""#).execute(db)
  }

  static func createTriggers<T: PrimaryKeyedTable>(
    for _: T.Type,
    parentForeignKey: ForeignKey?,
    db: Database
  ) throws {
    let foreignKeyName = (parentForeignKey?.from).map { #""new"."\#($0)""# } ?? "NULL"

    try SQLQueryExpression(
      """
      CREATE TEMPORARY TRIGGER \(Self.insertTriggerName(for: T.self))
      AFTER INSERT ON \(T.self) FOR EACH ROW BEGIN
        INSERT INTO \(Metadata.self)
          (
            \(quote: Metadata.recordType.name),
            \(quote: Metadata.recordName.name),
            \(quote: Metadata.zoneName.name),
            \(quote: Metadata.ownerName.name),
            \(quote: Metadata.parentRecordName.name),
            \(quote: Metadata.userModificationDate.name)
          )
        SELECT
          \(quote: T.tableName, delimiter: .text),
          "new".\(quote: T.columns.primaryKey.name),
          coalesce(
            \(Metadata.zoneName), 
            \(raw: String.sqliteDataCloudKitSchemaName)_getZoneName(), 
            \(quote: SyncEngine.defaultZone.zoneID.zoneName, delimiter: .text)
          ),
          coalesce(
            \(Metadata.ownerName), 
            \(raw: String.sqliteDataCloudKitSchemaName)_getOwnerName(), 
            \(quote: SyncEngine.defaultZone.zoneID.ownerName, delimiter: .text)
          ),
          \(raw: foreignKeyName) AS "foreignKeyName",
          datetime('subsec')
        FROM (SELECT 1) 
        LEFT JOIN \(Metadata.self) ON \(Metadata.recordName) = "foreignKeyName"
        ON CONFLICT("recordName") DO NOTHING;
      END
      """
    )
    .execute(db)
    try SQLQueryExpression(
      """
      CREATE TEMPORARY TRIGGER \(Self.updateTriggerName(for: T.self))
      AFTER UPDATE ON \(T.self) FOR EACH ROW BEGIN
        UPDATE \(Metadata.self)
        SET
          "recordName" = "new".\(quote: T.columns.primaryKey.name),
          "userModificationDate" = datetime('subsec'),
          "parentRecordName" = \(raw: foreignKeyName)
        WHERE "recordName" = "old".\(quote: T.columns.primaryKey.name)
        ;
      END
      """
    )
    .execute(db)
    try SQLQueryExpression(
      """
      CREATE TEMPORARY TRIGGER \(Self.deleteTriggerName(for: T.self))
      AFTER DELETE ON \(T.self) FOR EACH ROW BEGIN
        DELETE FROM \(Metadata.self)
        WHERE "recordName" = "old".\(quote: T.columns.primaryKey.name);
      END
      """
    )
    .execute(db)
  }

  static func dropTriggers<T: PrimaryKeyedTable>(
    for _: T.Type,
    db: Database
  ) throws {
    try SQLQueryExpression("DROP TRIGGER \(Self.deleteTriggerName(for: T.self))").execute(db)
    try SQLQueryExpression("DROP TRIGGER \(Self.updateTriggerName(for: T.self))").execute(db)
    try SQLQueryExpression("DROP TRIGGER \(Self.insertTriggerName(for: T.self))").execute(db)
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
