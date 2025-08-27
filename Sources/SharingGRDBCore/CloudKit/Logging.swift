#if canImport(CloudKit)
import CloudKit
import os

#if SharingGRDBSwiftLog
  import Logging
#endif

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension Logger {
  func log(_ event: SyncEngine.Event, syncEngine: any SyncEngineProtocol) {
    switch self {
    case .osLogger(let logger):
      logger.log(event, syncEngine: syncEngine)
    #if SharingGRDBSwiftLog
      case .swiftLogger(let logger):
        logger.log(event, syncEngine: syncEngine)
    #endif
    }
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension os.Logger {
  func log(_ event: SyncEngine.Event, syncEngine: any SyncEngineProtocol) {
    let prefix = "[\(syncEngine.database.databaseScope.label)] handleEvent:"
    switch event {
    case .stateUpdate:
      debug("\(prefix) stateUpdate")
    case .accountChange(let changeType):
      switch changeType {
      case .signIn(let currentUser):
        debug(
          """
          \(prefix) signIn
            Current user: \(currentUser.recordName).\(currentUser.zoneID.ownerName).\(currentUser.zoneID.zoneName)
          """
        )
      case .signOut(let previousUser):
        debug(
          """
          \(prefix) signOut
            Previous user: \(previousUser.recordName).\(previousUser.zoneID.ownerName).\(previousUser.zoneID.zoneName)
          """
        )
      case .switchAccounts(let previousUser, let currentUser):
        debug(
          """
          \(prefix) switchAccounts:
            Previous user: \(previousUser.recordName).\(previousUser.zoneID.ownerName).\(previousUser.zoneID.zoneName)
            Current user:  \(currentUser.recordName).\(currentUser.zoneID.ownerName).\(currentUser.zoneID.zoneName)
          """
        )
      @unknown default:
        debug("unknown")
      }
    case .fetchedDatabaseChanges(_, let deletions):
      debug(
        """
        \(prefix) fetchedDatabaseChanges
          \(deletedZones(ids: deletions.map(\.zoneID)))
        """
      )
    case .fetchedRecordZoneChanges(let modifications, let deletions):
      let (modifications, deletions) = fetchedRecordZoneChanges(
        modifications: modifications,
        deletions: deletions
      )
      debug(
        """
        \(prefix) fetchedRecordZoneChanges
          \(modifications)
          \(deletions)
        """
      )
    case .sentDatabaseChanges(
      let savedZones,
      let failedZoneSaves,
      let deletedZoneIDs,
      let failedZoneDeletes
    ):
      let (savedZones, deletedZones, failedZoneSaves, failedZoneDeletes) = sentDatabaseChanges(
        savedZones: savedZones,
        failedZoneSaves: failedZoneSaves,
        deletedZoneIDs: deletedZoneIDs,
        failedZoneDeletes: failedZoneDeletes
      )
      debug(
        """
        \(prefix) sentDatabaseChanges
          \(savedZones)
          \(deletedZones)
          \(failedZoneSaves)
          \(failedZoneDeletes)
        """
      )
    case .sentRecordZoneChanges(
      let savedRecords,
      let failedRecordSaves,
      let deletedRecordIDs,
      let failedRecordDeletes
    ):
      let (
        savedRecords,
        deletedRecords,
        failedRecordSaves,
        failedRecordDeletes
      ) = sentRecordZoneChanges(
        savedRecords: savedRecords,
        failedRecordSaves: failedRecordSaves,
        deletedRecordIDs: deletedRecordIDs,
        failedRecordDeletes: failedRecordDeletes
      )
      debug(
        """
        \(prefix) sentRecordZoneChanges
          \(savedRecords)
          \(deletedRecords)
          \(failedRecordSaves)
          \(failedRecordDeletes)
        """
      )
    case .willFetchChanges:
      debug("\(prefix) willFetchChanges")
    case .willFetchRecordZoneChanges(let zoneID):
      debug("\(prefix) willFetchRecordZoneChanges: \(zoneID.zoneName)")
    case .didFetchRecordZoneChanges(let zoneID, let error):
      let error = error.map(\.code.type).map { "\n  ❌ \($0)" } ?? ""
      debug(
        """
        \(prefix) willFetchRecordZoneChanges
          ✅ Zone: \(zoneID.zoneName):\(zoneID.ownerName)\(error)
        """
      )
    case .didFetchChanges:
      debug("\(prefix) didFetchChanges")
    case .willSendChanges(let context):
      debug("\(prefix) willSendChanges: \(context.reason.description)")
    case .didSendChanges(let context):
      debug("\(prefix) didSendChanges: \(context.reason.description)")
    @unknown default:
      warning("\(prefix) ⚠️ unknown event: \(event.description)")
    }
  }
}

#if SharingGRDBSwiftLog
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension Logging.Logger {
    func log(_ event: SyncEngine.Event, syncEngine: any SyncEngineProtocol) {
      var metadata: Logging.Logger.Metadata = [
        "databaseScope.label": "\(syncEngine.database.databaseScope.label)"
      ]
      switch event {
      case .stateUpdate:
        debug("stateUpdate", metadata: metadata)
      case .accountChange(let changeType):
        switch changeType {
        case .signIn(let currentUser):
          metadata["currentUser"] = "\(currentUser.recordName).\(currentUser.zoneID.ownerName).\(currentUser.zoneID.zoneName)"
          debug("signIn", metadata: metadata)
        case .signOut(let previousUser):
          metadata["previousUser"] = "\(previousUser.recordName).\(previousUser.zoneID.ownerName).\(previousUser.zoneID.zoneName)"
          debug("signOut", metadata: metadata)
        case .switchAccounts(let previousUser, let currentUser):
          metadata["currentUser"] = "\(currentUser.recordName).\(currentUser.zoneID.ownerName).\(currentUser.zoneID.zoneName)"
          metadata["previousUser"] = "\(previousUser.recordName).\(previousUser.zoneID.ownerName).\(previousUser.zoneID.zoneName)"
          debug("switchAccounts", metadata: metadata)
        @unknown default:
          debug("unknown", metadata: metadata)
        }
      case .fetchedDatabaseChanges(_, let deletions):
        metadata["zones.deleted"] = "\(deletedZones(ids: deletions.map(\.zoneID)))"
        debug("fetchedDatabaseChanges", metadata: metadata)
      case .fetchedRecordZoneChanges(let modifications, let deletions):
        let (modifications, deletions) = fetchedRecordZoneChanges(
          modifications: modifications,
          deletions: deletions
        )
        metadata["records.modifications"] = "\(modifications)"
        metadata["records.deleted"] = "\(deletions)"
        debug("fetchedRecordZoneChanges", metadata: metadata)
      case .sentDatabaseChanges(
        let savedZones,
        let failedZoneSaves,
        let deletedZoneIDs,
        let failedZoneDeletes
      ):
        let (savedZones, deletedZones, failedZoneSaves, failedZoneDeletes) = sentDatabaseChanges(
          savedZones: savedZones,
          failedZoneSaves: failedZoneSaves,
          deletedZoneIDs: deletedZoneIDs,
          failedZoneDeletes: failedZoneDeletes
        )
        metadata["zones.saved"] = "\(savedZones)"
        metadata["zones.deleted"] = "\(deletedZones)"
        metadata["zones.failed.saves"] = "\(failedZoneSaves)"
        metadata["zones.failed.deletes"] = "\(failedZoneDeletes)"
        debug("sentDatabaseChanges", metadata: metadata)
      case .sentRecordZoneChanges(
        let savedRecords,
        let failedRecordSaves,
        let deletedRecordIDs,
        let failedRecordDeletes
      ):
        let (
          savedRecords,
          deletedRecords,
          failedRecordSaves,
          failedRecordDeletes
        ) = sentRecordZoneChanges(
          savedRecords: savedRecords,
          failedRecordSaves: failedRecordSaves,
          deletedRecordIDs: deletedRecordIDs,
          failedRecordDeletes: failedRecordDeletes
        )
        metadata["records.saves"] = "\(savedRecords)"
        metadata["records.deletes"] = "\(deletedRecords)"
        metadata["records.failed.saves"] = "\(failedRecordSaves)"
        metadata["records.failed.deletes"] = "\(failedRecordDeletes)"
        debug("sentRecordZoneChanges", metadata: metadata)
      case .willFetchChanges:
        debug("willFetchChanges", metadata: defaultMetadata)
      case .willFetchRecordZoneChanges(let zoneID):
        metadata["zone"] = "\(zoneID.zoneName):\(zoneID.ownerName)"
        debug("willFetchRecordZoneChanges", metadata: metadata)
      case .didFetchRecordZoneChanges(let zoneID, let error):
        metadata["zone"] = "\(zoneID.zoneName):\(zoneID.ownerName)"
        if let error {
          metadata["error"] = "\(error.code.type)"
        }
        debug("willFetchRecordZoneChanges", metadata: metadata)
      case .didFetchChanges:
        debug("didFetchChanges", metadata: defaultMetadata)
      case .willSendChanges(let context):
        metadata["context.reason"] = "\(context.reason.description)"
        debug("willSendChanges", metadata: metadata)
      case .didSendChanges(let context):
        metadata["context.reason"] = "\(context.reason.description)"
        debug("didSendChanges", metadata: metadata)
      @unknown default:
        metadata["event"] = "\(event.description)"
        warning("⚠️ unknown event", metadata: metadata)
      }
    }
  }
#endif

private func deletedZones(ids: [CKRecordZone.ID]) -> String {
  ids.isEmpty
    ? "⚪️ No deletions"
    : "✅ Zones deleted (\(ids.count)): "
      + ids
      .map { $0.zoneName + ":" + $0.ownerName }
      .sorted()
      .joined(separator: ", ")
}

private func fetchedRecordZoneChanges(
  modifications: [CKRecord],
  deletions: [(recordID: CKRecord.ID, recordType: CKRecord.RecordType)]
) -> (modifications: String, deletions: String) {
  let deletionsByRecordType = Dictionary(
    grouping: deletions,
    by: \.recordType
  )
  let recordTypeDeletions = deletionsByRecordType.keys.sorted()
    .map { recordType in "\(recordType) (\(deletionsByRecordType[recordType]!.count))" }
    .joined(separator: ", ")
  let deletions =
    deletions.isEmpty
    ? "⚪️ No deletions" : "✅ Records deleted (\(deletions.count)): \(recordTypeDeletions)"

  let modificationsByRecordType = Dictionary(
    grouping: modifications,
    by: \.recordType
  )
  let recordTypeModifications = modificationsByRecordType.keys.sorted()
    .map { recordType in "\(recordType) (\(modificationsByRecordType[recordType]!.count))" }
    .joined(separator: ", ")
  let modifications =
    modifications.isEmpty
    ? "⚪️ No modifications"
    : "✅ Records modified (\(modifications.count)): \(recordTypeModifications)"
  return (modifications, deletions)
}

private func sentDatabaseChanges(
  savedZones: [CKRecordZone],
  failedZoneSaves: [(zone: CKRecordZone, error: CKError)],
  deletedZoneIDs: [CKRecordZone.ID],
  failedZoneDeletes: [CKRecordZone.ID: CKError]
) -> (
  savedZones: String,
  deletedZones: String,
  failedZoneSaves: String,
  failedZoneDeletes: String
) {
  let savedZoneNames = savedZones
    .map { $0.zoneID.zoneName + ":" + $0.zoneID.ownerName }
    .sorted()
    .joined(separator: ", ")
  let savedZones =
    savedZones.isEmpty
    ? "⚪️ No saved zones" : "✅ Saved zones (\(savedZones.count)): \(savedZoneNames)"

  let deletedZoneNames = deletedZoneIDs
    .map { $0.zoneName }
    .sorted()
    .joined(separator: ", ")
  let deletedZones =
    deletedZoneIDs.isEmpty
    ? "⚪️ No deleted zones"
    : "✅ Deleted zones (\(deletedZoneIDs.count)): \(deletedZoneNames)"

  let failedZoneSaveNames = failedZoneSaves
    .map { $0.zone.zoneID.zoneName + ":" + $0.zone.zoneID.ownerName }
    .sorted()
    .joined(separator: ", ")
  let failedZoneSaves =
    failedZoneSaves.isEmpty
    ? "⚪️ No failed saved zones"
    : "🛑 Failed zone saves (\(failedZoneSaves.count)): \(failedZoneSaveNames)"

  let failedZoneDeleteNames = failedZoneDeletes
    .keys
    .map { $0.zoneName }
    .sorted()
    .joined(separator: ", ")
  let failedZoneDeletes =
    failedZoneDeletes.isEmpty
    ? "⚪️ No failed deleted zones"
    : "🛑 Failed zone delete (\(failedZoneDeletes.count)): \(failedZoneDeleteNames)"
  return (savedZones, deletedZones, failedZoneSaves, failedZoneDeletes)
}

private func sentRecordZoneChanges(
  savedRecords: [CKRecord],
  failedRecordSaves: [(record: CKRecord, error: CKError)],
  deletedRecordIDs: [CKRecord.ID],
  failedRecordDeletes: [CKRecord.ID: CKError]
) -> (
  savedRecords: String,
  deletedRecords: String,
  failedRecordSaves: String,
  failedRecordDeletes: String
) {
  let savedRecordsByRecordType = Dictionary(
    grouping: savedRecords,
    by: \.recordType
  )
  let savedRecords = savedRecordsByRecordType.keys
    .sorted()
    .map { "\($0) (\(savedRecordsByRecordType[$0]!.count))" }
    .joined(separator: ", ")

  let failedRecordSavesByZoneName = Dictionary(
    grouping: failedRecordSaves,
    by: { $0.record.recordID.zoneID.zoneName + ":" + $0.record.recordID.zoneID.ownerName }
  )
  let failedRecordSaves = failedRecordSavesByZoneName.keys
    .sorted()
    .map { "\($0) (\(failedRecordSavesByZoneName[$0]!.count))" }
    .joined(separator: ", ")
  let savedRecordsMessage = savedRecordsByRecordType.isEmpty
    ? "⚪️ No records saved" : "✅ Saved records: \(savedRecords)"
  let deletedRecords = deletedRecordIDs.isEmpty 
    ? "⚪️ No records deleted" : "✅ Deleted records (\(deletedRecordIDs.count))"
  let failedRecordSavesMessage = failedRecordSavesByZoneName.isEmpty
    ? "⚪️ No records failed save" : "🛑 Records failed save: \(failedRecordSaves)"
  let failedRecordDeletes = failedRecordDeletes.isEmpty
    ? "⚪️ No records failed delete" : "🛑 Records failed delete (\(failedRecordDeletes.count))"
  return (savedRecordsMessage, deletedRecords, failedRecordSavesMessage, failedRecordDeletes)
}

extension CKError.Code {
  fileprivate var type: String {
    switch self {
    case .internalError: "internalError"
    case .partialFailure: "partialFailure"
    case .networkUnavailable: "networkUnavailable"
    case .networkFailure: "networkFailure"
    case .badContainer: "badContainer"
    case .serviceUnavailable: "serviceUnavailable"
    case .requestRateLimited: "requestRateLimited"
    case .missingEntitlement: "missingEntitlement"
    case .notAuthenticated: "notAuthenticated"
    case .permissionFailure: "permissionFailure"
    case .unknownItem: "unknownItem"
    case .invalidArguments: "invalidArguments"
    case .resultsTruncated: "resultsTruncated"
    case .serverRecordChanged: "serverRecordChanged"
    case .serverRejectedRequest: "serverRejectedRequest"
    case .assetFileNotFound: "assetFileNotFound"
    case .assetFileModified: "assetFileModified"
    case .incompatibleVersion: "incompatibleVersion"
    case .constraintViolation: "constraintViolation"
    case .operationCancelled: "operationCancelled"
    case .changeTokenExpired: "changeTokenExpired"
    case .batchRequestFailed: "batchRequestFailed"
    case .zoneBusy: "zoneBusy"
    case .badDatabase: "badDatabase"
    case .quotaExceeded: "quotaExceeded"
    case .zoneNotFound: "zoneNotFound"
    case .limitExceeded: "limitExceeded"
    case .userDeletedZone: "userDeletedZone"
    case .tooManyParticipants: "tooManyParticipants"
    case .alreadyShared: "alreadyShared"
    case .referenceViolation: "referenceViolation"
    case .managedAccountRestricted: "managedAccountRestricted"
    case .participantMayNeedVerification: "participantMayNeedVerification"
    case .serverResponseLost: "serverResponseLost"
    case .assetNotAvailable: "assetNotAvailable"
    case .accountTemporarilyUnavailable: "accountTemporarilyUnavailable"
    @unknown default: "unknown"
    }
  }
}

extension CKDatabase.Scope {
  var label: String {
    switch self {
    case .public: "public"
    case .private: "private"
    case .shared: "shared"
    @unknown default: "unknown"
    }
  }
}
#endif
