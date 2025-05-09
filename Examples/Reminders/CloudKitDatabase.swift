import CloudKit
import Dependencies
import SharingGRDB

extension DependencyValues {
  var cloudKitDatabase: CloudKitDatabase {
    get {
      self[CloudKitDatabase.self]
    }
    set {
      self[CloudKitDatabase.self] = newValue
    }
  }
}
extension CloudKitDatabase: TestDependencyKey {
  static var testValue: CloudKitDatabase {
    if shouldReportUnimplemented {
      reportIssue("TODO")
    }
    return CloudKitDatabase(
      container: CKContainer(identifier: "default"),
      tables: []
    )
  }
}

actor CloudKitDatabase {
  @Dependency(\.defaultDatabase) var database

  let container: CKContainer
  var syncEngine: CKSyncEngine!
  var stateSerialization: CKSyncEngine.State.Serialization?
  let tables: [any StructuredQueries.Table.Type]
  var delegate: Delegate

  init(
    container: CKContainer,
    tables: [any StructuredQueries.Table.Type]
  ) {
    self.container = container
    self.delegate = Delegate(container: container)
    self.tables = tables
    let stateSerializationData =
      UserDefaults.standard.data(
        forKey: stateSerializationKey(containerIdentifier: container.containerIdentifier)
      ) ?? Data()
    stateSerialization = try? JSONDecoder().decode(
      CKSyncEngine.State.Serialization.self,
      from: stateSerializationData
    )
    let configuration = CKSyncEngine.Configuration(
      database: container.privateCloudDatabase,
      stateSerialization: stateSerialization,
      delegate: delegate
    )
    syncEngine = CKSyncEngine(configuration)
    delegate.syncEngine = syncEngine
    Task {
      await saveZones()
    }
  }

  deinit {
    print("?!?!?!")
  }

  func restartSyncEngine() {
    UserDefaults.standard.removeObject(
      forKey: stateSerializationKey(containerIdentifier: container.containerIdentifier)
    )
    stateSerialization = nil
    self.delegate = Delegate(container: container)
    let configuration = CKSyncEngine.Configuration(
      database: container.privateCloudDatabase,
      stateSerialization: stateSerialization,
      delegate: delegate
    )
    syncEngine = CKSyncEngine(configuration)
    delegate.syncEngine = syncEngine
    saveZones()
  }

  func saveZones() {
    syncEngine.state.add(
      pendingDatabaseChanges: tables.map {
        .saveZone(CKRecordZone(zoneName: $0.tableName))
      }
    )
  }

  func didInsert(tableName: String, id: String) {
    syncEngine.state.add(
      pendingRecordZoneChanges: [
        .saveRecord(
          CKRecord.ID(
            recordName: id,
            zoneID: CKRecordZone(zoneName: tableName).zoneID
          )
        )
      ]
    )
  }

  func didUpdate(tableName: String, id: String) {
    // TODO: perform modification date checks
    syncEngine.state.add(
      pendingRecordZoneChanges: [
        .saveRecord(
          CKRecord.ID(
            recordName: id,
            zoneID: CKRecordZone(zoneName: tableName).zoneID
          )
        )
      ]
    )
  }

  func willDelete(tableName: String, id: String) {
    syncEngine.state.add(
      pendingRecordZoneChanges: [
        .deleteRecord(
          CKRecord.ID(
            recordName: id,
            zoneID: CKRecordZone(zoneName: tableName).zoneID
          )
        )
      ]
    )
  }

  #if DEBUG
    func deleteAllRecords() async throws {
      syncEngine.state.add(
        pendingDatabaseChanges: tables.map { table in
          .deleteZone(CKRecordZone.ID(zoneName: table.tableName))
        }
      )
      try await syncEngine.sendChanges()
    }
  #endif
}

final class Delegate: CKSyncEngineDelegate, @unchecked Sendable {
  @Dependency(\.defaultDatabase) var database
  let container: CKContainer
  var syncEngine: CKSyncEngine!
  init(container: CKContainer) {
    self.container = container
  }

