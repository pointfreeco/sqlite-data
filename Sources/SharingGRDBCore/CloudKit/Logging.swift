#if canImport(CloudKit)
import CloudKit
import os

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension Logger {
  func log(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) {
    let prefix = "[\(syncEngine.database.databaseScope.label)] handleEvent:"
    switch event {
    case .stateUpdate:
      debug("\(prefix) stateUpdate")
    case .accountChange(let event):
      switch event.changeType {
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
    case .fetchedDatabaseChanges(let event):
      let deletions =
        event.deletions.isEmpty
        ? "⚪️ No deletions"
        : "✅ Zones deleted (\(event.deletions.count)): "
          + event.deletions
          .map { $0.zoneID.zoneName + ":" + $0.zoneID.ownerName }
          .sorted()
          .joined(separator: ", ")
      debug(
        """
        \(prefix) fetchedDatabaseChanges
          \(deletions)
        """
      )
    case .fetchedRecordZoneChanges(let event):
      let deletionsByRecordType = Dictionary(
        grouping: event.deletions,
        by: \.recordType
      )
      let recordTypeDeletions = deletionsByRecordType.keys.sorted()
        .map { recordType in "\(recordType) (\(deletionsByRecordType[recordType]!.count))" }
        .joined(separator: ", ")
      let deletions =
        event.deletions.isEmpty
        ? "⚪️ No deletions" : "✅ Records deleted (\(event.deletions.count)): \(recordTypeDeletions)"

      let modificationsByRecordType = Dictionary(
        grouping: event.modifications,
        by: \.record.recordType
      )
      let recordTypeModifications = modificationsByRecordType.keys.sorted()
        .map { recordType in "\(recordType) (\(modificationsByRecordType[recordType]!.count))" }
        .joined(separator: ", ")
      let modifications =
        event.modifications.isEmpty
        ? "⚪️ No modifications"
        : "✅ Records modified (\(event.modifications.count)): \(recordTypeModifications)"

      debug(
        """
        \(prefix) fetchedRecordZoneChanges
          \(modifications)
          \(deletions)
        """
      )
    case .sentDatabaseChanges(let event):
      let savedZoneNames = event.savedZones
        .map { $0.zoneID.zoneName + ":" + $0.zoneID.ownerName }
        .sorted()
        .joined(separator: ", ")
      let savedZones =
        event.savedZones.isEmpty
        ? "⚪️ No saved zones" : "✅ Saved zones (\(event.savedZones.count)): \(savedZoneNames)"

      let deletedZoneNames = event.deletedZoneIDs
        .map { $0.zoneName }
        .sorted()
        .joined(separator: ", ")
      let deletedZones =
        event.deletedZoneIDs.isEmpty
        ? "⚪️ No deleted zones"
        : "✅ Deleted zones (\(event.deletedZoneIDs.count)): \(deletedZoneNames)"

      let failedZoneSaveNames = event.failedZoneSaves
        .map { $0.zone.zoneID.zoneName + ":" + $0.zone.zoneID.ownerName }
        .sorted()
        .joined(separator: ", ")
      let failedZoneSaves =
        event.failedZoneSaves.isEmpty
        ? "⚪️ No failed saved zones"
        : "🛑 Failed zone saves (\(event.failedZoneSaves.count)): \(failedZoneSaveNames)"

      let failedZoneDeleteNames = event.failedZoneDeletes
        .keys
        .map { $0.zoneName }
        .sorted()
        .joined(separator: ", ")
      let failedZoneDeletes =
        event.failedZoneDeletes.isEmpty
        ? "⚪️ No failed deleted zones"
        : "🛑 Failed zone delete (\(event.failedZoneDeletes.count)): \(failedZoneDeleteNames)"

      debug(
        """
        \(prefix) sentDatabaseChanges
          \(savedZones)
          \(deletedZones) 
          \(failedZoneSaves)
          \(failedZoneDeletes)
        """
      )
    case .sentRecordZoneChanges(let event):
      let savedRecordsByRecordType = Dictionary(
        grouping: event.savedRecords,
        by: \.recordType
      )
      let savedRecords = savedRecordsByRecordType.keys
        .sorted()
        .map { "\($0) (\(savedRecordsByRecordType[$0]!.count))" }
        .joined(separator: ", ")

      let failedRecordSavesByZoneName = Dictionary(
        grouping: event.failedRecordSaves,
        by: { $0.record.recordID.zoneID.zoneName + ":" + $0.record.recordID.zoneID.ownerName }
      )
      let failedRecordSaves = failedRecordSavesByZoneName.keys
        .sorted()
        .map { "\($0) (\(failedRecordSavesByZoneName[$0]!.count))" }
        .joined(separator: ", ")

      debug(
        """
        \(prefix) sentRecordZoneChanges
          \(savedRecordsByRecordType.isEmpty ? "⚪️ No records saved" : "✅ Saved records: \(savedRecords)")
          \(event.deletedRecordIDs.isEmpty ? "⚪️ No records deleted" : "✅ Deleted records (\(event.deletedRecordIDs.count))")
          \(failedRecordSavesByZoneName.isEmpty ? "⚪️ No records failed save" : "🛑 Records failed save: \(failedRecordSaves)")
          \(event.failedRecordDeletes.isEmpty ? "⚪️ No records failed delete" : "🛑 Records failed delete (\(event.failedRecordDeletes.count))")
        """
      )
    case .willFetchChanges(let event):
      if #available(macOS 14.2, iOS 17.2, tvOS 17.2, watchOS 10.2, *) {
        debug("\(prefix) willFetchChanges: \(event.context.reason.description)")
      } else {
        debug("\(prefix) willFetchChanges")
      }
    case .willFetchRecordZoneChanges(let event):
      debug("\(prefix) willFetchRecordZoneChanges: \(event.zoneID.zoneName)")
    case .didFetchRecordZoneChanges(let event):
      let errorType = event.error.map {
        switch $0.code {
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
      let error = errorType.map { "\n  ❌ \($0)" } ?? ""
      debug(
        """
        \(prefix) willFetchRecordZoneChanges
          ✅ Zone: \(event.zoneID.zoneName):\(event.zoneID.ownerName)\(error)
        """
      )
    case .didFetchChanges(let event):
      if #available(macOS 14.2, iOS 17.2, tvOS 17.2, watchOS 10.2, *) {
        debug("\(prefix) didFetchChanges: \(event.context.reason.description)")
      } else {
        debug("\(prefix) didFetchChanges")
      }
    case .willSendChanges(let event):
      debug("\(prefix) willSendChanges: \(event.context.reason.description)")
    case .didSendChanges(let event):
      debug("\(prefix) didSendChanges: \(event.context.reason.description)")
    @unknown default:
      warning("\(prefix) ⚠️ unknown event: \(event.description)")
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
