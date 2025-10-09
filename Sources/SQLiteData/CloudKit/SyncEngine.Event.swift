#if canImport(CloudKit)
  import CloudKit

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SyncEngine {
    public enum Event: CustomStringConvertible, Sendable {
      case stateUpdate(stateSerialization: CKSyncEngine.State.Serialization)
      case accountChange(changeType: CKSyncEngine.Event.AccountChange.ChangeType)
      case fetchedDatabaseChanges(
        modifications: [CKRecordZone.ID],
        deletions: [(zoneID: CKRecordZone.ID, reason: CKDatabase.DatabaseChange.Deletion.Reason)]
      )
      case fetchedRecordZoneChanges(
        modifications: [CKRecord],
        deletions: [(recordID: CKRecord.ID, recordType: CKRecord.RecordType)]
      )
      case sentDatabaseChanges(
        savedZones: [CKRecordZone],
        failedZoneSaves: [(zone: CKRecordZone, error: CKError)],
        deletedZoneIDs: [CKRecordZone.ID],
        failedZoneDeletes: [CKRecordZone.ID: CKError]
      )
      case sentRecordZoneChanges(
        savedRecords: [CKRecord],
        failedRecordSaves: [(record: CKRecord, error: CKError)],
        deletedRecordIDs: [CKRecord.ID],
        failedRecordDeletes: [CKRecord.ID: CKError]
      )
      case willFetchChanges
      case willFetchRecordZoneChanges(zoneID: CKRecordZone.ID)
      case didFetchChanges
      case didFetchRecordZoneChanges(zoneID: CKRecordZone.ID, error: CKError?)
      case willSendChanges(context: CKSyncEngine.SendChangesContext)
      case didSendChanges(context: CKSyncEngine.SendChangesContext)

      init?(_ event: CKSyncEngine.Event) {
        switch event {
        case .stateUpdate(let event):
          self = .stateUpdate(stateSerialization: event.stateSerialization)
        case .accountChange(let event):
          self = .accountChange(changeType: event.changeType)
        case .fetchedDatabaseChanges(let event):
          self = .fetchedDatabaseChanges(
            modifications: event.modifications.map(\.zoneID),
            deletions: event.deletions.map { (zoneID: $0.zoneID, reason: $0.reason) }
          )
        case .fetchedRecordZoneChanges(let event):
          self = .fetchedRecordZoneChanges(
            modifications: event.modifications.map(\.record),
            deletions: event.deletions.map {
              (recordID: $0.recordID, recordType: $0.recordType)
            }
          )
        case .sentDatabaseChanges(let event):
          self = .sentDatabaseChanges(
            savedZones: event.savedZones,
            failedZoneSaves: event.failedZoneSaves.map { (zone: $0.zone, error: $0.error) },
            deletedZoneIDs: event.deletedZoneIDs,
            failedZoneDeletes: event.failedZoneDeletes
          )
        case .sentRecordZoneChanges(let event):
          self = .sentRecordZoneChanges(
            savedRecords: event.savedRecords,
            failedRecordSaves: event.failedRecordSaves.map { (record: $0.record, error: $0.error) },
            deletedRecordIDs: event.deletedRecordIDs,
            failedRecordDeletes: event.failedRecordDeletes
          )
        case .willFetchChanges:
          self = .willFetchChanges
        case .willFetchRecordZoneChanges(let event):
          self = .willFetchRecordZoneChanges(zoneID: event.zoneID)
        case .didFetchChanges:
          self = .didFetchChanges
        case .didFetchRecordZoneChanges(let event):
          self = .didFetchRecordZoneChanges(zoneID: event.zoneID, error: event.error)
        case .willSendChanges(let event):
          self = .willSendChanges(context: event.context)
        case .didSendChanges(let event):
          self = .didSendChanges(context: event.context)
        @unknown default:
          return nil
        }
      }

      public var description: String {
        switch self {
        case .stateUpdate: "stateUpdate"
        case .accountChange: "accountChange"
        case .fetchedDatabaseChanges: "fetchedDatabaseChanges"
        case .fetchedRecordZoneChanges: "fetchedRecordZoneChanges"
        case .sentDatabaseChanges: "sentDatabaseChanges"
        case .sentRecordZoneChanges: "sentRecordZoneChanges"
        case .willFetchChanges: "willFetchChanges"
        case .willFetchRecordZoneChanges: "willFetchRecordZoneChanges"
        case .didFetchRecordZoneChanges: "didFetchRecordZoneChanges"
        case .didFetchChanges: "didFetchChanges"
        case .willSendChanges: "willSendChanges"
        case .didSendChanges: "didSendChanges"
        }
      }
    }
  }
#endif
