import CloudKit
import DependenciesTestSupport
import OrderedCollections
import SharingGRDB
import SnapshotTesting
import Testing
import os

@Suite(
  .snapshots(record: .missing),
  .dependencies {
    $0.date.now = Date(timeIntervalSince1970: 0)
    $0.dataManager = InMemoryDataManager()
  }
)
class BaseCloudKitTests: @unchecked Sendable {
  let container: MockCloudContainer
  let userDatabase: UserDatabase
  private let _syncEngine: any Sendable

  @Dependency(\.date.now) var now

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  var syncEngine: SyncEngine {
    _syncEngine as! SyncEngine
  }

  typealias SendablePrimaryKeyedTable<T> = PrimaryKeyedTable<T> & Sendable

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  init(
    accountStatus: CKAccountStatus = _AccountStatusScope.accountStatus,
    setUpUserDatabase: @Sendable (UserDatabase) async throws -> Void = { _ in }
  ) async throws {
    let testContainerIdentifier = "iCloud.co.pointfree.Testing.\(UUID())"

    self.userDatabase = UserDatabase(
      database: try SharingGRDBTests.database(containerIdentifier: testContainerIdentifier)
    )
    try await setUpUserDatabase(userDatabase)
    let privateDatabase = MockCloudDatabase(databaseScope: .private)
    let sharedDatabase = MockCloudDatabase(databaseScope: .shared)
    container = MockCloudContainer(
      accountStatus: accountStatus,
      containerIdentifier: testContainerIdentifier,
      privateCloudDatabase: privateDatabase,
      sharedCloudDatabase: sharedDatabase
    )
    privateDatabase.set(container: container)
    sharedDatabase.set(container: container)
    _syncEngine = try await SyncEngine(
      container: container,
      userDatabase: self.userDatabase,
      metadatabaseURL: URL.metadatabase(containerIdentifier: testContainerIdentifier),
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
      ]
    )
    if accountStatus == .available {
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

  func signIn() async {
    container._accountStatus.withValue { $0 = .available }
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
      try! userDatabase.read { db in
        try #expect(UnsyncedRecordID.count().fetchOne(db) == 0)
      }
    } else {
      Issue.record("Tests must be run on iOS 17+, macOS 14+, tvOS 17+ and watchOS 10+.")
    }
  }
}

extension SyncEngine {
  var `private`: MockSyncEngine {
    syncEngines.private as! MockSyncEngine
  }
  var shared: MockSyncEngine {
    syncEngines.shared as! MockSyncEngine
  }
  static nonisolated let defaultTestZone = CKRecordZone(
    zoneName: "co.pointfree.SQLiteData.defaultZone"
  )
  convenience init(
    container: any CloudContainer,
    userDatabase: UserDatabase,
    metadatabaseURL: URL,
    tables: [any PrimaryKeyedTable.Type],
    privateTables: [any PrimaryKeyedTable.Type] = []
  ) async throws {
    try self.init(
      container: container,
      defaultZone: Self.defaultTestZone,
      defaultSyncEngines: { _, syncEngine in
        (
          MockSyncEngine(
            database: container.privateCloudDatabase as! MockCloudDatabase,
            delegate: syncEngine,
            scope: .private,
            state: MockSyncEngineState()
          ),
          MockSyncEngine(
            database: container.sharedCloudDatabase as! MockCloudDatabase,
            delegate: syncEngine,
            scope: .shared,
            state: MockSyncEngineState()
          )
        )
      },
      userDatabase: userDatabase,
      logger: Logger(.disabled),
      metadatabaseURL: metadatabaseURL,
      tables: tables,
      privateTables: privateTables
    )
    try await setUpSyncEngine(userDatabase: userDatabase, metadatabase: metadatabase)?.value
  }
}

private let previousUserRecordID = CKRecord.ID(
  recordName: "previousUser"
)
private let currentUserRecordID = CKRecord.ID(
  recordName: "currentUser"
)
