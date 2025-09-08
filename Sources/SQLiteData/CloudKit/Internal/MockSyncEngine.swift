import CloudKit
import CustomDump
import OrderedCollections

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
package final class MockSyncEngine: SyncEngineProtocol {
  package let database: MockCloudDatabase
  package let delegate: any SyncEngineDelegate
  private let _state: LockIsolated<MockSyncEngineState>
  private let _fetchChangesScopes = LockIsolated<[CKSyncEngine.FetchChangesOptions.Scope]>([])
  private let _acceptedShareMetadata = LockIsolated<Set<ShareMetadata>>([])

  package init(
    database: MockCloudDatabase,
    delegate: any SyncEngineDelegate,
    state: MockSyncEngineState
  ) {
    self.database = database
    self.delegate = delegate
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
    await delegate.handleEvent(
      .fetchedRecordZoneChanges(modifications: records, deletions: []),
      syncEngine: self
    )
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
