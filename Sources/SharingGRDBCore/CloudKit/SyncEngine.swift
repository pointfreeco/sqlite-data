import CloudKit
import ConcurrencyExtras
import OSLog

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
public final actor SyncEngine {
  public static nonisolated let defaultZone = CKRecordZone(
    zoneName: "co.pointfree.SharingGRDB.defaultZone"
  )

  let database: any DatabaseWriter
  let logger: Logger
  lazy var metadatabase: any DatabaseWriter = try! DatabaseQueue()
  private let metadatabaseURL: URL
  let tables: [any StructuredQueriesCore.PrimaryKeyedTable.Type]
  let tablesByName: [String: any StructuredQueriesCore.PrimaryKeyedTable.Type]
  fileprivate let foreignKeysByTableName: [String: [ForeignKey]]
  var underlyingSyncEngine: (any CKSyncEngineProtocol)!
  let defaultSyncEngine: (any DatabaseReader, SyncEngine) -> any CKSyncEngineProtocol
  let _container: any Sendable

  let operationQueue = {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    return queue
  }()

  public init(
    container: CKContainer,
    database: any DatabaseWriter,
    logger: Logger = Logger(subsystem: "SQLiteData", category: "CloudKit"),
    tables: [any PrimaryKeyedTable.Type]
  ) throws {
    try self.init(
      container: container,
      defaultSyncEngine: { database, syncEngine in
        CKSyncEngine(
          CKSyncEngine.Configuration(
            database: container.sharedCloudDatabase,
            stateSerialization: try? database.read { db in  // TODO: write test for this
              try StateSerialization.select(\.data).fetchOne(db)
            },
            delegate: syncEngine
          )
        )
      },
      database: database,
      logger: logger,
      metadatabaseURL: URL.metadatabase(container: container),
      tables: tables
    )
  }

  package init(
    defaultSyncEngine: any CKSyncEngineProtocol,
    database: any DatabaseWriter,
    metadatabaseURL: URL,
    tables: [any StructuredQueriesCore.PrimaryKeyedTable.Type]
  ) throws {
    try self.init(
      defaultSyncEngine: { _, _ in defaultSyncEngine },
      database: database,
      logger: Logger(.disabled),
      metadatabaseURL: metadatabaseURL,
      tables: tables
    )
  }

  private init(
    container: (any Sendable)? = Void?.none,
    defaultSyncEngine: @escaping (any DatabaseReader, SyncEngine) -> any CKSyncEngineProtocol,
    database: any DatabaseWriter,
    logger: Logger,
    metadatabaseURL: URL,
    tables: [any StructuredQueriesCore.PrimaryKeyedTable.Type]
  ) throws {
    // TODO: Explain why / link to documentation?
    precondition(
      !database.configuration.foreignKeysEnabled,
      """
      Foreign key support must be disabled to synchronize with CloudKit.
      """
    )
    self._container = container
    self.defaultSyncEngine = defaultSyncEngine
    self.database = database
    self.logger = logger
    self.metadatabaseURL = metadatabaseURL
    self.tables = tables
    self.tablesByName = Dictionary(uniqueKeysWithValues: tables.map { ($0.tableName, $0) })
    self.foreignKeysByTableName = Dictionary(
      uniqueKeysWithValues: try database.read { db in
        try tables.map { table -> (String, [ForeignKey]) in
          (
            table.tableName,
            try ForeignKey.all(table).fetchAll(db)
          )
        }
      }
    )
    Task {
      await withErrorReporting(.sharingGRDBCloudKitFailure) {
        try await setUpSyncEngine()
      }
    }
  }

  nonisolated var container: CKContainer {
    _container as! CKContainer
  }

  package func setUpSyncEngine() throws {
    defer { underlyingSyncEngine = defaultSyncEngine(metadatabase, self) }

    metadatabase = try defaultMetadatabase
    // TODO: go towards idempotent migrations instead of GRDB migrator by the end of all of this
    var migrator = DatabaseMigrator()
    // TODO: do we want this?
    #if DEBUG
      migrator.eraseDatabaseOnSchemaChange = true
    #endif
    migrator.registerMigration("Create Metadata Tables") { db in
      try SQLQueryExpression(
        """
        CREATE TABLE IF NOT EXISTS "\(raw: .sharingGRDBCloudKitSchemaName)_metadata" (
          "recordType" TEXT NOT NULL,
          "recordName" TEXT NOT NULL PRIMARY KEY,
          "zoneName" TEXT NOT NULL,
          "ownerName" TEXT NOT NULL,
          "parentRecordName" TEXT,
          "lastKnownServerRecord" BLOB,
          "userModificationDate" TEXT
        ) STRICT
        """
      )
      .execute(db)
      // TODO: Should we have "parentRecordName TEXT REFERENCES metadata(recordName) ON DELETE CASCADE" ?
      // TODO: Do we ever query for "parentRecordName"? should we add an index?
      try SQLQueryExpression(
        """
        CREATE INDEX IF NOT EXISTS "\(raw: .sharingGRDBCloudKitSchemaName)_metadata_zoneName_ownerName"
        ON "\(raw: .sharingGRDBCloudKitSchemaName)_metadata" ("zoneName", "ownerName")
        """
      )
      .execute(db)
      try SQLQueryExpression(
        """
        CREATE TABLE IF NOT EXISTS "\(raw: .sharingGRDBCloudKitSchemaName)_recordTypes" (
          "tableName" TEXT NOT NULL PRIMARY KEY,
          "schema" TEXT NOT NULL
        ) STRICT
        """
      )
      .execute(db)
      try SQLQueryExpression(
        """
        CREATE TABLE IF NOT EXISTS "\(raw: .sharingGRDBCloudKitSchemaName)_stateSerialization" (
          "id" INTEGER NOT NULL PRIMARY KEY ON CONFLICT REPLACE CHECK ("id" = 1),
          "data" TEXT NOT NULL
        ) STRICT
        """
      )
      .execute(db)
    }
    try migrator.migrate(metadatabase)
    let previousRecordTypes = try metadatabase.read { db in
      try RecordType.all.fetchAll(db)
    }
    let currentRecordTypes = try database.read { db in
      try SQLQueryExpression(
        """
        SELECT "name", "sql" 
        FROM "sqlite_master" 
        WHERE "type" = 'table'
        AND "name" IN (\(tablesByName.keys.map(\.queryFragment).joined(separator: ", ")))
        """,
        as: RecordType.self
      )
      .fetchAll(db)
    }
    let recordTypesToFetch = currentRecordTypes.filter { currentRecordType in
      guard
        let existingRecordType = previousRecordTypes.first(where: { previousRecordType in
          currentRecordType.tableName == previousRecordType.tableName
        })
      else { return true }
      return existingRecordType.schema != currentRecordType.schema
    }
    if !recordTypesToFetch.isEmpty {
      // TODO: Should we avoid this unstructured task by making 'setUpSyncEngine' async?
      Task {
        await withErrorReporting(.sharingGRDBCloudKitFailure) {
          try await metadatabase.write { db in
            for recordType in recordTypesToFetch {
              try RecordType.upsert(RecordType.Draft(recordType)).execute(db)
            }
          }
        }
        await withErrorReporting(.sharingGRDBCloudKitFailure) {
          try await underlyingSyncEngine.fetchChanges()
        }
      }
    }
    try database.write { db in
      try SQLQueryExpression(
        "ATTACH DATABASE \(metadatabaseURL) AS \(quote: .sharingGRDBCloudKitSchemaName)"
      )
      .execute(db)
      db.add(function: .isUpdatingWithServerRecord)
      db.add(function: .getZoneName)
      db.add(function: .getOwnerName)
      db.add(function: .didUpdate(syncEngine: self))
      db.add(function: .willDelete(syncEngine: self))

      try SQLQueryExpression(
        """
        CREATE TEMPORARY TRIGGER IF NOT EXISTS "metadata_inserts"
        AFTER INSERT ON \(Metadata.self)
        FOR EACH ROW 
        BEGIN
          SELECT 
            \(raw: String.sharingGRDBCloudKitSchemaName)_didUpdate(
              "new"."recordName",
              "new"."zoneName",
              "new"."ownerName"
            )
          WHERE NOT \(raw: String.sharingGRDBCloudKitSchemaName)_isUpdatingWithServerRecord();
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
            \(raw: String.sharingGRDBCloudKitSchemaName)_didUpdate(
              "new"."recordName",
              "new"."zoneName",
              "new"."ownerName"
            )
          WHERE NOT \(raw: String.sharingGRDBCloudKitSchemaName)_isUpdatingWithServerRecord()
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
            \(raw: String.sharingGRDBCloudKitSchemaName)_willDelete(
              "old"."recordName",
              "old"."zoneName",
              "old"."ownerName"
            )
          WHERE NOT \(raw: String.sharingGRDBCloudKitSchemaName)_isUpdatingWithServerRecord();
        END
        """
      )
      .execute(db)

      for table in tables {
        func open<T: PrimaryKeyedTable>(_: T.Type) throws {
          try createTriggers(table: table, db: db)
        }
        try open(table)
      }
    }
  }

  package func tearDownSyncEngine() throws {
    try database.write { db in
      for table in tables {
        func open<T: PrimaryKeyedTable>(_: T.Type) throws {
          try dropTriggers(table: table, db: db)
        }
        try open(table)
      }
      try SQLQueryExpression(
        """
        DROP TRIGGER "metadata_deletes"
        """
      ).execute(db)
      try SQLQueryExpression(
        """
        DROP TRIGGER "metadata_updates"
        """
      ).execute(db)
      try SQLQueryExpression(
        """
        DROP TRIGGER "metadata_inserts"
        """
      ).execute(db)
      db.remove(function: .willDelete(syncEngine: self))
      db.remove(function: .didUpdate(syncEngine: self))
      db.remove(function: .getOwnerName)
      db.remove(function: .getZoneName)
      db.remove(function: .isUpdatingWithServerRecord)
    }
    try database.writeWithoutTransaction { db in
      try SQLQueryExpression(
        "DETACH DATABASE \(quote: .sharingGRDBCloudKitSchemaName)"
      )
      .execute(db)
    }
    try metadatabase.close()
    try FileManager.default.removeItem(at: metadatabaseURL)
  }

  public func fetchChanges() async throws {
    try await underlyingSyncEngine.fetchChanges()
  }

  public func deleteLocalData() throws {
    try tearDownSyncEngine()
    withErrorReporting(.sharingGRDBCloudKitFailure) {
      try database.write { db in
        for table in tables {
          func open<T: PrimaryKeyedTable>(_: T.Type) {
            withErrorReporting(.sharingGRDBCloudKitFailure) {
              try T.delete().execute(db)
            }
          }
          open(table)
        }
      }
    }
    try setUpSyncEngine()
  }

  func didUpdate(recordName: String, zoneName: String, ownerName: String) {
    underlyingSyncEngine.state.add(
      pendingRecordZoneChanges: [
        .saveRecord(
          CKRecord.ID(
            recordName: recordName,
            zoneID: CKRecordZone.ID(
              zoneName: zoneName,
              ownerName: ownerName
            )
          )
        )
      ]
    )
  }

  func willDelete(recordName: String, zoneName: String, ownerName: String) {
    underlyingSyncEngine.state.add(
      pendingRecordZoneChanges: [
        .deleteRecord(
          CKRecord.ID(
            recordName: recordName,
            zoneID: CKRecordZone.ID(
              zoneName: zoneName,
              ownerName: ownerName
            )
          )
        )
      ]
    )
  }

  private var defaultMetadatabase: any DatabaseWriter {
    get throws {
      var configuration = Configuration()
      configuration.prepareDatabase { [logger] db in
        db.trace {
          logger.trace("\($0.expandedDescription)")
        }
      }
      logger.debug(
        """
        Metadatabase connection:
        open "\(self.metadatabaseURL.path(percentEncoded: false))"
        """
      )
      try FileManager.default.createDirectory(
        at: .applicationSupportDirectory,
        withIntermediateDirectories: true
      )
      return try DatabaseQueue(
        path: metadatabaseURL.path(percentEncoded: false),
        configuration: configuration
      )
    }
  }

  private func createTriggers<T: PrimaryKeyedTable>(table: T.Type, db: Database) throws {
    let from =
      foreignKeysByTableName[T.tableName]?.count(where: \.notnull) == 1
      ? foreignKeysByTableName[T.tableName]?.first(where: \.notnull)?.from
      : nil

    try SQLQueryExpression(
      """
      CREATE TEMPORARY TRIGGER
        "\(raw: .sharingGRDBCloudKitSchemaName)_\(raw: T.tableName)_metadataInserts"
      AFTER INSERT ON \(T.self) FOR EACH ROW BEGIN
        INSERT INTO \(Metadata.self)
          ("recordType", "recordName", "zoneName", "ownerName", "parentRecordName", "userModificationDate")
        SELECT
          \(quote: T.tableName, delimiter: .text),
          "new".\(quote: T.columns.primaryKey.name),
          coalesce(
            "zoneName", 
            \(raw: String.sharingGRDBCloudKitSchemaName)_getZoneName(), 
            \(quote: Self.defaultZone.zoneID.zoneName, delimiter: .text)
          ),
          coalesce(
            "ownerName", 
            \(raw: String.sharingGRDBCloudKitSchemaName)_getOwnerName(), 
            \(quote: Self.defaultZone.zoneID.ownerName, delimiter: .text)
          ),
          \(raw: from.map { #""new"."\#($0)""# } ?? "NULL") AS "foreignKeyName",
          datetime('subsec')
        FROM (SELECT 1) 
        LEFT JOIN "\(raw: String.sharingGRDBCloudKitSchemaName)_metadata" ON "recordName" = "foreignKeyName"
        ON CONFLICT("recordName") DO NOTHING;
      END
      """
    )
    .execute(db)
    try SQLQueryExpression(
      """
      CREATE TEMPORARY TRIGGER
        "\(raw: .sharingGRDBCloudKitSchemaName)_\(raw: T.tableName)_metadataUpdates"
      AFTER UPDATE ON \(T.self) FOR EACH ROW BEGIN
        UPDATE \(Metadata.self)
        SET
          "recordName" = "new".\(quote: T.columns.primaryKey.name),
          "userModificationDate" = datetime('subsec'),
          "parentRecordName" = \(raw: from.map { #""new"."\#($0)""# } ?? "NULL")
        WHERE "recordName" = "old".\(quote: T.columns.primaryKey.name)
        ;
      END
      """
    )
    .execute(db)
    try SQLQueryExpression(
      """
      CREATE TEMPORARY TRIGGER
        "\(raw: .sharingGRDBCloudKitSchemaName)_\(raw: T.tableName)_metadataDeletes"
      AFTER DELETE ON \(T.self) FOR EACH ROW BEGIN
        DELETE FROM \(Metadata.self)
        WHERE "recordName" = "old".\(quote: T.columns.primaryKey.name);
      END
      """
    )
    .execute(db)

    let foreignKeys = foreignKeysByTableName[T.tableName] ?? []
    for foreignKey in foreignKeys {
      switch foreignKey.onDelete {
      case .cascade:
        try SQLQueryExpression(
          """
          CREATE TEMPORARY TRIGGER
            "\(raw: .sharingGRDBCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onDeleteCascade"
          AFTER DELETE ON \(quote: foreignKey.table)
          FOR EACH ROW BEGIN
            DELETE FROM \(table)
            WHERE \(quote: foreignKey.from) = "old".\(quote: foreignKey.to);
          END
          """
        )
        .execute(db)

      case .restrict:
        // TODO: Report issue?
        continue

      case .setDefault:
        let defaultValue =
          try SQLQueryExpression(
            """
            SELECT "dflt_value"
            FROM pragma_table_info(\(bind: T.tableName))
            WHERE "name" = \(bind: foreignKey.from)
            """,
            as: String?.self
          )
          .fetchOne(db) ?? nil

        guard let defaultValue
        else {
          // TODO: Report issue?
          continue
        }
        try SQLQueryExpression(
          """
          CREATE TEMPORARY TRIGGER
            "\(raw: .sharingGRDBCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onDeleteSetDefault"
          AFTER DELETE ON \(quote: foreignKey.table)
          FOR EACH ROW BEGIN
            UPDATE \(table)
            SET \(quote: foreignKey.from) = \(raw: defaultValue)
            WHERE \(quote: foreignKey.from) = "old".\(quote: foreignKey.to);
          END
          """
        )
        .execute(db)

      case .setNull:
        try SQLQueryExpression(
          """
          CREATE TEMPORARY TRIGGER
            "\(raw: .sharingGRDBCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onDeleteSetNull"
          AFTER DELETE ON \(quote: foreignKey.table)
          FOR EACH ROW BEGIN
            UPDATE \(table)
            SET \(quote: foreignKey.from) = NULL
            WHERE \(quote: foreignKey.from) = "old".\(quote: foreignKey.to);
          END
          """
        )
        .execute(db)

      case .noAction:
        continue
      }

      switch foreignKey.onUpdate {
      case .cascade:
        try SQLQueryExpression(
          """
          CREATE TEMPORARY TRIGGER
            "\(raw: .sharingGRDBCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onUpdateCascade"
          AFTER UPDATE ON \(quote: foreignKey.table)
          FOR EACH ROW BEGIN
            UPDATE \(T.self)
            SET \(quote: foreignKey.from) = "new".\(quote: foreignKey.to)
            WHERE \(quote: foreignKey.from) = "old".\(quote: foreignKey.to);
          END
          """
        )
        .execute(db)

      case .restrict:
        // TODO: Report issue?
        continue

      case .setDefault:
        let defaultValue =
          try SQLQueryExpression(
            """
            SELECT "dflt_value"
            FROM pragma_table_info(\(bind: T.tableName))
            WHERE "name" = \(bind: foreignKey.from)
            """,
            as: String?.self
          )
          .fetchOne(db) ?? nil

        guard let defaultValue
        else {
          // TODO: Report issue?
          continue
        }
        try SQLQueryExpression(
          """
          CREATE TEMPORARY TRIGGER
            "\(raw: .sharingGRDBCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onUpdateSetDefault"
          AFTER UPDATE ON \(quote: foreignKey.table)
          FOR EACH ROW BEGIN
            UPDATE \(table)
            SET \(quote: foreignKey.from) = \(raw: defaultValue)
            WHERE \(quote: foreignKey.from) = "old".\(quote: foreignKey.to);
          END
          """
        )
        .execute(db)

      case .setNull:
        try SQLQueryExpression(
          """
          CREATE TEMPORARY TRIGGER
            "\(raw: .sharingGRDBCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onUpdateSetNull"
          AFTER UPDATE ON \(quote: foreignKey.table)
          FOR EACH ROW BEGIN
            UPDATE \(T.self)
            SET \(quote: foreignKey.from) = NULL
            WHERE \(quote: foreignKey.from) = "old".\(quote: foreignKey.to);
          END
          """
        )
        .execute(db)

      case .noAction:
        continue
      }
    }
  }

  private func dropTriggers<T: PrimaryKeyedTable>(table: T.Type, db: Database) throws {
    let foreignKeys = foreignKeysByTableName[T.tableName] ?? []
    for foreignKey in foreignKeys {
      switch foreignKey.onDelete {
      case .cascade:
        try SQLQueryExpression(
          """
          DROP TRIGGER
            "\(raw: .sharingGRDBCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onDeleteCascade"
          """
        )
        .execute(db)

      case .restrict:
        continue

      case .setDefault:
        try SQLQueryExpression(
          """
          DROP TRIGGER
            "\(raw: .sharingGRDBCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onDeleteSetDefault"
          """
        )
        .execute(db)

      case .setNull:
        try SQLQueryExpression(
          """
          DROP TRIGGER
            "\(raw: .sharingGRDBCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onDeleteSetNull"
          """
        )
        .execute(db)

      case .noAction:
        continue
      }

      switch foreignKey.onUpdate {
      case .cascade:
        try SQLQueryExpression(
          """
          DROP TRIGGER
            "\(raw: .sharingGRDBCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onUpdateCascade"
          """
        )
        .execute(db)

      case .restrict:
        continue

      case .setDefault:
        try SQLQueryExpression(
          """
          DROP TRIGGER
            "\(raw: .sharingGRDBCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onUpdateSetDefault"
          """
        )
        .execute(db)

      case .setNull:
        try SQLQueryExpression(
          """
          DROP TRIGGER
            "\(raw: .sharingGRDBCloudKitSchemaName)_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onUpdateSetNull"
          """
        )
        .execute(db)

      case .noAction:
        continue
      }
    }
    try SQLQueryExpression(
      """
      DROP TRIGGER "\(raw: .sharingGRDBCloudKitSchemaName)_\(raw: T.tableName)_metadataDeletes"
      """
    )
    .execute(db)
    try SQLQueryExpression(
      """
      DROP TRIGGER "\(raw: .sharingGRDBCloudKitSchemaName)_\(raw: T.tableName)_metadataUpdates"
      """
    )
    .execute(db)
    try SQLQueryExpression(
      """
      DROP TRIGGER "\(raw: .sharingGRDBCloudKitSchemaName)_\(raw: T.tableName)_metadataInserts"
      """
    )
    .execute(db)
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncEngine: CKSyncEngineDelegate {
  public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    logger.log(event)

    switch event {
    case .accountChange(let event):
      handleAccountChange(event)
    case .stateUpdate(let event):
      handleStateUpdate(event)
    case .fetchedDatabaseChanges(let event):
      handleFetchedDatabaseChanges(event)
    case .sentDatabaseChanges:
      break
    case .fetchedRecordZoneChanges(let event):
      handleFetchedRecordZoneChanges(
        modifications: event.modifications.map(\.record),
        deletions: event.deletions.map { ($0.recordID, $0.recordType) }
      )
    case .sentRecordZoneChanges(let event):
      handleSentRecordZoneChanges(event)
    case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges, .willFetchChanges,
      .didFetchChanges, .willSendChanges, .didSendChanges:
      break
    @unknown default:
      break
    }
  }

  public func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext,
    syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    let allChanges = syncEngine.state.pendingRecordZoneChanges.filter(
      context.options.scope.contains
    )
    guard !allChanges.isEmpty
    else { return nil }

    var allChangesByIsDeleted = Dictionary(grouping: allChanges) {
      switch $0 {
      case .deleteRecord: true
      case .saveRecord: false
      @unknown default: false
      }
    }
    allChangesByIsDeleted[true]?.reverse()
    let changes = allChangesByIsDeleted.reduce(into: []) { changes, keyValue in
      changes += keyValue.value
    }

    #if DEBUG
      struct State {
        var missingTables: [CKRecord.ID] = []
        var missingRecords: [CKRecord.ID] = []
        var sentRecords: [CKRecord.ID] = []
      }
      let state = LockIsolated(State())
      defer {
        let state = state.withValue(\.self)
        let missingTables = Dictionary(grouping: state.missingTables, by: \.zoneID.zoneName)
          .reduce(into: [String]()) {
            strings,
            keyValue in strings += ["\(keyValue.key) (\(keyValue.value.count))"]
          }
          .joined(separator: ", ")
        let missingRecords = Dictionary(grouping: state.missingRecords, by: \.zoneID.zoneName)
          .reduce(into: [String]()) {
            strings,
            keyValue in strings += ["\(keyValue.key) (\(keyValue.value.count))"]
          }
          .joined(separator: ", ")
        let sentRecords = Dictionary(grouping: state.sentRecords, by: \.zoneID.zoneName)
          .reduce(into: [String]()) {
            strings,
            keyValue in strings += ["\(keyValue.key) (\(keyValue.value.count))"]
          }
          .joined(separator: ", ")
        logger.debug(
          """
          nextRecordZoneChangeBatch: \(context.reason)
            \(state.missingTables.isEmpty ? "⚪️ No missing tables" : "⚠️ Missing tables: \(missingTables)")
            \(state.missingRecords.isEmpty ? "⚪️ No missing records" : "⚠️ Missing records: \(missingRecords)")
            \(state.sentRecords.isEmpty ? "⚪️ No sent records" : "✅ Sent records: \(sentRecords)")
          """
        )
      }
    #endif

    let batch = await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
      #if DEBUG
        var missingTable: CKRecord.ID?
        var missingRecord: CKRecord.ID?
        var sentRecord: CKRecord.ID?
        defer {
          state.withValue { [missingTable, missingRecord, sentRecord] in
            if let missingTable { $0.missingTables.append(missingTable) }
            if let missingRecord { $0.missingRecords.append(missingRecord) }
            if let sentRecord { $0.sentRecords.append(sentRecord) }
          }
        }
      #endif

      guard let metadata = await metadataFor(recordID: recordID)
      else {
        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
        return nil
      }
      guard let table = tablesByName[metadata.recordType]
      else {
        reportIssue("")
        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
        missingTable = recordID
        return nil
      }
      func open<T: PrimaryKeyedTable>(_: T.Type) async -> CKRecord? {
        let row =
          withErrorReporting {
            try database.read { db in
              try T.find(recordID: recordID).fetchOne(db)
            }
          }
          ?? nil
        guard let row
        else {
          syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
          missingRecord = recordID
          return nil
        }

        let record =
          metadata.lastKnownServerRecord
          ?? CKRecord(
            recordType: metadata.recordType,
            recordID: recordID
          )
        record.parent = metadata.parentRecordName.map { parentRecordName in
          CKRecord.Reference(
            recordID: CKRecord.ID(
              recordName: parentRecordName,
              zoneID: record.recordID.zoneID
            ),
            action: .none
          )
        }
        record.update(
          with: T(queryOutput: row),
          userModificationDate: metadata.userModificationDate
        )
        await refreshLastKnownServerRecord(record)
        sentRecord = recordID
        return record
      }
      return await open(table)
    }
    return batch
  }

  private func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) {
    switch event.changeType {
    case .signIn:
      // TODO: handle this
      //underlyingSyncEngine.state.add(pendingDatabaseChanges: [.saveZone(Self.defaultZone)])
      for table in tables {
        withErrorReporting(.sharingGRDBCloudKitFailure) {
          let names: [String] = try database.read { db in
            func open<T: PrimaryKeyedTable>(_: T.Type) throws -> [String] {
              try T
                .select { SQLQueryExpression("\($0.primaryKey)", as: String.self) }
                .fetchAll(db)
            }
            return try open(table)
          }
          underlyingSyncEngine.state.add(
            pendingRecordZoneChanges: names.map {
              .saveRecord(
                CKRecord.ID(
                  recordName: $0,
                  zoneID: Self.defaultZone.zoneID
                )
              )
            }
          )
        }
      }
    case .signOut, .switchAccounts:
      withErrorReporting(.sharingGRDBCloudKitFailure) {
        try deleteLocalData()
      }
    @unknown default:
      break
    }
  }

  private func handleStateUpdate(_ event: CKSyncEngine.Event.StateUpdate) {
    withErrorReporting(.sharingGRDBCloudKitFailure) {
      try database.write { db in
        try StateSerialization.insert(
          StateSerialization(data: event.stateSerialization)
        )
        .execute(db)
      }
    }
  }

  private func handleFetchedDatabaseChanges(_ event: CKSyncEngine.Event.FetchedDatabaseChanges) {
    // TODO: Come back to this once we have zoneName in the metadata table.
    //    $isUpdatingWithServerRecord.withValue(true) {
    //      withErrorReporting(.sharingGRDBCloudKitFailure) {
    //        try database.write { db in
    //          for deletion in event.deletions {
    //            if let table = tablesByName[deletion.zoneID.zoneName] {
    //              func open<T: PrimaryKeyedTable>(_: T.Type) {
    //                withErrorReporting(.sharingGRDBCloudKitFailure) {
    //                  try T.delete().execute(db)
    //                }
    //              }
    //              open(table)
    //            }
    //          }
    //
    //          // TODO: Deal with modifications?
    //          _ = event.modifications
    //        }
    //      }
    //    }
  }

  package func handleFetchedRecordZoneChanges(
    modifications: [CKRecord],
    deletions: [(CKRecord.ID, CKRecord.RecordType)]
  ) {
    $isUpdatingWithServerRecord.withValue(true) {
      for modifiedRecord in modifications {
        mergeFromServerRecord(modifiedRecord)
        refreshLastKnownServerRecord(modifiedRecord)
      }

      for (recordID, recordType) in deletions {
        if let table = tablesByName[recordType] {
          func open<T: PrimaryKeyedTable>(_: T.Type) {
            withErrorReporting(.sharingGRDBCloudKitFailure) {
              try database.write { db in
                try T.find(recordID: recordID)
                  .delete()
                  .execute(db)
              }
            }
          }
          open(table)
        } else {
          reportIssue(
            .sharingGRDBCloudKitFailure.appending(
              """
              : No table to delete from: "\(recordType)"
              """
            )
          )
        }
      }
    }
  }

  private func handleSentRecordZoneChanges(_ event: CKSyncEngine.Event.SentRecordZoneChanges) {
    for savedRecord in event.savedRecords {
      refreshLastKnownServerRecord(savedRecord)
    }

    var newPendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] = []
    var newPendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] = []
    defer {
      underlyingSyncEngine.state.add(pendingDatabaseChanges: newPendingDatabaseChanges)
      underlyingSyncEngine.state.add(pendingRecordZoneChanges: newPendingRecordZoneChanges)
    }
    for failedRecordSave in event.failedRecordSaves {
      let failedRecord = failedRecordSave.record

      func clearServerRecord() {
        withErrorReporting {
          try $isUpdatingWithServerRecord.withValue(true) {
            try database.write { db in
              try Metadata
                .find(recordID: failedRecord.recordID)
                .update { $0.lastKnownServerRecord = nil }
                .execute(db)
            }
          }
        }
      }

      switch failedRecordSave.error.code {
      case .serverRecordChanged:
        guard let serverRecord = failedRecordSave.error.serverRecord else { continue }
        mergeFromServerRecord(serverRecord)
        refreshLastKnownServerRecord(serverRecord)
        newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))

      case .zoneNotFound:
        let zone = CKRecordZone(zoneID: failedRecord.recordID.zoneID)
        // TODO: handle this
        //newPendingDatabaseChanges.append(.saveZone(zone))
        newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
        clearServerRecord()

      case .unknownItem:
        newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
        clearServerRecord()

      case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated,
        .operationCancelled, .batchRequestFailed:
        continue

      default:
        continue
      }
    }
    // TODO: handle event.failedRecordDeletes ? look at apple sample code
  }

  private func mergeFromServerRecord(_ record: CKRecord) {
    $isUpdatingWithServerRecord.withValue(true) {
      $currentZoneID.withValue(record.recordID.zoneID) {
        withErrorReporting(.sharingGRDBCloudKitFailure) {
          let userModificationDate =
            try metadatabase.read { db in
              try Metadata.find(recordID: record.recordID).select(\.userModificationDate).fetchOne(
                db
              )
            }
            ?? nil
          guard let table = tablesByName[record.recordType]
          else {
            reportIssue(
              .sharingGRDBCloudKitFailure.appending(
                """
                : No table to merge from: "\(record.recordType)"
                """
              )
            )
            return
          }
          guard
            let userModificationDate,
            userModificationDate > record.userModificationDate ?? .distantPast
          else {
            let columnNames = try database.read { db in
              try SQLQueryExpression(
                """
                SELECT "name" 
                FROM pragma_table_info(\(bind: table.tableName))    
                """,
                as: String.self
              )
              .fetchAll(db)
            }
            var query: QueryFragment = "INSERT INTO \(table) ("
            query.append(columnNames.map { "\(quote: $0)" }.joined(separator: ", "))
            query.append(") VALUES (")
            let encryptedValues = record.encryptedValues
            query.append(
              columnNames
                .map { columnName in
                  encryptedValues[columnName]?.queryFragment ?? "NULL"
                }
                .joined(separator: ", ")
            )
            func open<T: PrimaryKeyedTable>(_: T.Type) {
              query.append(") ON CONFLICT(\(quote: T.columns.primaryKey.name)) DO UPDATE SET")
            }
            open(table)
            query.append(
              columnNames
                .map {
                  """
                  \(quote: $0) = "excluded".\(quote: $0)
                  """
                }
                .joined(separator: ",")
            )
            try database.write { db in
              try SQLQueryExpression(query).execute(db)
              try Metadata
                .insert(Metadata(record: record)) {
                  $0.lastKnownServerRecord = record
                  $0.userModificationDate = record.userModificationDate
                }
                .execute(db)
            }
            return
          }
        }
      }
    }
  }

  private func refreshLastKnownServerRecord(_ record: CKRecord) {
    $currentZoneID.withValue(record.recordID.zoneID) {
      $isUpdatingWithServerRecord.withValue(true) {
        let metadata = metadataFor(recordID: record.recordID)

        func updateLastKnownServerRecord() {
          withErrorReporting(.sharingGRDBCloudKitFailure) {
            try database.write { db in
              try Metadata
                .find(recordID: record.recordID)
                .update { $0.lastKnownServerRecord = record }
                .execute(db)
            }
          }
        }

        if let lastKnownDate = metadata?.lastKnownServerRecord?.modificationDate {
          if let recordDate = record.modificationDate, lastKnownDate < recordDate {
            updateLastKnownServerRecord()
          }
        } else {
          updateLastKnownServerRecord()
        }
      }
    }
  }

  private func metadataFor(recordID: CKRecord.ID) -> Metadata? {
    withErrorReporting(.sharingGRDBCloudKitFailure) {
      try metadatabase.read { db in
        try Metadata.find(recordID: recordID).fetchOne(db)
      }
    }
      ?? nil
  }
}

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
extension DatabaseFunction {
  fileprivate static func didUpdate(syncEngine: SyncEngine) -> Self {
    Self("didUpdate") { recordName, zoneName, ownerName in
      await syncEngine
        .didUpdate(
          recordName: recordName,
          zoneName: zoneName,
          ownerName: ownerName
        )
    }
  }

