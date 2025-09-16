import CloudKit
import CustomDump
import OrderedCollections

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
package final class MockSyncEngine: SyncEngineProtocol {
  package let database: MockCloudDatabase
  package let parentSyncEngine: SyncEngine
  private let _state: LockIsolated<MockSyncEngineState>
  private let _fetchChangesScopes = LockIsolated<[CKSyncEngine.FetchChangesOptions.Scope]>([])
  private let _acceptedShareMetadata = LockIsolated<Set<ShareMetadata>>([])

  package init(
    database: MockCloudDatabase,
    parentSyncEngine: SyncEngine,
    state: MockSyncEngineState
  ) {
    self.database = database
    self.parentSyncEngine = parentSyncEngine
    self._state = LockIsolated(state)
  }

  package var scope: CKDatabase.Scope {
    database.databaseScope
  }

  package var state: MockSyncEngineState {
    _state.withValue(\.self)
  }

  package func acceptShare(metadata: ShareMetadata) {
    _ = _acceptedShareMetadata.withValue { $0.insert(metadata) }
  }

  package func fetchChanges(_ options: CKSyncEngine.FetchChangesOptions) async throws {
    let records: [CKRecord]
    let zoneIDs: [CKRecordZone.ID]
    switch options.scope {
    case .all:
      zoneIDs = Array(database.storage.keys)
    case .allExcluding(let excludedZoneIDs):
      zoneIDs = Array(Set(database.storage.keys).subtracting(excludedZoneIDs))
    case .zoneIDs(let includedZoneIDs):
      zoneIDs = includedZoneIDs
    @unknown default:
      fatalError()
    }
    records = zoneIDs.reduce(into: [CKRecord]()) { accum, zoneID in
      accum += database.storage.withValue {
        ($0[zoneID]?.values).map { Array($0) } ?? []
      }
    }
    await parentSyncEngine.handleEvent(
      .fetchedRecordZoneChanges(modifications: records, deletions: []),
      syncEngine: self
    )
  }

  package func sendChanges(_ options: CKSyncEngine.SendChangesOptions) async throws {
    guard
      !parentSyncEngine.syncEngine(for: database.databaseScope).state.pendingRecordZoneChanges
        .isEmpty
    else { return }
    try await parentSyncEngine.processPendingRecordZoneChanges(scope: database.databaseScope)
  }

  package func recordZoneChangeBatch(
    pendingChanges: [CKSyncEngine.PendingRecordZoneChange],
    recordProvider: @Sendable (CKRecord.ID) async -> CKRecord?
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    var recordsToSave: [CKRecord] = []
    var recordIDsSkipped: [CKRecord.ID] = []
    var recordIDsToDelete: [CKRecord.ID] = []
    for pendingChange in pendingChanges {
      switch pendingChange {
      case .saveRecord(let recordID):
        guard let record = await recordProvider(recordID)
        else {
          recordIDsSkipped.append(recordID)
          continue
        }
        recordsToSave.append(record)
      case .deleteRecord(let recordID):
        recordIDsToDelete.append(recordID)
      @unknown default:
        fatalError()
      }
    }

    state.remove(pendingRecordZoneChanges: recordsToSave.map { .saveRecord($0.recordID) })

    return CKSyncEngine.RecordZoneChangeBatch(
      recordsToSave: recordsToSave,
      recordIDsToDelete: recordIDsToDelete
    )
  }

  package func assertFetchChangesScopes(
    _ scopes: [CKSyncEngine.FetchChangesOptions.Scope],
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

  package func assertAcceptedShareMetadata(
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

  package func cancelOperations() async {
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
package final class MockSyncEngineState: CKSyncEngineStateProtocol, CustomDumpReflectable {
  private let _pendingRecordZoneChanges = LockIsolated<
    OrderedSet<CKSyncEngine.PendingRecordZoneChange>
  >([]
  )
  private let _pendingDatabaseChanges = LockIsolated<
    OrderedSet<CKSyncEngine.PendingDatabaseChange>
  >([])
  private let fileID: StaticString
  private let filePath: StaticString
  private let line: UInt
  private let column: UInt

  package init(
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

  package func assertPendingRecordZoneChanges(
    _ changes: OrderedSet<CKSyncEngine.PendingRecordZoneChange>,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) {
    _pendingRecordZoneChanges.withValue {
      expectNoDifference(
        Set(changes),
        Set($0),
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      $0.removeAll()
    }
  }

  package func assertPendingDatabaseChanges(
    _ changes: OrderedSet<CKSyncEngine.PendingDatabaseChange>,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) {
    _pendingDatabaseChanges.withValue {
      expectNoDifference(
        Set(changes),
        Set($0),
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      $0.removeAll()
    }
  }

  package var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] {
    _pendingRecordZoneChanges.withValue { Array($0) }
  }

  package var pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] {
    _pendingDatabaseChanges.withValue { Array($0) }
  }

  package func removePendingChanges() {
    _pendingDatabaseChanges.withValue { $0.removeAll() }
    _pendingRecordZoneChanges.withValue { $0.removeAll() }
  }

  package func add(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange]) {
    self._pendingRecordZoneChanges.withValue {
      $0.append(contentsOf: pendingRecordZoneChanges)
    }
  }

  package func remove(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange]) {
    self._pendingRecordZoneChanges.withValue {
      $0.subtract(pendingRecordZoneChanges)
    }
  }

  package func add(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange]) {
    self._pendingDatabaseChanges.withValue {
      $0.append(contentsOf: pendingDatabaseChanges)
    }
  }

  package func remove(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange]) {
    self._pendingDatabaseChanges.withValue {
      $0.subtract(pendingDatabaseChanges)
    }
  }

  package var customDumpMirror: Mirror {
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

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
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

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
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
extension SyncEngine {
  package func processPendingRecordZoneChanges(
    options: CKSyncEngine.SendChangesOptions = CKSyncEngine.SendChangesOptions(),
    scope: CKDatabase.Scope,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async throws {
    let syncEngine = syncEngine(for: scope)
    guard !syncEngine.state.pendingRecordZoneChanges.isEmpty
    else {
      reportIssue(
        "Processing empty set of record zone changes.",
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      return
    }
    guard try await container.accountStatus() == .available
    else {
      reportIssue(
        """
        User must be logged in to process pending changes.
        """,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      return
    }

    let batch = await nextRecordZoneChangeBatch(
      reason: .scheduled,
      options: options,
      syncEngine: {
        switch scope {
        case .private:
          self.private
        case .shared:
          self.shared
        case .public:
          fatalError("Public database not supported in tests.")
        @unknown default:
          fatalError("Unknown database scope not supported in tests.")
        }
      }()
    )
    guard let batch
    else { return }

    let (saveResults, deleteResults) = try syncEngine.database.modifyRecords(
      saving: batch.recordsToSave,
      deleting: batch.recordIDsToDelete,
      savePolicy: .ifServerRecordUnchanged,
      atomically: true
    )

    var savedRecords: [CKRecord] = []
    var failedRecordSaves: [(record: CKRecord, error: CKError)] = []
    var deletedRecordIDs: [CKRecord.ID] = []
    var failedRecordDeletes: [CKRecord.ID: CKError] = [:]
    for (recordID, result) in saveResults {
      switch result {
      case .success(let record):
        savedRecords.append(record)
      case .failure(let error as CKError):
        guard let record = batch.recordsToSave.first(where: { $0.recordID == recordID })
        else { fatalError("\(recordID.debugDescription) not found in pending changes") }
        failedRecordSaves.append((record: record, error: error))
      case .failure:
        fatalError("Mocks should only raise 'CKError' values.")
      }
    }
    for (recordID, result) in deleteResults {
      switch result {
      case .success:
        deletedRecordIDs.append(recordID)
      case .failure(let error as CKError):
        failedRecordDeletes[recordID] = error
      case .failure:
        fatalError("Mocks should only raise 'CKError' values.")
      }
    }
    syncEngine.state.remove(
      pendingRecordZoneChanges: savedRecords.map { .saveRecord($0.recordID) }
    )
    syncEngine.state.remove(
      pendingRecordZoneChanges: deletedRecordIDs.map { .deleteRecord($0) }
    )

    await syncEngine.parentSyncEngine
      .handleEvent(
        .sentRecordZoneChanges(
          savedRecords: savedRecords,
          failedRecordSaves: failedRecordSaves,
          deletedRecordIDs: deletedRecordIDs,
          failedRecordDeletes: failedRecordDeletes
        ),
        syncEngine: syncEngine
      )
  }

  package var `private`: MockSyncEngine {
    syncEngines.private as! MockSyncEngine
  }
  package var shared: MockSyncEngine {
    syncEngines.shared as! MockSyncEngine
  }

  package func syncEngine(for scope: CKDatabase.Scope) -> MockSyncEngine {
    switch scope {
    case .public:
      fatalError("Public database not supported in sync engines.")
    case .private:
      `private`
    case .shared:
      shared
    @unknown default:
      fatalError("Unknown database scope not supported in sync engines.")
    }
  }
}
