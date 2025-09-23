#if canImport(CloudKit)
  import CloudKit
  import os

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension Logger {
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
        let deletions =
          deletions.isEmpty
          ? "⚪️ No deletions"
          : "✅ Zones deleted (\(deletions.count)): "
            + deletions
            .map { $0.zoneID.zoneName + ":" + $0.zoneID.ownerName }
            .sorted()
            .joined(separator: ", ")
        debug(
          """
          \(prefix) fetchedDatabaseChanges
            \(deletions)
          """
        )
      case .fetchedRecordZoneChanges(let modifications, let deletions):
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
        let savedZoneNames =
          savedZones
          .map { $0.zoneID.zoneName + ":" + $0.zoneID.ownerName }
          .sorted()
          .joined(separator: ", ")
        let savedZones =
          savedZones.isEmpty
          ? "⚪️ No saved zones" : "✅ Saved zones (\(savedZones.count)): \(savedZoneNames)"

        let deletedZoneNames =
          deletedZoneIDs
          .map { $0.zoneName }
          .sorted()
          .joined(separator: ", ")
        let deletedZones =
          deletedZoneIDs.isEmpty
          ? "⚪️ No deleted zones"
          : "✅ Deleted zones (\(deletedZoneIDs.count)): \(deletedZoneNames)"

        let failedZoneSaveNames =
          failedZoneSaves
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

        debug(
          """
          \(prefix) sentRecordZoneChanges
            \(savedRecordsByRecordType.isEmpty ? "⚪️ No records saved" : "✅ Saved records: \(savedRecords)")
            \(deletedRecordIDs.isEmpty ? "⚪️ No records deleted" : "✅ Deleted records (\(deletedRecordIDs.count))")
            \(failedRecordSavesByZoneName.isEmpty ? "⚪️ No records failed save" : "🛑 Records failed save: \(failedRecordSaves)")
            \(failedRecordDeletes.isEmpty ? "⚪️ No records failed delete" : "🛑 Records failed delete (\(failedRecordDeletes.count))")
          """
        )
      case .willFetchChanges:
        debug("\(prefix) willFetchChanges")
      case .willFetchRecordZoneChanges(let zoneID):
        debug("\(prefix) willFetchRecordZoneChanges: \(zoneID.zoneName)")
      case .didFetchRecordZoneChanges(let zoneID, let error):
        let errorType = error.map {
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
          #if canImport(FoundationModels)
            case .participantAlreadyInvited:
              "participantAlreadyInvited"
          #endif
          @unknown default: "unknown"
          }
        }
        let error = errorType.map { "\n  ❌ \($0)" } ?? ""
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