  fileprivate static func willDelete(syncEngine: SyncEngine) -> Self {
    return Self("willDelete") { recordName, zoneName, ownerName in
      await syncEngine.willDelete(
        recordName: recordName,
        zoneName: zoneName,
        ownerName: ownerName
      )
    }
  }

  fileprivate static var isUpdatingWithServerRecord: Self {
    Self(.sharingGRDBCloudKitSchemaName + "_" + "isUpdatingWithServerRecord", argumentCount: 0) {
      _ in
      SharingGRDBCore.isUpdatingWithServerRecord
    }
  }

  fileprivate static var getZoneName: Self {
    Self(.sharingGRDBCloudKitSchemaName + "_" + "getZoneName", argumentCount: 0) { _ in
      SharingGRDBCore.currentZoneID?.zoneName
    }
  }

  fileprivate static var getOwnerName: Self {
    Self(.sharingGRDBCloudKitSchemaName + "_" + "getOwnerName", argumentCount: 0) { _ in
      SharingGRDBCore.currentZoneID?.ownerName
    }
  }

  private convenience init(
    _ name: String,
    function: @escaping @Sendable (String, String, String) async -> Void
  ) {
    self.init(.sharingGRDBCloudKitSchemaName + "_" + name, argumentCount: 3) { arguments in
      guard
        let recordName = String.fromDatabaseValue(arguments[0]),
        let zoneName = String.fromDatabaseValue(arguments[1]),
        let ownerName = String.fromDatabaseValue(arguments[2])
      else {
        return nil
      }
      // TODO: can we get rid of task by making stuff in actor non-isolated?
      Task { await function(recordName, zoneName, ownerName) }
      return nil
    }
  }
}

