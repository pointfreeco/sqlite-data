import CloudKit
import ConcurrencyExtras
import CustomDump
import SharingGRDBCore

extension PrimaryKeyedTable<UUID> {
  static func recordID(for id: UUID, zoneID: CKRecordZone.ID? = nil) -> CKRecord.ID {
    CKRecord.ID(
      recordName: self.recordName(for: id).rawValue,
      zoneID: zoneID ?? SyncEngine.defaultZone.zoneID
    )
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
final class MockSyncEngine: SyncEngineProtocol {
  let database: MockCloudDatabase
  private let _state: LockIsolated<MockSyncEngineState>
  private let _fetchChangesScopes = LockIsolated<Set<CKSyncEngine.FetchChangesOptions.Scope>>([])
  private let _acceptedShareMetadata = LockIsolated<Set<ShareMetadata>>([])
  let scope: CKDatabase.Scope

  init(
    database: MockCloudDatabase,
    scope: CKDatabase.Scope,
    state: MockSyncEngineState
  ) {
    self.database = database
    self.scope = scope
    self._state = LockIsolated(state)
  }

  var state: MockSyncEngineState {
    _state.withValue(\.self)
  }

  func acceptShare(metadata: ShareMetadata) {
    _ = _acceptedShareMetadata.withValue { $0.insert(metadata) }
  }

  func recordZoneChangeBatch(
    pendingChanges: [CKSyncEngine.PendingRecordZoneChange],
    recordProvider: @Sendable (CKRecord.ID) async -> CKRecord?
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    let savedRecordIDs: [CKRecord.ID] = state.pendingRecordZoneChanges.compactMap {
      guard case .saveRecord(let recordID) = $0
      else { return nil }
      return recordID
    }
    var recordsToSave: [CKRecord] = []
    for recordID in savedRecordIDs {
      guard let record = await recordProvider(recordID)
      else { continue }
      recordsToSave.append(record)
    }
    let recordIDsToDelete: [CKRecord.ID] = state.pendingRecordZoneChanges.compactMap {
      guard case .deleteRecord(let recordID) = $0
      else { return nil }
      return recordID
    }

    state.remove(pendingRecordZoneChanges: recordsToSave.map { .saveRecord($0.recordID) })
    state.remove(pendingRecordZoneChanges: recordIDsToDelete.map { .deleteRecord($0) })
    
    _ = await database.modifyRecords(
      saving: recordsToSave,
      deleting: recordIDsToDelete,
      savePolicy: .ifServerRecordUnchanged,
      atomically: true
    )

    return CKSyncEngine.RecordZoneChangeBatch(
      recordsToSave: recordsToSave,
      recordIDsToDelete: recordIDsToDelete
    )
  }

  func assertFetchChangesScopes(
    _ scopes: Set<CKSyncEngine.FetchChangesOptions.Scope>,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) {
    _fetchChangesScopes.withValue {
      expectNoDifference(
        scopes,
        $0,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      $0.removeAll()
    }
  }

  func assertAcceptedShareMetadata(
    _ sharedMetadata: Set<ShareMetadata>,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) {
    _acceptedShareMetadata.withValue {
      expectNoDifference(
        sharedMetadata,
        $0,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      $0.removeAll()
    }
  }

  func cancelOperations() async {
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
final class MockSyncEngineState: CKSyncEngineStateProtocol, CustomDumpReflectable {
  private let _pendingRecordZoneChanges = LockIsolated<Set<CKSyncEngine.PendingRecordZoneChange>>([]
  )
  private let _pendingDatabaseChanges = LockIsolated<Set<CKSyncEngine.PendingDatabaseChange>>([])
  private let fileID: StaticString
  private let filePath: StaticString
  private let line: UInt
  private let column: UInt

  init(
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) {
    self.fileID = fileID
    self.filePath = filePath
    self.line = line
    self.column = column
  }

  func assertPendingRecordZoneChanges(
    _ changes: Set<CKSyncEngine.PendingRecordZoneChange>,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) {
    _pendingRecordZoneChanges.withValue {
      expectNoDifference(
        changes,
        $0,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      $0.removeAll()
    }
  }

  func assertPendingDatabaseChanges(
    _ changes: Set<CKSyncEngine.PendingDatabaseChange>,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) {
    _pendingDatabaseChanges.withValue {
      expectNoDifference(
        changes,
        $0,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      $0.removeAll()
    }
  }

  var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] {
    _pendingRecordZoneChanges.withValue { Array($0) }
  }

  func add(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange]) {
    self._pendingRecordZoneChanges.withValue {
      $0.formUnion(pendingRecordZoneChanges)
    }
  }
  func remove(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange]) {
    self._pendingRecordZoneChanges.withValue {
      $0.subtract(pendingRecordZoneChanges)
    }
  }
  func add(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange]) {
    self._pendingDatabaseChanges.withValue {
      $0.formUnion(pendingDatabaseChanges)
    }
  }
  func remove(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange]) {
    self._pendingDatabaseChanges.withValue {
      $0.subtract(pendingDatabaseChanges)
    }
  }

  var customDumpMirror: Mirror {
    return Mirror(
      self,
      children: [
        (
          "pendingRecordZoneChanges",
          _pendingRecordZoneChanges.withValue(\.self)
            .sorted(by: comparePendingRecordZoneChange)
            as Any
        ),
        (
          "pendingDatabaseChanges",
          _pendingDatabaseChanges.withValue(\.self)
            .sorted(by: comparePendingDatabaseChange) as Any
        ),
      ],
      displayStyle: .struct
    )
  }
}

actor MockCloudDatabase: CloudDatabase {
  var storage: [CKRecord.ID: CKRecord] = [:]
  let databaseScope: CKDatabase.Scope

  struct RecordNotFound: Error {}

  init(databaseScope: CKDatabase.Scope) {
    self.databaseScope = databaseScope
  }

  func record(for recordID: CKRecord.ID) throws -> CKRecord {
    guard let record = storage[recordID]
    else { throw RecordNotFound() }
    return record
  }

  func records(
    for ids: [CKRecord.ID],
    desiredKeys: [CKRecord.FieldKey]?
  ) throws -> [CKRecord.ID : Result<CKRecord, any Error>] {
    var results: [CKRecord.ID : Result<CKRecord, any Error>] = [:]
    for id in ids {
      results[id] = Result { try record(for: id) }
    }
    return results
  }

  func modifyRecords(
    saving recordsToSave: [CKRecord],
    deleting recordIDsToDelete: [CKRecord.ID],
    savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
    atomically: Bool
  ) -> (
    saveResults: [CKRecord.ID : Result<CKRecord, any Error>],
    deleteResults: [CKRecord.ID : Result<Void, any Error>]
  ) {
    for recordToSave in recordsToSave {
      storage[recordToSave.recordID] = recordToSave
    }
    for recordIDToDelete in recordIDsToDelete {
      storage[recordIDToDelete] = nil
    }
    return (
      saveResults: Dictionary(
        uniqueKeysWithValues: recordsToSave.map { ($0.recordID, .success($0)) }
      ),
      deleteResults: Dictionary(
        uniqueKeysWithValues: recordIDsToDelete.map { ($0, .success(())) }
      )
    )
  }

  nonisolated static func == (lhs: MockCloudDatabase, rhs: MockCloudDatabase) -> Bool {
    lhs === rhs
  }

  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

final class MockCloudContainer: CloudContainer {
  let privateCloudDatabase: MockCloudDatabase
  let sharedCloudDatabase: MockCloudDatabase

  init(privateCloudDatabase: MockCloudDatabase, sharedCloudDatabase: MockCloudDatabase) {
    self.privateCloudDatabase = privateCloudDatabase
    self.sharedCloudDatabase = sharedCloudDatabase
  }

  var rawValue: CKContainer {
    fatalError("This should never be called in tests.")
  }

  func shareMetadata(for url: URL, shouldFetchRootRecord: Bool) async throws -> CKShare.Metadata {
    fatalError()
  }

  static func == (lhs: MockCloudContainer, rhs: MockCloudContainer) -> Bool {
    lhs === rhs
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

private func comparePendingRecordZoneChange(
  _ lhs: CKSyncEngine.PendingRecordZoneChange,
  _ rhs: CKSyncEngine.PendingRecordZoneChange
) -> Bool {
  switch (lhs, rhs) {
  case (.saveRecord(let lhs), .saveRecord(let rhs)),
    (.deleteRecord(let lhs), .deleteRecord(let rhs)):
    lhs.recordName < rhs.recordName
  case (.deleteRecord, .saveRecord):
    true
  case (.saveRecord, .deleteRecord):
    false
  default:
    false
  }
}

private func comparePendingDatabaseChange(
  _ lhs: CKSyncEngine.PendingDatabaseChange,
  _ rhs: CKSyncEngine.PendingDatabaseChange
) -> Bool {
  switch (lhs, rhs) {
  case (.saveZone(let lhs), .saveZone(let rhs)):
    lhs.zoneID.zoneName < rhs.zoneID.zoneName
  case (.deleteZone(let lhs), .deleteZone(let rhs)):
    lhs.zoneName < rhs.zoneName
  case (.deleteZone, .saveZone):
    true
  case (.saveZone, .deleteZone):
    false
  default:
    false
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension CKSyncEngine.FetchChangesOptions.Scope: @retroactive Hashable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case (.all, .all):
      return true
    case (.allExcluding(let lhs), .allExcluding(let rhs)):
      return lhs == rhs
    case (.zoneIDs(let lhs), .zoneIDs(let rhs)):
      return lhs == rhs
    case (.all, _), (.allExcluding, _), (.zoneIDs, _):
      return false
    @unknown default:
      return false
    }
  }
  public func hash(into hasher: inout Hasher) {
    switch self {
    case .all:
      hasher.combine(0)
    case .allExcluding(let zoneIDs):
      hasher.combine(1)
      hasher.combine(zoneIDs)
    case .zoneIDs(let zoneIDs):
      hasher.combine(2)
      hasher.combine(zoneIDs)
    @unknown default:
      hasher.combine(3)
    }
  }
}