  func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    logger.info("CloudKitDatabase.Delegate.handleEvent.\(event)")
    switch event {
    case .stateUpdate(let stateUpdate):
      withErrorReporting {
        UserDefaults.standard.set(
          try JSONEncoder().encode(stateUpdate.stateSerialization),
          forKey: stateSerializationKey(containerIdentifier: container.containerIdentifier)
        )
      }
      break
    case .accountChange(_):
      // TODO
      break
    case .fetchedDatabaseChanges(let changes):
      handleFetchedDatabaseChanges(changes)
      break
    case .fetchedRecordZoneChanges(let changes):
      handleFetchedRecordZoneChanges(changes)
      break
    case .sentDatabaseChanges(_):
      // TODO
      break
    case .sentRecordZoneChanges(let changes):
      handleSentRecordZoneChanges(changes)
      break
    case .willFetchChanges(_):
      // TODO
      break
    case .willFetchRecordZoneChanges(_):
      // TODO
      break
    case .didFetchRecordZoneChanges(_):
      // TODO
      break
    case .didFetchChanges(_):
      // TODO
      break
    case .willSendChanges(_):
      // TODO
      break
    case .didSendChanges(_):
      // TODO
      break
    @unknown default:
      // TODO
      break
    }
  }

  private func handleSentRecordZoneChanges(_ changes: CKSyncEngine.Event.SentRecordZoneChanges) {
    var newPendingRecordZoneChanges = [CKSyncEngine.PendingRecordZoneChange]()
    var newPendingDatabaseChanges = [CKSyncEngine.PendingDatabaseChange]()
    defer {
      syncEngine.state.add(pendingDatabaseChanges: newPendingDatabaseChanges)
      syncEngine.state.add(pendingRecordZoneChanges: newPendingRecordZoneChanges)
    }

    withErrorReporting {
      try database.write { db in
        for savedRecord in changes.savedRecords {
          try db.cacheNewRecordIfNewer(savedRecord)
        }

        for failedRecordSave in changes.failedRecordSaves {
          // TODO: do this
          switch failedRecordSave.error.code {
            //      case .internalError:
            //        <#code#>
            //      case .partialFailure:
            //        <#code#>
            //      case .networkUnavailable:
            //        <#code#>
            //      case .networkFailure:
            //        <#code#>
            //      case .badContainer:
            //        <#code#>
            //      case .serviceUnavailable:
            //        <#code#>
            //      case .requestRateLimited:
            //        <#code#>
            //      case .missingEntitlement:
            //        <#code#>
            //      case .notAuthenticated:
            //        <#code#>
            //      case .permissionFailure:
            //        <#code#>
          case .unknownItem:
            print("")
            //      case .invalidArguments:
            //        <#code#>
            //      case .resultsTruncated:
            //        <#code#>
          case .serverRecordChanged:
            guard let serverRecord = failedRecordSave.error.serverRecord
            else { continue }
            try db.cacheNewRecordIfNewer(serverRecord)
            try serverRecord.upsertIfNewer(db: db)
            print(
              serverRecord.recordID,
              failedRecordSave.record.recordID,
              serverRecord.recordID == failedRecordSave.record.recordID
            )
            newPendingRecordZoneChanges.append(.saveRecord(failedRecordSave.record.recordID))
            //      case .serverRejectedRequest:
            //        <#code#>
            //      case .assetFileNotFound:
            //        <#code#>
            //      case .assetFileModified:
            //        <#code#>
            //      case .incompatibleVersion:
            //        <#code#>
            //      case .constraintViolation:
            //        <#code#>
            //      case .operationCancelled:
            //        <#code#>
            //      case .changeTokenExpired:
            //        <#code#>
            //      case .batchRequestFailed:
            //        <#code#>
            //      case .zoneBusy:
            //        <#code#>
            //      case .badDatabase:
            //        <#code#>
            //      case .quotaExceeded:
            //        <#code#>
          case .zoneNotFound:
            // TODO: recreate zone if it matches a table name?
            let zone = CKRecordZone(zoneID: failedRecordSave.record.recordID.zoneID)
            newPendingDatabaseChanges.append(.saveZone(zone))
            newPendingRecordZoneChanges.append(.saveRecord(failedRecordSave.record.recordID))

            //      case .limitExceeded:
            //        <#code#>
            //      case .userDeletedZone:
            //        <#code#>
            //      case .tooManyParticipants:
            //        <#code#>
            //      case .alreadyShared:
            //        <#code#>
            //      case .referenceViolation:
            //        <#code#>
            //      case .managedAccountRestricted:
            //        <#code#>
            //      case .participantMayNeedVerification:
            //        <#code#>
            //      case .serverResponseLost:
            //        <#code#>
            //      case .assetNotAvailable:
            //        <#code#>
            //      case .accountTemporarilyUnavailable:
            //        <#code#>

          case .networkFailure,
              .networkUnavailable,
              .zoneBusy,
              .serviceUnavailable,
              .notAuthenticated,
              .operationCancelled:
            print("")
          default:
            reportIssue("Unhandled error: \(failedRecordSave.error.code)")
          }
        }

        for (recordID, failedRecordDelete) in changes.failedRecordDeletes {
          // TODO: do this
          print(failedRecordDelete)
        }

        // TODO: double check this is correct. the sample code doesn't have this
        for deletedRecordID in changes.deletedRecordIDs {
          try deletedRecordID.delete(db: db)
        }
      }
    }
  }

  private func handleFetchedRecordZoneChanges(
    _ changes: CKSyncEngine.Event.FetchedRecordZoneChanges
  ) {
    withErrorReporting {
      try database.write { db in
        for modification in changes.modifications {
          try modification.record.upsertIfNewer(db: db)
          try db.cacheNewRecordIfNewer(modification.record)
        }

        for deletion in changes.deletions {
          try deletion.recordID.delete(db: db)
        }
      }
    }
  }

  private func handleFetchedDatabaseChanges(_ changes: CKSyncEngine.Event.FetchedDatabaseChanges) {
    withErrorReporting {
      try database.write { db in
        for deletion in changes.deletions {
          let tableName = deletion.zoneID.zoneName
          try #sql(
            """
            DELETE FROM "\(raw: tableName)"
            """
          )
          .execute(db)

          syncEngine.state.add(
            pendingDatabaseChanges: [
              .saveZone(CKRecordZone(zoneName: tableName))
            ]
          )
        }
      }
    }
  }

  func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext,
    syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    logger.info("CloudKitDatabase.Delegate.nextRecordZoneChangeBatch \(context)")

    let changes = syncEngine.state.pendingRecordZoneChanges.filter(context.options.scope.contains)
    let batch = await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
      do {
        return try database.write { db in
          let record = try db.fetchLastCachedRecord(id: recordID)
          let row = try Row.fetchOne(
            db,
            SQLRequest(
              sql: """
                SELECT * FROM "\(recordID.tableName)" WHERE "id" = ?
                """,
              arguments: [recordID.primaryKey]
            )
          )

          guard let row
          else {
            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return nil
          }
          record.update(with: row)
          try db.cacheNewRecordIfNewer(record)
          return record
        }
      } catch {
        reportIssue(error)
        return nil
      }
    }
    return batch
  }
}

