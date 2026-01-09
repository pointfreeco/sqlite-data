#if canImport(CloudKit)
  import CloudKit
import Dependencies
  import IssueReporting
  import OrderedCollections

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  package final class MockSyncEngine: SyncEngineProtocol {
    package let database: MockCloudDatabase
    package let parentSyncEngine: SyncEngine
    package let _fetchChangesScopes = LockIsolated<[CKSyncEngine.FetchChangesOptions.Scope]>([])
    package let _acceptedShareMetadata = LockIsolated<Set<ShareMetadata>>([])
    package let _pendingRecordZoneChanges = LockIsolated<
      OrderedSet<CKSyncEngine.PendingRecordZoneChange>
    >([]
    )
    package let _pendingDatabaseChanges = LockIsolated<
      OrderedSet<CKSyncEngine.PendingDatabaseChange>
    >([])
    private let fileID: StaticString
    private let filePath: StaticString
    private let line: UInt
    private let column: UInt
    let context = Dependency(\.context)

    package init(
      database: MockCloudDatabase,
      parentSyncEngine: SyncEngine,
      fileID: StaticString = #fileID,
      filePath: StaticString = #filePath,
      line: UInt = #line,
      column: UInt = #column
    ) {
      self.database = database
      self.parentSyncEngine = parentSyncEngine
      self.fileID = fileID
      self.filePath = filePath
      self.line = line
      self.column = column
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
        zoneIDs = Array(database.storage.keys)
      case .allExcluding(let excludedZoneIDs):
        zoneIDs = Array(Set(database.storage.keys).subtracting(excludedZoneIDs))
      case .zoneIDs(let includedZoneIDs):
        zoneIDs = includedZoneIDs
      @unknown default:
        fatalError()
      }
      modifications = zoneIDs.reduce(into: [CKRecord]()) { accum, zoneID in
        accum += database.storage.withValue {
          ($0[zoneID]?.records.values).map { Array($0) } ?? []
        }
      }

      await parentSyncEngine.handleEvent(
        .fetchedRecordZoneChanges(
          modifications: modifications,
          deletions: database.deletedRecords.withValue {
            let records = $0.filter { recordID, _ in
              zoneIDs.contains(recordID.zoneID)
            }
            $0.removeAll { lhs, _ in
              records.contains { rhs, _ in lhs == rhs }
            }
            return records
          }
        ),
        syncEngine: self
      )
    }

    package func sendChanges(_ options: CKSyncEngine.SendChangesOptions) async throws {

      if !parentSyncEngine.syncEngine(for: database.databaseScope).pendingDatabaseChanges
        .isEmpty
      {

        try await parentSyncEngine.processPendingDatabaseChanges(scope: database.databaseScope)
      }
      if !parentSyncEngine.syncEngine(for: database.databaseScope).pendingRecordZoneChanges
        .isEmpty
      {

        try await parentSyncEngine.processPendingRecordZoneChanges(scope: database.databaseScope)
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

      remove(pendingRecordZoneChanges: recordsToSave.map { .saveRecord($0.recordID) })

      return CKSyncEngine.RecordZoneChangeBatch(
        recordsToSave: recordsToSave,
        recordIDsToDelete: recordIDsToDelete
      )
    }

    package func cancelOperations() async {
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
      guard !pendingRecordZoneChanges.isEmpty
      else { return }

      self._pendingRecordZoneChanges.withValue {
        $0.append(contentsOf: pendingRecordZoneChanges)
      }

      if context.wrappedValue == .preview {
        Task { try await parentSyncEngine.sendChanges() }
      }
    }

    package func remove(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange]) {
      guard !pendingRecordZoneChanges.isEmpty
      else { return }

      self._pendingRecordZoneChanges.withValue {
        $0.subtract(pendingRecordZoneChanges)
      }
      if context.wrappedValue == .preview {
        Task { try await parentSyncEngine.sendChanges() }
      }
    }

    package func add(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange]) {
      guard !pendingDatabaseChanges.isEmpty
      else { return }

      self._pendingDatabaseChanges.withValue {
        $0.append(contentsOf: pendingDatabaseChanges)
      }
      if context.wrappedValue == .preview {
        Task { try await parentSyncEngine.sendChanges() }
      }
    }

    package func remove(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange]) {
      guard !pendingDatabaseChanges.isEmpty
      else { return }

      self._pendingDatabaseChanges.withValue {
        $0.subtract(pendingDatabaseChanges)
      }
      if context.wrappedValue == .preview {
        Task { try await parentSyncEngine.sendChanges() }
      }
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SyncEngine {
    package func processPendingRecordZoneChanges(
      options: CKSyncEngine.SendChangesOptions = CKSyncEngine.SendChangesOptions(),
      scope: CKDatabase.Scope,
      forceAtomicByZone: Bool? = nil,
      fileID: StaticString = #fileID,
      filePath: StaticString = #filePath,
      line: UInt = #line,
      column: UInt = #column
    ) async throws {
      let syncEngine = syncEngine(for: scope)
      guard !syncEngine.pendingRecordZoneChanges.isEmpty
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
      else { return }

      let (saveResults, deleteResults) = try syncEngine.database.modifyRecords(
        saving: batch.recordsToSave,
        deleting: batch.recordIDsToDelete,
        savePolicy: .ifServerRecordUnchanged,
        atomically: batch.atomicByZone
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
      syncEngine.remove(
        pendingRecordZoneChanges: savedRecords.map { .saveRecord($0.recordID) }
      )
      syncEngine.remove(
        pendingRecordZoneChanges: failedRecordSaves.map { .saveRecord($0.record.recordID) }
      )
      syncEngine.remove(
        pendingRecordZoneChanges: deletedRecordIDs.map { .deleteRecord($0) }
      )
      syncEngine.remove(
        pendingRecordZoneChanges: failedRecordDeletes.keys.map { .deleteRecord($0) }
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

    package func processPendingDatabaseChanges(
      scope: CKDatabase.Scope,
      fileID: StaticString = #fileID,
      filePath: StaticString = #filePath,
      line: UInt = #line,
      column: UInt = #column
    ) async throws {
      let syncEngine = syncEngine(for: scope)
      guard !syncEngine.pendingDatabaseChanges.isEmpty
      else {
        reportIssue(
          "Processing empty set of database changes.",
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
          "User must be logged in to process pending changes.",
          fileID: fileID,
          filePath: filePath,
          line: line,
          column: column
        )
        return
      }

      var zonesToSave: [CKRecordZone] = []
      var zoneIDsToDelete: [CKRecordZone.ID] = []
      for pendingDatabaseChange in syncEngine.pendingDatabaseChanges {
        switch pendingDatabaseChange {
        case .saveZone(let zone):
          zonesToSave.append(zone)
        case .deleteZone(let zoneID):
          zoneIDsToDelete.append(zoneID)
        @unknown default:
          fatalError("Unsupported pendingDatabaseChange: \(pendingDatabaseChange)")
        }
      }
      let results:
        (
          saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>],
          deleteResults: [CKRecordZone.ID: Result<Void, any Error>]
        ) = try syncEngine.database.modifyRecordZones(
          saving: zonesToSave,
          deleting: zoneIDsToDelete
        )
      var savedZones: [CKRecordZone] = []
      var failedZoneSaves: [(zone: CKRecordZone, error: CKError)] = []
      var deletedZoneIDs: [CKRecordZone.ID] = []
      var failedZoneDeletes: [CKRecordZone.ID: CKError] = [:]
      for (zoneID, saveResult) in results.saveResults {
        switch saveResult {
        case .success(let zone):
          savedZones.append(zone)
        case .failure(let error as CKError):
          failedZoneSaves.append((zonesToSave.first(where: { $0.zoneID == zoneID })!, error))
        case .failure(let error):
          reportIssue("Error thrown not CKError: \(error)")
        }
      }
      for (zoneID, deleteResult) in results.deleteResults {
        switch deleteResult {
        case .success:
          deletedZoneIDs.append(zoneID)
        case .failure(let error as CKError):
          failedZoneDeletes[zoneID] = error
        case .failure(let error):
          reportIssue("Error thrown not CKError: \(error)")
        }
      }

      syncEngine.remove(pendingDatabaseChanges: savedZones.map { .saveZone($0) })
      syncEngine.remove(pendingDatabaseChanges: deletedZoneIDs.map { .deleteZone($0) })

      await syncEngine.parentSyncEngine
        .handleEvent(
          .sentDatabaseChanges(
            savedZones: savedZones,
            failedZoneSaves: failedZoneSaves,
            deletedZoneIDs: deletedZoneIDs,
            failedZoneDeletes: failedZoneDeletes
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
