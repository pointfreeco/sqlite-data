import CloudKit
import DependenciesTestSupport
import OrderedCollections
import SQLiteData
import SnapshotTesting
import Testing
import os

@Suite(
  .snapshots(record: .missing),
  .dependencies {
    $0.currentTime.now = 0
    $0.dataManager = InMemoryDataManager()
  }
)
class BaseCloudKitTests: @unchecked Sendable {
  let userDatabase: UserDatabase
  private let _syncEngine: any Sendable
  private let _container: any Sendable

  @Dependency(\.currentTime.now) var now

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  var container: MockCloudContainer {
    _container as! MockCloudContainer
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  var syncEngine: SyncEngine {
    _syncEngine as! SyncEngine
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  init() async throws {
    let testContainerIdentifier = "iCloud.co.pointfree.Testing.\(UUID())"

    self.userDatabase = UserDatabase(
      database: try SQLiteDataTests.database(
        containerIdentifier: testContainerIdentifier,
        attachMetadatabase: _AttachMetadatabaseTrait.attachMetadatabase
      )
    )
    try await _PrepareDatabaseTrait.prepareDatabase(userDatabase)
    let privateDatabase = MockCloudDatabase(databaseScope: .private)
    let sharedDatabase = MockCloudDatabase(databaseScope: .shared)
    let container = MockCloudContainer(
      accountStatus: _AccountStatusScope.accountStatus,
      containerIdentifier: testContainerIdentifier,
      privateCloudDatabase: privateDatabase,
      sharedCloudDatabase: sharedDatabase
    )
    _container = container
    privateDatabase.set(container: container)
    sharedDatabase.set(container: container)
    _syncEngine = try await SyncEngine(
      container: container,
      userDatabase: self.userDatabase,
      tables: [
        Reminder.self,
        RemindersList.self,
        RemindersListAsset.self,
        Tag.self,
        ReminderTag.self,
        Parent.self,
        ChildWithOnDeleteSetNull.self,
        ChildWithOnDeleteSetDefault.self,
        ModelA.self,
        ModelB.self,
        ModelC.self,
      ],
      privateTables: [
        RemindersListPrivate.self
      ],
      startImmediately: _StartImmediatelyTrait.startImmediately
    )
    if _StartImmediatelyTrait.startImmediately,
      _AccountStatusScope.accountStatus == .available
    {
      await syncEngine.handleEvent(
        .accountChange(changeType: .signIn(currentUser: currentUserRecordID)),
        syncEngine: syncEngine.private
      )
      await syncEngine.handleEvent(
        .accountChange(changeType: .signIn(currentUser: currentUserRecordID)),
        syncEngine: syncEngine.shared
      )
      try await syncEngine.processPendingDatabaseChanges(scope: .private)
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  func signOut() async {
    container._accountStatus.withValue { $0 = .noAccount }
    await syncEngine.handleEvent(
      .accountChange(changeType: .signOut(previousUser: previousUserRecordID)),
      syncEngine: syncEngine.private
    )
    await syncEngine.handleEvent(
      .accountChange(changeType: .signOut(previousUser: previousUserRecordID)),
      syncEngine: syncEngine.shared
    )
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  func softSignOut() async {
    container._accountStatus.withValue { $0 = .temporarilyUnavailable }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  func signIn() async {
    container._accountStatus.withValue { $0 = .available }
    // NB: Emulates what CKSyncEngine does when signing in
    syncEngine.private.state.removePendingChanges()
    syncEngine.shared.state.removePendingChanges()
    await syncEngine.handleEvent(
      .accountChange(changeType: .signIn(currentUser: currentUserRecordID)),
      syncEngine: syncEngine.private
    )
    await syncEngine.handleEvent(
      .accountChange(changeType: .signIn(currentUser: currentUserRecordID)),
      syncEngine: syncEngine.shared
    )
  }

  deinit {
    if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *) {
      syncEngine.shared.assertFetchChangesScopes([])
      syncEngine.shared.state.assertPendingDatabaseChanges([])
      syncEngine.shared.state.assertPendingRecordZoneChanges([])
      syncEngine.shared.assertAcceptedShareMetadata([])
      syncEngine.private.assertFetchChangesScopes([])
      syncEngine.private.state.assertPendingDatabaseChanges([])
      syncEngine.private.state.assertPendingRecordZoneChanges([])
      syncEngine.private.assertAcceptedShareMetadata([])
      try! syncEngine.metadatabase.read { db in
        try #expect(UnsyncedRecordID.count().fetchOne(db) == 0)
      }
    } else {
      Issue.record("Tests must be run on iOS 17+, macOS 14+, tvOS 17+ and watchOS 10+.")
    }
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncEngine {
  var `private`: MockSyncEngine {
    syncEngines.private as! MockSyncEngine
  }
  var shared: MockSyncEngine {
    syncEngines.shared as! MockSyncEngine
  }
  static nonisolated let defaultTestZone = CKRecordZone(
    zoneName: "zone"
  )
  convenience init(
    container: any CloudContainer,
    userDatabase: UserDatabase,
    tables: [any PrimaryKeyedTable.Type],
    privateTables: [any PrimaryKeyedTable.Type] = [],
    startImmediately: Bool = true
  ) async throws {
    try self.init(
      container: container,
      defaultZone: Self.defaultTestZone,
      defaultSyncEngines: { _, syncEngine in
        (
          MockSyncEngine(
            database: container.privateCloudDatabase as! MockCloudDatabase,
            parentSyncEngine: syncEngine,
            state: MockSyncEngineState()
          ),
          MockSyncEngine(
            database: container.sharedCloudDatabase as! MockCloudDatabase,
            parentSyncEngine: syncEngine,
            state: MockSyncEngineState()
          )
        )
      },
      userDatabase: userDatabase,
      logger: Logger(.disabled),
      tables: tables,
      privateTables: privateTables
    )
    try setUpSyncEngine()
    if startImmediately {
      try await start()
    }
  }
}

private let previousUserRecordID = CKRecord.ID(
  recordName: "previousUser"
)
private let currentUserRecordID = CKRecord.ID(
  recordName: "currentUser"
)
