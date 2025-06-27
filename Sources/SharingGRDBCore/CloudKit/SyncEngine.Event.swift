#if canImport(CloudKit)
  import CloudKit

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SyncEngine {
    package enum Event: CustomStringConvertible, Sendable {
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
      case sentRecordZoneChanges(SentRecordZoneChanges)
      case willFetchChanges(WillFetchChanges)
      case willFetchRecordZoneChanges(WillFetchRecordZoneChanges)
      case didFetchRecordZoneChanges(DidFetchRecordZoneChanges)
      case didFetchChanges(DidFetchChanges)
      case willSendChanges(WillSendChanges)
      case didSendChanges(DidSendChanges)

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
            SentRecordZoneChanges.init(
              savedRecords: event.savedRecords,
              failedRecordSaves: event.failedRecordSaves
                .map { .init(record: $0.record, error: $0.error) },
              deletedRecordIDs: event.deletedRecordIDs,
              failedRecordDeletes: event.failedRecordDeletes
            )
          )
        case .willFetchChanges(let event):
          if #available(macOS 14.2, iOS 17.2, tvOS 17.2, watchOS 10.2, *) {
            self = .willFetchChanges(WillFetchChanges(context: event.context))
          } else {
            self = .willFetchChanges(WillFetchChanges())
          }
        case .willFetchRecordZoneChanges(let event):
          self = .willFetchRecordZoneChanges(WillFetchRecordZoneChanges(zoneID: event.zoneID))
        case .didFetchRecordZoneChanges(let event):
          self = .didFetchRecordZoneChanges(
            DidFetchRecordZoneChanges(
              zoneID: event.zoneID,
              error: event.error
            )
          )
        case .didFetchChanges(let event):
          if #available(macOS 14.2, iOS 17.2, tvOS 17.2, watchOS 10.2, *) {
            self = .didFetchChanges(DidFetchChanges(context: event.context))
          } else {
            self = .didFetchChanges(DidFetchChanges())
          }
        case .willSendChanges(let event):
          self = .willSendChanges(WillSendChanges(context: event.context))
        case .didSendChanges(let event):
          self = .didSendChanges(DidSendChanges(context: event.context))
        @unknown default:
          return nil
        }
      }

      public var description: String {
        switch self {
        case .stateUpdate:
          return "stateUpdate"
        case .accountChange:
          return "accountChange"
        case .fetchedDatabaseChanges:
          return "fetchedDatabaseChanges"
        case .fetchedRecordZoneChanges:
          return "fetchedRecordZoneChanges"
        case .sentDatabaseChanges:
          return "sentDatabaseChanges"
        case .sentRecordZoneChanges:
          return "sentRecordZoneChanges"
        case .willFetchChanges:
          return "willFetchChanges"
        case .willFetchRecordZoneChanges:
          return "willFetchRecordZoneChanges"
        case .didFetchRecordZoneChanges:
          return "didFetchRecordZoneChanges"
        case .didFetchChanges:
          return "didFetchChanges"
        case .willSendChanges:
          return "willSendChanges"
        case .didSendChanges:
          return "didSendChanges"
        }
      }

      package struct SentRecordZoneChanges: Sendable {
        package let savedRecords: [CKRecord]
        package let failedRecordSaves: [FailedRecordSave]
        package let deletedRecordIDs: [CKRecord.ID]
        package let failedRecordDeletes: [CKRecord.ID: CKError]
        package struct FailedRecordSave: Sendable {
          package let record: CKRecord
          package let error: CKError
        }
      }
      package struct WillFetchChanges: Sendable {
        private var _context: (any Sendable)?
        @available(macOS 14.2, iOS 17.2, tvOS 17.2, watchOS 10.2, *)
        package var context: CKSyncEngine.FetchChangesContext {
          _context as! CKSyncEngine.FetchChangesContext
        }
        @available(macOS 14.2, iOS 17.2, tvOS 17.2, watchOS 10.2, *)
        init(context: CKSyncEngine.FetchChangesContext) {
          _context = context
        }
        init() {
          _context = nil
        }
      }
      package struct FetchChangesContext: Sendable {
        package let reason: CKSyncEngine.SyncReason
        package let options: CKSyncEngine.FetchChangesOptions
      }
      package struct WillFetchRecordZoneChanges: Sendable {
        package let zoneID: CKRecordZone.ID
      }
      package struct DidFetchRecordZoneChanges: Sendable {
        package let zoneID: CKRecordZone.ID
        package let error: CKError?
      }
      package struct DidFetchChanges: Sendable {
        private var _context: (any Sendable)?
        @available(macOS 14.2, iOS 17.2, tvOS 17.2, watchOS 10.2, *)
        package var context: CKSyncEngine.FetchChangesContext {
          _context as! CKSyncEngine.FetchChangesContext
        }
        @available(macOS 14.2, iOS 17.2, tvOS 17.2, watchOS 10.2, *)
        init(context: CKSyncEngine.FetchChangesContext) {
          _context = context
        }
        init() {
          _context = nil
        }
      }
      package struct WillSendChanges: Sendable {
        package let context: CKSyncEngine.SendChangesContext
      }
      package struct DidSendChanges: Sendable {
        package let context: CKSyncEngine.SendChangesContext
      }
    }
  }
#endif