extension CKRecord {
  func update(with row: Row) {
    for columnName in row.columnNames {
      switch row[columnName]?.databaseValue.storage {
      case .null:
        if encryptedValues[columnName] != nil {
          encryptedValues[columnName] = nil
        }
      case .int64(let value):
        if object(forKey: columnName) as? Int64 != value {
          encryptedValues[columnName] = value
        }
      case .double(let value):
        if object(forKey: columnName) as? Double != value {
          encryptedValues[columnName] = value
        }
      case .string(let value):
        if object(forKey: columnName) as? String != value {
          encryptedValues[columnName] = value
        }
      case .blob(let value):
        if object(forKey: columnName) as? Data != value {
          encryptedValues[columnName] = value
        }
      case .none:
        break
      }
    }
  }
}

extension CKRecord.ID {
  fileprivate var primaryKey: String { recordName }
  fileprivate var tableName: String { zoneID.zoneName }
}

private func stateSerializationKey(containerIdentifier: String?) -> String {
  (containerIdentifier ?? "") + ".stateSerializationData"
}

extension Database {
  func cacheNewRecordIfNewer(_ newRecord: CKRecord) throws {
    let existingRecord = try fetchLastCachedRecord(id: newRecord.recordID)
    if let existingRecordModificationDate = existingRecord.modificationDate {
      if let newRecordModificationDate = newRecord.modificationDate,
        existingRecordModificationDate < newRecordModificationDate
      {
        try update()
      } else {
        print("Modification date caught")
      }
    } else {
      try update()
    }

    func update() throws {
      let archiver = NSKeyedArchiver(requiringSecureCoding: true)
      newRecord.encodeSystemFields(with: archiver)
      // TODO: should we use userModificationDate based on record.modificationDate?
      try #sql(
        """
        INSERT INTO "sharing_grdb_cloudkit"
        ("tableName", "primaryKey", "recordData", "userModificationDate")
        VALUES (
          \(bind: newRecord.recordID.tableName),
          \(bind: newRecord.recordID.primaryKey),
          \(archiver.encodedData),
          \(bind: Date.ISO8601Representation(queryOutput: newRecord.modificationDate ?? Date()))
        )
        ON CONFLICT("tableName", "primaryKey") DO UPDATE SET
        "recordData" = \(archiver.encodedData)
        """
      )
      .execute(self)
    }
  }

  func fetchLastCachedRecord(id recordID: CKRecord.ID) throws -> CKRecord {
    return try #sql(
      """
      SELECT "recordData"
      FROM "sharing_grdb_cloudkit"
      WHERE "tableName" = \(bind: recordID.tableName)
      AND "primaryKey" = \(bind: recordID.primaryKey)
      """,
      as: Data?.self
    )
    .fetchOne(self)
    .flatMap { $0 }
    .flatMap { data in
      let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
      unarchiver.requiresSecureCoding = true
      return CKRecord(coder: unarchiver)
    }
      ?? CKRecord(recordType: recordID.tableName, recordID: recordID)
  }
}

