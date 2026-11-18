#if canImport(CloudKit)
  package import ConcurrencyExtras
  package import CloudKit
  import IssueReporting
  package import OrderedCollections

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  package final class MockSyncEngine: SyncEngineProtocol {
    package let database: MockCloudDatabase
    package let parentSyncEngine: SyncEngine
    package let state: MockSyncEngineState
    package let _fetchChangesScopes = LockIsolated<[CKSyncEngine.FetchChangesOptions.Scope]>([])
    package let _acceptedShareMetadata = LockIsolated<Set<ShareMetadata>>([])

    package init(
      database: MockCloudDatabase,
      parentSyncEngine: SyncEngine,
      state: MockSyncEngineState
    ) {
      self.database = database
      self.parentSyncEngine = parentSyncEngine
      self.state = state
    }

    package var scope: CKDatabase.Scope {
      database.databaseScope
    }

    package func acceptShare(metadata: ShareMetadata) {
      _ = _acceptedShareMetadata.withValue { $0.insert(metadata) }
    }

    package func fetchChanges(_ options: CKSyncEngine.FetchChangesOptions) async throws {
      let modifications: [CKRecord]
      let zoneIDs: [CKRecordZone.ID]
      switch options.scope {
      case .all:
        zoneIDs = Array(database.state.storage.keys)
      case .allExcluding(let excludedZoneIDs):
        zoneIDs = Array(Set(database.state.storage.keys).subtracting(excludedZoneIDs))
      case .zoneIDs(let includedZoneIDs):
        zoneIDs = includedZoneIDs
      @unknown default:
        fatalError()
      }

      modifications = state.withState { syncEngineState in
        let currentChangeTag = syncEngineState.changeTag
        return database.state.withValue { dbState in
          zoneIDs.reduce(into: [CKRecord]()) { accum, zoneID in
            accum += ((dbState.storage[zoneID]?.records.values).map { Array($0) } ?? [])
              .map { $0.copy() as! CKRecord }
              .filter {
                precondition(
                  $0._recordChangeTag != nil,
                  "Records stored in database should have their 'recordChangeTag' assigned."
                )
                return $0._recordChangeTag! > currentChangeTag
              }
          }
        }
      }

      let deletions = database.state.withValue {
        let records = $0.deletedRecords.filter { recordID, _ in
          zoneIDs.contains(recordID.zoneID)
        }
        $0.deletedRecords.removeAll { lhsRecordID, _ in
          records.contains { rhsRecordID, _ in lhsRecordID == rhsRecordID }
        }
        return records
      }

      guard !modifications.isEmpty || !deletions.isEmpty
      else { return }

      state.withState {
        $0.changeTag = modifications.compactMap(\._recordChangeTag).max() ?? $0.changeTag
      }

      await parentSyncEngine.handleEvent(
        .fetchedRecordZoneChanges(modifications: modifications, deletions: deletions),
        syncEngine: self
      )
    }

    package func sendChanges(_ options: CKSyncEngine.SendChangesOptions) async throws {
      if !state.pendingDatabaseChanges.isEmpty {
        try await parentSyncEngine.processPendingDatabaseChanges(scope: database.databaseScope)
      }
      if !state.pendingRecordZoneChanges.isEmpty || state.hasPendingUntrackedChanges {
        try await parentSyncEngine.processPendingRecordZoneChanges(
          options: options,
          scope: database.databaseScope
        )
      }
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

    package func cancelOperations() async {
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  package final class MockSyncEngineState: CKSyncEngineStateProtocol {
    package struct State: Sendable {
      package var changeTag = 0
      package var hasPendingUntrackedChanges = false
      package var pendingDatabaseChanges:
        OrderedDictionary<CKRecordZone.ID, CKSyncEngine.PendingDatabaseChange> = [:]
      package var pendingRecordZoneChanges:
        OrderedDictionary<CKRecord.ID, CKSyncEngine.PendingRecordZoneChange> = [:]
    }

    private let state = LockIsolated(State())
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

    package func withState<T: Sendable>(
      _ operation: @Sendable (inout State) throws -> T
    ) rethrows -> T {
      try state.withValue(operation)
    }

    package var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] {
      withState { Array($0.pendingRecordZoneChanges.values) }
    }

    package var pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] {
      withState { Array($0.pendingDatabaseChanges.values) }
    }

    package var hasPendingUntrackedChanges: Bool {
      get { withState(\.hasPendingUntrackedChanges) }
      set { withState { $0.hasPendingUntrackedChanges = newValue } }
    }

    package func removePendingChanges() {
      withState {
        $0.pendingDatabaseChanges.removeAll()
        $0.pendingRecordZoneChanges.removeAll()
        $0.hasPendingUntrackedChanges = false
      }
    }

    package func add(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange]) {
      withState { state in
        for change in pendingRecordZoneChanges {
          guard let id = change.id
          else { fatalError("Unsupported pendingRecordZoneChange: \(change)") }
          state.pendingRecordZoneChanges[id] = change
        }
      }
    }

    package func remove(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange]) {
      withState { state in
        for change in pendingRecordZoneChanges {
          guard let id = change.id
          else { fatalError("Unsupported pendingRecordZoneChange: \(change)") }
          if state.pendingRecordZoneChanges[id] == change {
            state.pendingRecordZoneChanges.removeValue(forKey: id)
          }
        }
      }
    }

    package func add(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange]) {
      withState { state in
        for change in pendingDatabaseChanges {
          guard let zoneID = change.zoneID
          else { fatalError("Unsupported pendingDatabaseChange: \(change)") }
          state.pendingDatabaseChanges[zoneID] = change
        }
      }
    }

    package func remove(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange]) {
      withState { state in
        for change in pendingDatabaseChanges {
          guard let zoneID = change.zoneID
          else { fatalError("Unsupported pendingDatabaseChange: \(change)") }
          if state.pendingDatabaseChanges[zoneID] == change {
            state.pendingDatabaseChanges.removeValue(forKey: zoneID)
          }
        }
      }
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SyncEngine {
    package struct SendRecordsCallback {
      fileprivate let operation: @Sendable () async -> Void
      package func receive() async {
        await operation()
      }
    }

    package func sendPendingRecordZoneChanges(
      options: CKSyncEngine.SendChangesOptions = CKSyncEngine.SendChangesOptions(),
      scope: CKDatabase.Scope,
      forceAtomicByZone: Bool? = nil,
      fileID: StaticString = #fileID,
      filePath: StaticString = #filePath,
      line: UInt = #line,
      column: UInt = #column
    ) async throws -> SendRecordsCallback {
      let syncEngine = syncEngine(for: scope)
      guard
        syncEngine.state.withState({
          !$0.pendingRecordZoneChanges.isEmpty || $0.hasPendingUntrackedChanges
        })
      else {
        reportIssue(
          "Processing empty set of record zone changes.",
          fileID: fileID,
          filePath: filePath,
          line: line,
          column: column
        )
        return SendRecordsCallback {}
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
        return SendRecordsCallback {}
      }

      var batch = await nextRecordZoneChangeBatch(
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
      if let forceAtomicByZone {
        batch?.atomicByZone = forceAtomicByZone
      }
      guard let batch
      else {
        syncEngine.state.withState { $0.hasPendingUntrackedChanges = false }
        return SendRecordsCallback {}
      }

      let (saveResults, deleteResults) = try $_isRateLimitingDisabled.withValue(true) {
        try syncEngine.database.modifyRecords(
          saving: batch.recordsToSave,
          deleting: batch.recordIDsToDelete,
          savePolicy: .ifServerRecordUnchanged,
          atomically: batch.atomicByZone
        )
      }

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
        pendingRecordZoneChanges: failedRecordSaves.map { .saveRecord($0.record.recordID) }
      )
      syncEngine.state.remove(
        pendingRecordZoneChanges: deletedRecordIDs.map { .deleteRecord($0) }
      )
      syncEngine.state.remove(
        pendingRecordZoneChanges: failedRecordDeletes.keys.map { .deleteRecord($0) }
      )

      return SendRecordsCallback {
        [savedRecords, failedRecordSaves, deletedRecordIDs, failedRecordDeletes] in
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
    }

    package func processPendingRecordZoneChanges(
      options: CKSyncEngine.SendChangesOptions = CKSyncEngine.SendChangesOptions(),
      scope: CKDatabase.Scope,
      forceAtomicByZone: Bool? = nil,
      fileID: StaticString = #fileID,
      filePath: StaticString = #filePath,
      line: UInt = #line,
      column: UInt = #column
    ) async throws {
      try await sendPendingRecordZoneChanges(
        options: options,
        scope: scope,
        forceAtomicByZone: forceAtomicByZone,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      .receive()
    }

    package func processPendingDatabaseChanges(
      scope: CKDatabase.Scope,
      fileID: StaticString = #fileID,
      filePath: StaticString = #filePath,
      line: UInt = #line,
      column: UInt = #column
    ) async throws {
      struct Changes {
        var zonesToSave: [CKRecordZone] = []
        var zoneIDsToDelete: [CKRecordZone.ID] = []
        var savedZones: [CKRecordZone] = []
        var failedZoneSaves: [(zone: CKRecordZone, error: CKError)] = []
        var deletedZoneIDs: [CKRecordZone.ID] = []
        var failedZoneDeletes: [CKRecordZone.ID: CKError] = [:]
      }
      let syncEngine = syncEngine(for: scope)
      let changes = try syncEngine.state.withState { syncEngineState -> Changes in
        var changes = Changes()
        guard !syncEngineState.pendingDatabaseChanges.isEmpty
        else {
          reportIssue(
            "Processing empty set of database changes.",
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
          )
          return changes
        }
        guard
          let mockContainer = container as? MockCloudContainer,
          mockContainer.accountStatus() == .available
        else {
          reportIssue(
            "User must be logged in to process pending changes.",
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
          )
          return changes
        }

        for (_, pendingDatabaseChange) in syncEngineState.pendingDatabaseChanges {
          switch pendingDatabaseChange {
          case .saveZone(let zone):
            changes.zonesToSave.append(zone)
          case .deleteZone(let zoneID):
            changes.zoneIDsToDelete.append(zoneID)
          @unknown default:
            fatalError("Unsupported pendingDatabaseChange: \(pendingDatabaseChange)")
          }
        }
        let results:
          (
            saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>],
            deleteResults: [CKRecordZone.ID: Result<Void, any Error>]
          ) = try $_isRateLimitingDisabled.withValue(true) {
            try syncEngine.database.modifyRecordZones(
              saving: changes.zonesToSave,
              deleting: changes.zoneIDsToDelete
            )
          }
        for (zoneID, saveResult) in results.saveResults {
          switch saveResult {
          case .success(let zone):
            changes.savedZones.append(zone)
          case .failure(let error as CKError):
            changes.failedZoneSaves.append(
              (changes.zonesToSave.first(where: { $0.zoneID == zoneID })!, error)
            )
          case .failure(let error):
            reportIssue("Error thrown not CKError: \(error)")
          }
        }
        for (zoneID, deleteResult) in results.deleteResults {
          switch deleteResult {
          case .success:
            changes.deletedZoneIDs.append(zoneID)
          case .failure(let error as CKError):
            changes.failedZoneDeletes[zoneID] = error
          case .failure(let error):
            reportIssue("Error thrown not CKError: \(error)")
          }
        }

        return changes
      }

      syncEngine.state.remove(pendingDatabaseChanges: changes.savedZones.map { .saveZone($0) })
      syncEngine.state.remove(
        pendingDatabaseChanges: changes.deletedZoneIDs.map { .deleteZone($0) }
      )
      await syncEngine.parentSyncEngine
        .handleEvent(
          .sentDatabaseChanges(
            savedZones: changes.savedZones,
            failedZoneSaves: changes.failedZoneSaves,
            deletedZoneIDs: changes.deletedZoneIDs,
            failedZoneDeletes: changes.failedZoneDeletes
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
#endif
