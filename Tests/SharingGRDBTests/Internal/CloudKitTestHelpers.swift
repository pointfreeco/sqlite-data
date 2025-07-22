import CloudKit
import ConcurrencyExtras
import CustomDump
import OrderedCollections
import SharingGRDBCore
import Testing

extension PrimaryKeyedTable where PrimaryKey.QueryOutput: IdentifierStringConvertible {
  static func recordID(
    for id: PrimaryKey.QueryOutput,
    zoneID: CKRecordZone.ID? = nil
  ) -> CKRecord.ID {
    CKRecord.ID(
      recordName: self.recordName(for: id),
      zoneID: zoneID ?? SyncEngine.defaultZone.zoneID
    )
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
final class MockSyncEngine: SyncEngineProtocol {
  let database: MockCloudDatabase
  let delegate: any SyncEngineDelegate
  private let _state: LockIsolated<MockSyncEngineState>
  private let _fetchChangesScopes = LockIsolated<[CKSyncEngine.FetchChangesOptions.Scope]>([])
  private let _acceptedShareMetadata = LockIsolated<Set<ShareMetadata>>([])
  let scope: CKDatabase.Scope

  init(
    database: MockCloudDatabase,
    delegate: any SyncEngineDelegate,
    scope: CKDatabase.Scope,
    state: MockSyncEngineState
  ) {
    self.database = database
    self.delegate = delegate
    self.scope = scope
    self._state = LockIsolated(state)
  }

  var state: MockSyncEngineState {
    _state.withValue(\.self)
  }

  func acceptShare(metadata: ShareMetadata) {
    _ = _acceptedShareMetadata.withValue { $0.insert(metadata) }
  }

  func fetchChanges(_ options: CKSyncEngine.FetchChangesOptions) async throws {
    // TODO: do something here
  }

  func recordZoneChangeBatch(
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

    state.remove(pendingRecordZoneChanges: recordIDsSkipped.map { .saveRecord($0) })

    return CKSyncEngine.RecordZoneChangeBatch(
      recordsToSave: recordsToSave,
      recordIDsToDelete: recordIDsToDelete
    )
  }

  func assertFetchChangesScopes(
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

  func assertPendingDatabaseChanges(
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

  var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] {
    _pendingRecordZoneChanges.withValue { Array($0) }
  }

  var pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] {
    _pendingDatabaseChanges.withValue { Array($0) }
  }

  func add(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange]) {
    self._pendingRecordZoneChanges.withValue {
      $0.append(contentsOf: pendingRecordZoneChanges)
    }
  }
  func remove(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange]) {
    self._pendingRecordZoneChanges.withValue {
      $0.subtract(pendingRecordZoneChanges)
    }
  }
  func add(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange]) {
    self._pendingDatabaseChanges.withValue {
      $0.append(contentsOf: pendingDatabaseChanges)
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

final class MockCloudDatabase: CloudDatabase {
  let storage = LockIsolated<[CKRecordZone.ID: [CKRecord.ID: CKRecord]]>([:])
  let assets = LockIsolated<[AssetID: Data]>([:])
  let databaseScope: CKDatabase.Scope
  let _container = IsolatedWeakVar<MockCloudContainer>()

  let dataManager = Dependency(\.dataManager)

  struct AssetID: Hashable {
    let recordID: CKRecord.ID
    let key: String
  }

  init(databaseScope: CKDatabase.Scope) {
    self.databaseScope = databaseScope
  }

  func set(container: MockCloudContainer) {
    _container.set(container)
  }

  var container: MockCloudContainer {
    _container.value!
  }

  func record(for recordID: CKRecord.ID) throws -> CKRecord {
    let accountStatus = container.accountStatus()
    guard accountStatus == .available
    else { throw ckError(forAccountStatus: accountStatus) }
    guard let zone = storage[recordID.zoneID]
    else { throw CKError(.zoneNotFound) }
    guard let record = zone[recordID]
    else { throw CKError(.unknownItem) }
    guard let record = record.copy() as? CKRecord
    else { fatalError("Could not copy CKRecord.") }

    try assets.withValue { assets in
      for key in record.allKeys() {
        guard let assetData = assets[AssetID(recordID: record.recordID, key: key)]
        else { continue }
        let url = URL(filePath: UUID().uuidString.lowercased())
        try dataManager.wrappedValue.save(assetData, to: url)
        record[key] = CKAsset(fileURL: url)
      }
    }

    return record
  }

  func records(
    for ids: [CKRecord.ID],
    desiredKeys: [CKRecord.FieldKey]?
  ) throws -> [CKRecord.ID: Result<CKRecord, any Error>] {
    let accountStatus = container.accountStatus()
    guard accountStatus == .available
    else { throw ckError(forAccountStatus: accountStatus) }

    var results: [CKRecord.ID: Result<CKRecord, any Error>] = [:]
    for id in ids {
      results[id] = Result { try record(for: id) }
    }
    return results
  }

  func modifyRecords(
    saving recordsToSave: [CKRecord] = [],
    deleting recordIDsToDelete: [CKRecord.ID] = [],
    savePolicy: CKModifyRecordsOperation.RecordSavePolicy = .ifServerRecordUnchanged,
    atomically: Bool = true
  ) throws -> (
    saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
    deleteResults: [CKRecord.ID: Result<Void, any Error>]
  ) {
    let accountStatus = container.accountStatus()
    guard accountStatus == .available
    else { throw ckError(forAccountStatus: accountStatus) }

    return storage.withValue { storage in
      var saveResults: [CKRecord.ID: Result<CKRecord, any Error>] = [:]
      var deleteResults: [CKRecord.ID: Result<Void, any Error>] = [:]

      switch savePolicy {
      case .ifServerRecordUnchanged:
        for recordToSave in recordsToSave {
          guard storage[recordToSave.recordID.zoneID] != nil
          else {
            saveResults[recordToSave.recordID] = .failure(CKError(.zoneNotFound))
            continue
          }

          let existingRecord = storage[recordToSave.recordID.zoneID]?[recordToSave.recordID]

          func saveRecordToDatabase() {
            let hasReferenceViolation =
              recordToSave.parent.map { parent in
                storage[parent.recordID.zoneID]?[parent.recordID] == nil
                  && !recordsToSave.contains { $0.recordID == parent.recordID }
              }
              ?? false
            guard !hasReferenceViolation
            else {
              saveResults[recordToSave.recordID] = .failure(CKError(.referenceViolation))
              return
            }

            guard let copy = recordToSave.copy() as? CKRecord
            else { fatalError("Could not copy CKRecord.") }
            copy._recordChangeTag = UUID().uuidString
            assets.withValue { assets in
              for key in copy.allKeys() {
                guard let assetURL = (copy[key] as? CKAsset)?.fileURL
                else { continue }
                assets[AssetID(recordID: copy.recordID, key: key)] = try? dataManager.wrappedValue
                  .load(assetURL)
              }
            }
            storage[recordToSave.recordID.zoneID]?[recordToSave.recordID] = copy
            saveResults[recordToSave.recordID] = .success(copy)
          }

          switch (existingRecord, recordToSave._recordChangeTag) {
          case (.some(let existingRecord), .some(let recordToSaveChangeTag)):
            // We are trying to save a record with a change tag that also already exists in the
            // DB. If the tags match, we can save the record. Otherwise, we notify the sync engine
            // that the server record has changed since it was last synced.
            if existingRecord._recordChangeTag == recordToSaveChangeTag {
              precondition(existingRecord._recordChangeTag != nil)
              saveRecordToDatabase()
            } else {
              saveResults[recordToSave.recordID] = .failure(
                CKError(
                  .serverRecordChanged,
                  userInfo: [
                    CKRecordChangedErrorServerRecordKey: existingRecord.copy() as Any,
                    CKRecordChangedErrorClientRecordKey: recordToSave.copy(),
                  ]
                )
              )
            }
            break
          case (.some(let existingRecord), .none):
            // We are trying to save a record that does not have a change tag yet also already
            // exists in the DB. This means the user has created a new CKRecord from scratch,
            // giving it a new identity, rather than leveraging an existing CKRecord.
            Issue.record(
              """
              A new identity was created for an existing 'CKRecord' \
              ('\(existingRecord.recordID.recordName)'). Rather than creating \
              'CKRecord' from scratch for an existing record, use the database to fetch the \
              current record.
              """
            )
            saveResults[recordToSave.recordID] = .failure(
              CKError(
                .serverRejectedRequest,
                userInfo: [
                  CKRecordChangedErrorServerRecordKey: existingRecord.copy() as Any,
                  CKRecordChangedErrorClientRecordKey: recordToSave.copy(),
                ]
              )
            )
          case (.none, .some):
            // We are trying to save a record with a change tag but it does not exist in the DB.
            // This means the record was deleted by another device.
            saveResults[recordToSave.recordID] = .failure(CKError(.unknownItem))
          case (.none, .none):
            // We are trying to save a record with no change tag and no existing record in the DB.
            // This means it's a brand new record.
            saveRecordToDatabase()
          }
        }
      case .allKeys, .changedKeys:
        fatalError()
      @unknown default:
        fatalError()
      }
      for recordIDToDelete in recordIDsToDelete {
        guard storage[recordIDToDelete.zoneID] != nil
        else {
          deleteResults[recordIDToDelete] = .failure(CKError(.zoneNotFound))
          continue
        }
        let hasReferenceViolation = !Set(
          storage[recordIDToDelete.zoneID]?.values
            .compactMap { $0.parent?.recordID == recordIDToDelete ? $0.recordID : nil }
            ?? []
        )
        .subtracting(recordIDsToDelete)
        .isEmpty

        guard !hasReferenceViolation
        else {
          deleteResults[recordIDToDelete] = .failure(CKError(.referenceViolation))
          continue
        }
        storage[recordIDToDelete.zoneID]?[recordIDToDelete] = nil
        deleteResults[recordIDToDelete] = .success(())
      }

      return (saveResults: saveResults, deleteResults: deleteResults)
    }
  }

  func modifyRecordZones(
    saving recordZonesToSave: [CKRecordZone] = [],
    deleting recordZoneIDsToDelete: [CKRecordZone.ID] = []
  ) throws -> (
    saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>],
    deleteResults: [CKRecordZone.ID: Result<Void, any Error>]
  ) {
    let accountStatus = container.accountStatus()
    guard accountStatus == .available
    else { throw ckError(forAccountStatus: accountStatus) }

    return storage.withValue { storage in
      var saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>] = [:]
      var deleteResults: [CKRecordZone.ID: Result<Void, any Error>] = [:]

      for recordZoneToSave in recordZonesToSave {
        storage[recordZoneToSave.zoneID] = storage[recordZoneToSave.zoneID] ?? [:]
        saveResults[recordZoneToSave.zoneID] = .success(recordZoneToSave)
      }

      for recordZoneIDsToDelete in recordZoneIDsToDelete {
        guard storage[recordZoneIDsToDelete] != nil
        else {
          deleteResults[recordZoneIDsToDelete] = .failure(CKError(.zoneNotFound))
          continue
        }
        storage[recordZoneIDsToDelete] = nil
        deleteResults[recordZoneIDsToDelete] = .success(())
      }

      return (saveResults: saveResults, deleteResults: deleteResults)
    }
  }

  nonisolated static func == (lhs: MockCloudDatabase, rhs: MockCloudDatabase) -> Bool {
    lhs === rhs
  }

  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

extension MockCloudDatabase: CustomDumpReflectable {
  var customDumpMirror: Mirror {
    Mirror(
      self,
      children: [
        "databaseScope": databaseScope,
        "storage": storage
            .value
            .flatMap { _, value in value.values }
            .sorted {
              ($0.recordType, $0.recordID.recordName) < ($1.recordType, $1.recordID.recordName)
            }
        ,
      ],
      displayStyle: .struct
    )
  }
}

final class MockCloudContainer: CloudContainer, CustomDumpReflectable {
  let _accountStatus: LockIsolated<CKAccountStatus>
  let containerIdentifier: String?
  let privateCloudDatabase: MockCloudDatabase
  let sharedCloudDatabase: MockCloudDatabase

  init(
    accountStatus: CKAccountStatus = .available,
    containerIdentifier: String?,
    privateCloudDatabase: MockCloudDatabase,
    sharedCloudDatabase: MockCloudDatabase
  ) {
    self._accountStatus = LockIsolated(accountStatus)
    self.containerIdentifier = containerIdentifier
    self.privateCloudDatabase = privateCloudDatabase
    self.sharedCloudDatabase = sharedCloudDatabase
  }

  func accountStatus() -> CKAccountStatus {
    _accountStatus.withValue(\.self)
  }

  var rawValue: CKContainer {
    fatalError("This should never be called in tests.")
  }

  func shareMetadata(for url: URL, shouldFetchRootRecord: Bool) async throws -> CKShare.Metadata {
    fatalError()
  }

  func accept(_ metadata: CKShare.Metadata) async throws -> CKShare {
    fatalError()
  }

  static func createContainer(identifier containerIdentifier: String) -> MockCloudContainer {
    @Dependency(\.mockCloudContainers) var mockCloudContainers
    return mockCloudContainers.withValue { storage in
      let container: MockCloudContainer
      if let existingContainer = storage[containerIdentifier] {
        container = existingContainer
      } else {
        container = MockCloudContainer(
          containerIdentifier: containerIdentifier,
          privateCloudDatabase: MockCloudDatabase(databaseScope: .private),
          sharedCloudDatabase: MockCloudDatabase(databaseScope: .shared)
        )
        container.privateCloudDatabase.set(container: container)
        container.sharedCloudDatabase.set(container: container)
      }
      storage[containerIdentifier] = container
      return container
    }
  }

  static func == (lhs: MockCloudContainer, rhs: MockCloudContainer) -> Bool {
    lhs === rhs
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
  var customDumpMirror: Mirror {
    Mirror.init(
      self,
      children: [
        ("privateCloudDatabase", privateCloudDatabase),
        ("sharedCloudDatabase", sharedCloudDatabase),
      ],
      displayStyle: .struct
    )
  }
}

private enum MockCloudContainersKey: TestDependencyKey {
  static var testValue: LockIsolated<[String: MockCloudContainer]> {
    LockIsolated<[String: MockCloudContainer]>([:])
  }
}
extension DependencyValues {
  var mockCloudContainers: LockIsolated<[String: MockCloudContainer]> {
    get {
      self[MockCloudContainersKey.self]
    }
    set {
      self[MockCloudContainersKey.self] = newValue
    }
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

extension SyncEngine {
  struct ModifyRecordsCallback {
    fileprivate let operation: @Sendable () async -> Void
    func notify() async {
      await operation()
    }
  }

  func modifyRecordZones(
    scope: CKDatabase.Scope,
    saving recordZonesToSave: [CKRecordZone] = [],
    deleting recordZoneIDsToDelete: [CKRecordZone.ID] = []
  ) throws -> ModifyRecordsCallback {
    let syncEngine = syncEngine(for: scope)

    let (saveResults, deleteResults) = try syncEngine.database.modifyRecordZones(
        saving: recordZonesToSave,
        deleting: recordZoneIDsToDelete
      )

    return ModifyRecordsCallback {
      await syncEngine.delegate
        .handleEvent(
          .fetchedDatabaseChanges(
            modifications: saveResults.values.compactMap { try? $0.get().zoneID },
            deletions: deleteResults.compactMap { zoneID, result in
              ((try? result.get()) != nil)
              ? (zoneID, .deleted)
              : nil
            }
          ),
          syncEngine: syncEngine
        )
    }
  }

  func modifyRecords(
    scope: CKDatabase.Scope,
    saving recordsToSave: [CKRecord] = [],
    deleting recordIDsToDelete: [CKRecord.ID] = []
  ) throws -> ModifyRecordsCallback {
    let syncEngine = syncEngine(for: scope)
    let recordsToDeleteByID = Dictionary(
      grouping: syncEngine.database.storage.withValue { storage in
        recordIDsToDelete.compactMap { recordID in storage[recordID.zoneID]?[recordID] }
      },
      by: \.recordID
    )
    .compactMapValues(\.first)

    let (saveResults, deleteResults) = try syncEngine.database.modifyRecords(
      saving: recordsToSave,
      deleting: recordIDsToDelete
    )

    return ModifyRecordsCallback {
      await syncEngine.delegate.handleEvent(
        .fetchedRecordZoneChanges(
          modifications: saveResults.values.compactMap { try? $0.get() },
          deletions: deleteResults.compactMap { recordID, result in
            syncEngine.database.storage.withValue { storage in
              (recordsToDeleteByID[recordID]?.recordType).flatMap { recordType in
                (try? result.get()) != nil
                  ? (recordID, recordType)
                  : nil
              }
            }
          }
        ),
        syncEngine: syncEngine
      )
    }
  }

  func processPendingRecordZoneChanges(
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
      Issue.record(
        "Processing empty set of record zone changes.",
        sourceLocation: SourceLocation.init(
          fileID: String(describing: fileID),
          filePath: String(describing: filePath),
          line: Int(line),
          column: Int(column)
        )
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

    await syncEngine.delegate
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

  func processPendingDatabaseChanges(
    scope: CKDatabase.Scope,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async throws {
    let syncEngine = syncEngine(for: scope)
    guard !syncEngine.state.pendingDatabaseChanges.isEmpty
    else {
      Issue.record(
        "Processing empty set of database changes.",
        sourceLocation: SourceLocation.init(
          fileID: String(describing: fileID),
          filePath: String(describing: filePath),
          line: Int(line),
          column: Int(column)
        )
      )
      return
    }

    var zonesToSave: [CKRecordZone] = []
    var zoneIDsToDelete: [CKRecordZone.ID] = []
    for pendingDatabaseChange in syncEngine.state.pendingDatabaseChanges {
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
    var failedZoneDeletes: [CKRecordZone.ID : CKError] = [:]
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

    syncEngine.state.remove(pendingDatabaseChanges: savedZones.map { .saveZone($0) })
    syncEngine.state.remove(pendingDatabaseChanges: deletedZoneIDs.map { .deleteZone($0) })

    await syncEngine.delegate
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

  private func syncEngine(for scope: CKDatabase.Scope) -> MockSyncEngine {
    switch scope {
    case .public:
      fatalError("Public database not supported in tests.")
    case .private:
      `private`
    case .shared:
      shared
    @unknown default:
      fatalError("Unknown database scope not supported in tests.")
    }
  }
}

private func ckError(forAccountStatus accountStatus: CKAccountStatus) -> CKError {
  switch accountStatus {
  case .couldNotDetermine, .restricted, .noAccount:
    return CKError(.notAuthenticated)
  case .temporarilyUnavailable:
    return CKError(.accountTemporarilyUnavailable)
  case .available:
    fatalError()
  @unknown default:
    fatalError()
  }
}