// TODO: Rename to isUpdatingFromServer / isHandlingServerUpdates
@TaskLocal private var isUpdatingWithServerRecord = false
@TaskLocal private var currentZoneID: CKRecordZone.ID?

extension String {
  package static let sharingGRDBCloudKitSchemaName = "sqlitedata_icloud"
  fileprivate static let sharingGRDBCloudKitFailure = "SharingGRDB CloudKit Failure"
}

@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
extension URL {
  fileprivate static func metadatabase(container: CKContainer) -> Self {
    applicationSupportDirectory.appending(
      component: "\(container.containerIdentifier.map { "\($0)." } ?? "")sqlite-data-icloud.sqlite"
    )
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncEngine {
  public func share<T: PrimaryKeyedTable>(
    record: T,
    configure: @Sendable (CKShare) -> Void
  ) async throws -> CKShare
  where T.TableColumns.PrimaryKey == UUID {
    let recordName = record[keyPath: T.columns.primaryKey.keyPath].uuidString.lowercased()
    let lastKnownServerRecord =
      try await database.write { db in
        try Metadata
          .find(recordID: CKRecord.ID(recordName: recordName))
          .select(\.lastKnownServerRecord)
          .fetchOne(db)
      } ?? nil

    guard let lastKnownServerRecord
    else {
      throw NoCKRecordFound()
    }

    let shareID = CKRecord.ID(
      recordName: UUID().uuidString,
      zoneID: lastKnownServerRecord.recordID.zoneID
    )
    let share = CKShare(rootRecord: lastKnownServerRecord, shareID: shareID)
    configure(share)

    let modifyOperation = CKModifyRecordsOperation(
      recordsToSave: [share, lastKnownServerRecord],
      recordIDsToDelete: nil
    )
    try await withUnsafeThrowingContinuation {
      (continuation: UnsafeContinuation<Void, any Error>) in
      modifyOperation.modifyRecordsCompletionBlock = { records, recordIDs, error in
        if let error = error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }

      modifyOperation.database = container.sharedCloudDatabase
      // TODO: can this be container.add?
      operationQueue.addOperation(modifyOperation)
    }

    return share
  }
}

struct NoCKRecordFound: Error {}

#if canImport(UIKit)
  import UIKit
  extension UICloudSharingController {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    public convenience init<T: PrimaryKeyedTable>(_ record: T)
    where T.TableColumns.PrimaryKey == UUID {
      // TODO: Remove UUID constraint by reaching into metadata table
      // TODO: verify that table has no foreign keys
      @Dependency(\.defaultSyncEngine) var syncEngine
      let record = try! syncEngine.database.write { db in
        return
          try Metadata
          .find(
            recordID: CKRecord.ID.init(
              recordName: record[keyPath: T.columns.primaryKey.keyPath].uuidString.lowercased()
            )
          )
          .select(\.lastKnownServerRecord)
          .fetchOne(db)
      }
      self.init(
        share: CKShare(rootRecord: record!!),
        container: syncEngine.container
      )
    }
  }

  import SwiftUI

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public struct CloudSharingView<T: PrimaryKeyedTable>: UIViewControllerRepresentable
  where T.TableColumns.PrimaryKey == UUID {
    let record: T
    public init(_ record: T) {
      self.record = record
    }

    public func makeUIViewController(context: Context) -> UICloudSharingController {
      UICloudSharingController(record)
    }

    public func updateUIViewController(
      _ uiViewController: UICloudSharingController,
      context: Context
    ) {
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public struct CloudSharingView2: UIViewControllerRepresentable {
    let share: CKShare
    public init(share: CKShare) {
      self.share = share
    }

    public func makeUIViewController(context: Context) -> UICloudSharingController {
      @Dependency(\.defaultSyncEngine) var syncEngine
      return UICloudSharingController.init(share: share, container: syncEngine.container)
    }

    public func updateUIViewController(
      _ uiViewController: UICloudSharingController,
      context: Context
    ) {
    }
  }
#endif

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncEngine {
  public nonisolated func userDidAcceptCloudKitShare(with metadata: CKShare.Metadata) {
    let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
    operation.perShareResultBlock = { metadata, result in
      print(metadata.hierarchicalRootRecordID)
    }
    operation.acceptSharesResultBlock = { [weak self] result in
      guard let self else { return }
      Task {
        await withErrorReporting {
          try await self.underlyingSyncEngine
            .fetchChanges(
              .init(
                scope: .zoneIDs([metadata.hierarchicalRootRecordID!.zoneID]),
                operationGroup: nil
              )
            )
        }
      }
    }

    let metadataFetchOperation = CKFetchShareMetadataOperation(shareURLs: [metadata.share.url!])
    metadataFetchOperation.shouldFetchRootRecord = true
    metadataFetchOperation.perShareMetadataResultBlock = { url, result in
      //print("!!!")
    }
    container.add(metadataFetchOperation)

    //operationQueue.addOperation(operation)
    operation.qualityOfService = .utility
    container.add(operation)
  }
}
