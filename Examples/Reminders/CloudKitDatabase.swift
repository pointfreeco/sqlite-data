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
    return CloudKitDatabase(container: CKContainer(identifier: "default"))
  }
}

// TODO: fix sendable by either making actor or locking mutable state
class CloudKitDatabase: @unchecked Sendable {
  let container: CKContainer
  let syncEngine: CKSyncEngine
  var stateSerialization: CKSyncEngine.State.Serialization?
  let delegate: Delegate

  init(container: CKContainer) {
    self.container = container
    self.delegate = Delegate(container: container)
    let stateSerializationData =
      UserDefaults.standard.data(
        forKey: stateSerializationKey(containerIdentifier: container.containerIdentifier)
      ) ?? Data()
    stateSerialization = try? JSONDecoder()
      .decode(
        CKSyncEngine.State.Serialization.self,
        from: stateSerializationData
      )
    let configuration = CKSyncEngine.Configuration(
      database: container.privateCloudDatabase,
      stateSerialization: stateSerialization,
      delegate: delegate
    )
    syncEngine = CKSyncEngine(configuration)
  }

  func saveZones(tableNames: [String]) {
    syncEngine.state.add(
      pendingDatabaseChanges: tableNames.map {
        .saveZone(CKRecordZone(zoneName: $0))
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
}

final class Delegate: CKSyncEngineDelegate, @unchecked Sendable {
  @Dependency(\.defaultDatabase) var database
  let container: CKContainer
  init(container: CKContainer) {
    self.container = container
  }

  func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    logger.info("CloudKitDatabase.Delegate.handleEvent.\(event)")
    switch event {
    case .stateUpdate(let stateUpdate):
      UserDefaults.standard.set(
        try? JSONEncoder().encode(stateUpdate.stateSerialization),
        forKey: stateSerializationKey(containerIdentifier: container.containerIdentifier)
      )
      // TODO
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

    for savedRecord in changes.savedRecords {
      // TODO: do this
    }

    for failedRecordSave in changes.failedRecordSaves {
      // TODO: do this
      //      switch failedRecordSave.error.code  {
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
      //      case .unknownItem:
      //        <#code#>
      //      case .invalidArguments:
      //        <#code#>
      //      case .resultsTruncated:
      //        <#code#>
      //      case .serverRecordChanged:
      //        <#code#>
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
      //      case .zoneNotFound:
      //        <#code#>
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
      //      @unknown default:
      //        <#fatalError()#>
      //      }
    }

    for failedRecordDelete in changes.failedRecordDeletes {
      // TODO: do this
    }

    withErrorReporting {
      // TODO: double check this is correct. the sample code doesn't have this
      try database.write { db in
        for deletedRecordID in changes.deletedRecordIDs {
          try deletedRecordID.delete(db: db)
        }
      }
    }

    //    // If we failed to save a record, we might want to retry depending on the error code.
    //    var newPendingRecordZoneChanges = [CKSyncEngine.PendingRecordZoneChange]()
    //    var newPendingDatabaseChanges = [CKSyncEngine.PendingDatabaseChange]()
    //
    //    // Update the last known server record for each of the saved records.
    //    for savedRecord in event.savedRecords {
    //
    //      let id = savedRecord.recordID.recordName
    //      if var contact = self.appData.contacts[id] {
    //        contact.setLastKnownRecordIfNewer(savedRecord)
    //        self.appData.contacts[id] = contact
    //      }
    //    }
    //
    //    // Handle any failed record saves.
    //    for failedRecordSave in event.failedRecordSaves {
    //      let failedRecord = failedRecordSave.record
    //      let contactID = failedRecord.recordID.recordName
    //      var shouldClearServerRecord = false
    //
    //      switch failedRecordSave.error.code {
    //
    //      case .serverRecordChanged:
    //        // Let's merge the record from the server into our own local copy.
    //        // The `mergeFromServerRecord` function takes care of the conflict resolution.
    //        guard let serverRecord = failedRecordSave.error.serverRecord else {
    //          Logger.database.error("No server record for conflict \(failedRecordSave.error)")
    //          continue
    //        }
    //        guard var contact = self.appData.contacts[contactID] else {
    //          Logger.database.error("No local object for conflict \(failedRecordSave.error)")
    //          continue
    //        }
    //        contact.mergeFromServerRecord(serverRecord)
    //        contact.setLastKnownRecordIfNewer(serverRecord)
    //        self.appData.contacts[contactID] = contact
    //        newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
    //
    //      case .zoneNotFound:
    //        // Looks like we tried to save a record in a zone that doesn't exist.
    //        // Let's save that zone and retry saving the record.
    //        // Also clear the last known server record if we have one, it's no longer valid.
    //        let zone = CKRecordZone(zoneID: failedRecord.recordID.zoneID)
    //        newPendingDatabaseChanges.append(.saveZone(zone))
    //        newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
    //        shouldClearServerRecord = true
    //
    //      case .unknownItem:
    //        // We tried to save a record with a locally-cached server record, but that record no longer exists on the server.
    //        // This might mean that another device deleted the record, but we still have the data for that record locally.
    //        // We have the choice of either deleting the local data or re-uploading the local data.
    //        // For this sample app, let's re-upload the local data.
    //        newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
    //        shouldClearServerRecord = true
    //
    //      case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated,
    //        .operationCancelled:
    //        // There are several errors that the sync engine will automatically retry, let's just log and move on.
    //        Logger.database.debug(
    //          "Retryable error saving \(failedRecord.recordID): \(failedRecordSave.error)"
    //        )
    //
    //      default:
    //        // We got an error, but we don't know what it is or how to handle it.
    //        // If you have any sort of telemetry system, you should consider tracking this scenario so you can understand which errors you see in the wild.
    //        Logger.database.fault(
    //          "Unknown error saving record \(failedRecord.recordID): \(failedRecordSave.error)"
    //        )
    //      }
    //
    //      if shouldClearServerRecord {
    //        if var contact = self.appData.contacts[contactID] {
    //          contact.lastKnownRecord = nil
    //          self.appData.contacts[contactID] = contact
    //        }
    //      }
    //    }
    //
    //    self.syncEngine.state.add(pendingDatabaseChanges: newPendingDatabaseChanges)
    //    self.syncEngine.state.add(pendingRecordZoneChanges: newPendingRecordZoneChanges)
    //
    //    // Now that we've processed the batch, save to disk.
    //    try? self.persistLocalData()
  }

  private func handleFetchedRecordZoneChanges(
    _ changes: CKSyncEngine.Event.FetchedRecordZoneChanges
  ) {
    withErrorReporting {
      try database.write { db in
        for modification in changes.modifications {
          let row = try Row.fetchOne(
            db,
            sql: """
              SELECT * FROM "\(modification.record.recordID.tableName)"
              WHERE "id" = ?
              """,
            arguments: [modification.record.recordID.primaryKey]
          )
          if let row {
            print(row)
            print("?!?!?")
            // TODO: fetch CKRecord data from centralized table associated with modification.recordID
            // TODO: merge modification.record into saved CKRecord, respecting modification dates
            // TODO: merge updated CKRecord state into row data
            // TODO: save freshes CKRecord data into centralized database
            try modification.record.upsert(db: db)
          } else {
            try modification.record.upsert(db: db)
            // TODO: create entry in centralized database with CKRecord
          }
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
      // TODO: fetch record data from centralized table
      let record = CKRecord(recordType: recordID.tableName, recordID: recordID)

      let row = withErrorReporting {
        try database.read { db in
          try Row.fetchOne(
            db,
            SQLRequest(
              sql: """
                SELECT * FROM "\(recordID.tableName)" WHERE "id" = ?
                """,
              arguments: [recordID.primaryKey]
            )
          )
        }
      }

      guard
        let row,  // NB: No error was thrown from fetchOne
        let row  // NB: fetchOne returned a value
      else {
        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
        return nil
      }

      for columnName in row.columnNames {
        switch row[columnName]?.databaseValue.storage {
        case .null:
          if record.encryptedValues[columnName] != nil {
            record.encryptedValues[columnName] = nil
          }
        case .int64(let value):
          if record.object(forKey: columnName) as? Int64 != value {
            record.encryptedValues[columnName] = value
          }
        case .double(let value):
          if record.object(forKey: columnName) as? Double != value {
            record.encryptedValues[columnName] = value
          }
        case .string(let value):
          if record.object(forKey: columnName) as? String != value {
            record.encryptedValues[columnName] = value
          }
        case .blob(let value):
          if record.object(forKey: columnName) as? Data != value {
            record.encryptedValues[columnName] = value
          }
        case .none:
          break
        }
      }
      // TODO: save new record in centralized table

      return record
    }
    return batch
  }
}

extension CKRecord.ID {
  fileprivate var primaryKey: String { recordName }
  fileprivate var tableName: String { zoneID.zoneName }
}

private func stateSerializationKey(containerIdentifier: String?) -> String {
  (containerIdentifier ?? "") + ".stateSerializationData"
}

extension CKRecord {
  func upsert(db: Database) throws {
    let columnNames = try String.fetchAll(
      db,
      sql: """
        SELECT "name" 
        FROM pragma_table_info('\(recordID.tableName)')
        """
    )
    var query: QueryFragment = """
      INSERT INTO \(raw: recordID.tableName) (
      """
    query.append(columnNames.map { "\(quote: $0)" }.joined(separator: ","))
    query.append("""
      ) VALUES (
      """)
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
    print("?!?!")
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
    return _Null<Void>(nilLiteral: ())
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