extension CKRecord {
  func upsertIfNewer(db: Database) throws {
    let userModificationDate =
      try #sql(
        """
        SELECT "userModificationDate" FROM "sharing_grdb_cloudkit"
        WHERE "tableName" = \(bind: recordID.tableName)
        AND "primaryKey" = \(bind: recordID.primaryKey)
        """,
        as: Date?.ISO8601Representation.self
      )
      .fetchOne(db)
      ?? nil

    if let userModificationDate,
      userModificationDate > (modificationDate ?? .distantPast)
    {
      print("Modification date caught")
    } else {
      // TODO: can we use record.keysChanged to update only columns that changed?
      let columnNames = try String.fetchAll(
        db,
        sql: """
          SELECT "name" 
          FROM pragma_table_info('\(recordID.tableName)')
          """
      )
      var query: QueryFragment = """
        INSERT INTO "\(raw: recordID.tableName)" (
        """
      query.append(columnNames.map { "\(quote: $0)" }.joined(separator: ","))
      query.append(
        """
        ) VALUES (
        """
      )
      query.append(
        columnNames.map { columnName in
          "\(bind: convert(encryptedValues[columnName]))"
        }.joined(separator: ",")
      )
      query.append(
        """
        ) ON CONFLICT("id") DO UPDATE SET
        """
      )
      query.append(
        columnNames
          .map { " \(quote: $0) = excluded.\(quote: $0)" }
          .joined(separator: ",")
      )
      try SQLQueryExpression(query).execute(db)
    }
  }
}

extension CKRecord.ID {
  func delete(db: Database) throws {
    try #sql(
      """
      DELETE FROM "\(raw: tableName)" 
      WHERE "id" = \(bind: primaryKey)
      """
    )
    .execute(db)
  }
}

extension CKRecordZone.ID {
  func deleteAll(db: Database) throws {
    try #sql(
      """
      DELETE FROM "\(raw: zoneName)"
      """
    )
    .execute(db)
  }
}

private func convert(_ value: (any __CKRecordObjCValue)?) -> any QueryExpression {
  guard let value else {
    // TODO: better way?
    return SQLQueryExpression("NULL", as: Void?.self)
  }
  if let value = value as? Int64 {
    return value
  } else if let value = value as? Double {
    return value
  } else if let value = value as? String {
    return value
  } else if let value = value as? Data {
    return value
  } else {
    fatalError("TODO: do we need to do all numeric types?")
  }
}

extension Database {
  // TODO: Can this be done automatically by looking at the schema of the tables?
  func installForeignKeyTrigger<Child: PrimaryKeyedTable, Parent: StructuredQueries.Table>(
    _ childTable: Child.Type,
    belongsTo: Parent.Type,
    through foreignKey: TableColumn<Parent, Child.TableColumns.PrimaryKey>
  ) throws {
    try #sql(
      """
      CREATE TEMP TRIGGER "foreign_key_\(raw: Child.tableName)_belongsTo_\(raw: Parent.tableName)" 
      AFTER DELETE ON \(Child.self)
      FOR EACH ROW BEGIN
        DELETE FROM \(Parent.self)
        WHERE \(foreignKey) = old.\(raw: Child.columns.primaryKey.name);
      END
      """
    )
    .execute(self)
  }
}

extension DatabaseFunction {
  convenience init(name: String, function: @escaping @Sendable (String, String) async -> Void) {
    self.init(name, argumentCount: 2) { arguments in
      guard
        let tableName = String.fromDatabaseValue(arguments[0]),
        let id = String.fromDatabaseValue(arguments[1])
      else {
        return 0
      }
      Task { await function(tableName, id) }
      return 0
    }
  }
}

