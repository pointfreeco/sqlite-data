import CloudKit
import DependenciesTestSupport
import Foundation
import OrderedCollections
import os
import SharingGRDB
import SnapshotTesting
import Testing

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
  let container: MockCloudContainer
  let notificationCenter: NotificationCenter
  private let _syncEngine: any Sendable

  @Dependency(\.date.now) var now

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  var syncEngine: SyncEngine {
    _syncEngine as! SyncEngine
  }

  typealias SendablePrimaryKeyedTable<T> = PrimaryKeyedTable<T> & Sendable

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  init(
    accountStatus: CKAccountStatus = .available,
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
      containerIdentifier: testContainerIdentifier,
      accountStatus: accountStatus,
      privateCloudDatabase: privateDatabase,
      sharedCloudDatabase: sharedDatabase
    )
    notificationCenter = NotificationCenter()
    privateDatabase.set(container: container)
    sharedDatabase.set(container: container)
    _syncEngine = try await SyncEngine(
      container: container,
      userDatabase: self.userDatabase,
      notificationCenter: notificationCenter,
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
        RemindersListPrivate.self,
      ]
    )
    if accountStatus == .available {
    await syncEngine.handleEvent(
      .accountChange(
        changeType: .signIn(
          currentUser: CKRecord
            .ID(
              recordName: "defaultCurrentUser",
              zoneID: syncEngine.defaultZone.zoneID
            )
        )
      ),
      syncEngine: syncEngine.syncEngines.withValue(\.private)!
    )
    try await syncEngine.processPendingDatabaseChanges(scope: .private)
  }
  }

  func updateAccountStatus(_ status: CKAccountStatus) {
    container._accountStatus.withValue { $0 = status }
    notificationCenter.post(name: .CKAccountChanged, object: container)
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
    notificationCenter: NotificationCenter,
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
      notificationCenter: notificationCenter,
      metadatabaseURL: metadatabaseURL,
      tables: tables,
      privateTables: privateTables
    )
    try await setUpSyncEngine(userDatabase: userDatabase, metadatabase: metadatabase)?.value
  }
}