extension Database {
  func setUpCloudKit(
    containerIdentifier: String,
    tables: [any StructuredQueries.Table.Type]
  ) throws {
    @Dependency(\.context) var context
    guard context == .live else { return }

    let cloudKitDatabase = CloudKitDatabase(
      container: CKContainer(
        identifier: "iCloud.co.pointfree.sharing-grdb.Reminders"
      ),
      tables: [
        Reminder.self,
        RemindersList.self,
        Tag.self,
        ReminderTag.self,
      ]
    )
    prepareDependencies {
      $0.cloudKitDatabase = cloudKitDatabase
    }

    try? FileManager.default
      .createDirectory(
        at: URL.applicationSupportDirectory,
        withIntermediateDirectories: false
      )
    let url = URL.applicationSupportDirectory.appending(component: "sharing-grdb-cloudkit.sqlite")
    logger.info("open \(url.absoluteString)")
    let database = try DatabasePool(path: url.absoluteString)
    var migrator = DatabaseMigrator()
    migrator.registerMigration("Create SharingGRDB tables") { db in
      try #sql(
        """
        CREATE TABLE "sharing_grdb_cloudkit" (
          "tableName" TEXT NOT NULL,
          "primaryKey" TEXT NOT NULL,
          "recordData" BLOB,
          "userModificationDate" TEXT,
          PRIMARY KEY("tableName", "primaryKey")
        )
        """
      )
      .execute(db)
    }
    try migrator.migrate(database)
    try execute(
      literal: """
        ATTACH DATABASE \(url.absoluteString) AS "sharing_grdb_cloudkit_db"
        """
    )
    try execute(
      literal: """
          SELECT * FROM "sharing_grdb_cloudkit"
        """
    )
    try installTriggers(db: self, cloudKitDatabase: cloudKitDatabase)
    // TODO: look at schema to create triggers for foreign key cascading
  }
}

func installTriggers(
  db: Database,
  cloudKitDatabase: CloudKitDatabase
) throws {
  db.add(
    function: DatabaseFunction(
      name: "didInsert",
      function: { await cloudKitDatabase.didInsert(tableName: $0, id: $1) }
    )
  )
  db.add(
    function: DatabaseFunction(
      name: "didUpdate",
      function: { await cloudKitDatabase.didUpdate(tableName: $0, id: $1) }
    )
  )
  db.add(
    function: DatabaseFunction(
      name: "willDelete",
      function: { await cloudKitDatabase.willDelete(tableName: $0, id: $1) }
    )
  )
  db.add(
    function: DatabaseFunction(
      "currentDate",
      argumentCount: 0,
      function: { _ in
        Date()
      }
    )
  )
  for table in cloudKitDatabase.tables {
    try Trigger.delete(tableName: table.tableName).sql
      .execute(db)
    try Trigger.insert(tableName: table.tableName).sql
      .execute(db)
    try Trigger.update(tableName: table.tableName).sql
      .execute(db)
    try #sql(
      """
      CREATE TEMP TRIGGER "sharing_grdb_cloudkit_\(raw: table.tableName)_userModificationDate" 
      AFTER UPDATE ON \(table) FOR EACH ROW BEGIN
        INSERT INTO "sharing_grdb_cloudkit"
        ("tableName", "primaryKey", "userModificationDate")
        VALUES 
        (
          '\(raw: table.tableName)',
          new."id",
          currentDate()
        )
        ON CONFLICT("tableName", "primaryKey") DO UPDATE SET
        "userModificationDate" = excluded."userModificationDate";
      END
      """
    )
    .execute(db)
  }
}

struct Trigger {
  let idColumn: String
  let function: String
  let tableName: String
  let type: String
  let when: String
  static func delete(tableName: String) -> Self {
    Trigger(
      idColumn: "old.id",
      function: "willDelete",
      tableName: tableName,
      type: "DELETE",
      when: "BEFORE"
    )
  }
  static func insert(tableName: String) -> Self {
    Trigger(
      idColumn: "new.id",
      function: "didInsert",
      tableName: tableName,
      type: "INSERT",
      when: "AFTER"
    )
  }
  static func update(tableName: String) -> Self {
    Trigger(
      idColumn: "new.id",
      function: "didUpdate",
      tableName: tableName,
      type: "UPDATE",
      when: "AFTER"
    )
  }
  var sql: SQLQueryExpression<Void> {
    #sql(
      """
      CREATE TEMP TRIGGER "sharing_grdb_cloudkit_\(raw: type.lowercased())_\(raw: tableName)"
      \(raw: when) \(raw: type) ON "\(raw: tableName)" FOR EACH ROW BEGIN
        SELECT \(raw: function)('\(raw: tableName)', \(raw: idColumn));
      END
      """
    )
  }
}
