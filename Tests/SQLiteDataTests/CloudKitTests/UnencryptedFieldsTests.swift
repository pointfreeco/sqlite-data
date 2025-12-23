#if canImport(CloudKit)
  import CloudKit
  import CustomDump
  import DependenciesTestSupport
  import Foundation
  import InlineSnapshotTesting
  import OrderedCollections
  import SQLiteData
  import SQLiteDataTestSupport
  import SnapshotTestingCustomDump
  import Testing
  import os

  @MainActor
  @Suite(
    .snapshots(record: .missing),
    .dependencies {
      $0.currentTime.now = 0
      $0.dataManager = InMemoryDataManager()
    },
    .attachMetadatabase(false)
  )
  final class UnencryptedFieldsTests: @unchecked Sendable {
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
          attachMetadatabase: false
        )
      )
      let privateDatabase = MockCloudDatabase(databaseScope: .private)
      let sharedDatabase = MockCloudDatabase(databaseScope: .shared)
      let container = MockCloudContainer(
        accountStatus: .available,
        containerIdentifier: testContainerIdentifier,
        privateCloudDatabase: privateDatabase,
        sharedCloudDatabase: sharedDatabase
      )
      _container = container
      privateDatabase.set(container: container)
      sharedDatabase.set(container: container)

      // Create sync engine with only isCompleted and remindersListID encrypted (title unencrypted)
      _syncEngine = try await SyncEngine(
        container: container,
        userDatabase: userDatabase,
        delegate: nil,
        tables: [
          SynchronizedTable(for: Reminder.self, unencryptedColumnNames: ["title"]),
          SynchronizedTable(for: RemindersList.self, unencryptedColumnNames: ["title"]),
        ],
        privateTables: [
          SynchronizedTable(for: RemindersListPrivate.self, unencryptedColumnNames: []),
        ],
        startImmediately: true
      )

      await syncEngine.handleEvent(
        .accountChange(changeType: .signIn(currentUser: CKRecord.ID(recordName: "currentUser"))),
        syncEngine: syncEngine.private
      )
      await syncEngine.handleEvent(
        .accountChange(changeType: .signIn(currentUser: CKRecord.ID(recordName: "currentUser"))),
        syncEngine: syncEngine.shared
      )
      try await syncEngine.processPendingDatabaseChanges(scope: .private)
    }

    deinit {
      if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *) {
        let syncEngine = _syncEngine as! SyncEngine
        guard syncEngine.isRunning
        else { return }

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
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func unencryptedFieldsStoredInPlainRecord() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 1, title: "Get milk", remindersListID: 1)
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      // Get the reminder record from the mock database
      let reminderRecord = try syncEngine.private.database
        .record(for: Reminder.recordID(for: 1))

      // Verify the title is stored in the unencrypted part (direct record access)
      #expect(reminderRecord["title"] as? String == "Get milk")

      // Verify the title is NOT stored in encryptedValues
      #expect(reminderRecord.encryptedValues["title"] == nil)

      // Verify encrypted fields (like isCompleted) are still stored in encryptedValues
      #expect(reminderRecord.encryptedValues["isCompleted"] != nil)
      #expect(reminderRecord["isCompleted"] == nil)
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func mixedEncryptedAndUnencryptedFields() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 1, isCompleted: true, title: "Get milk", remindersListID: 1)
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      let reminderRecord = try syncEngine.private.database
        .record(for: Reminder.recordID(for: 1))

      // Unencrypted field: title
      #expect(reminderRecord["title"] as? String == "Get milk")
      #expect(reminderRecord.encryptedValues["title"] == nil)

      // Encrypted fields: isCompleted, remindersListID, id
      #expect(reminderRecord.encryptedValues["isCompleted"] as? Int64 == 1)
      #expect(reminderRecord["isCompleted"] == nil)

      #expect(reminderRecord.encryptedValues["remindersListID"] as? Int64 == 1)
      #expect(reminderRecord["remindersListID"] == nil)
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func remoteChangeToUnencryptedField() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 1, title: "Get milk", remindersListID: 1)
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      // Simulate a remote change to the unencrypted title field
      let reminderRecord = try syncEngine.private.database
        .record(for: Reminder.recordID(for: 1))

      // Set the unencrypted field value directly (simulating what CloudKit would do)
      reminderRecord["title"] = "Get bread"
      reminderRecord.encryptedValues["\(CKRecord.userModificationTimeKey)_title"] = Int64(100)
      reminderRecord.encryptedValues[CKRecord.userModificationTimeKey] = Int64(100)

      try await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord]).notify()

      // Verify the local database is updated
      let updatedReminder = try await userDatabase.read { db in
        try Reminder.find(1).fetchOne(db)
      }
      #expect(updatedReminder?.title == "Get bread")
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func multipleTablesWithUnencryptedFields() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          RemindersList(id: 2, title: "Work")
          Reminder(id: 1, title: "Get milk", remindersListID: 1)
          Reminder(id: 2, title: "Buy groceries", remindersListID: 2)
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      // Verify RemindersList.title is unencrypted
      let remindersList1 = try syncEngine.private.database
        .record(for: RemindersList.recordID(for: 1))
      #expect(remindersList1["title"] as? String == "Personal")
      #expect(remindersList1.encryptedValues["title"] == nil)

      let remindersList2 = try syncEngine.private.database
        .record(for: RemindersList.recordID(for: 2))
      #expect(remindersList2["title"] as? String == "Work")
      #expect(remindersList2.encryptedValues["title"] == nil)

      // Verify Reminder.title is unencrypted
      let reminder1 = try syncEngine.private.database
        .record(for: Reminder.recordID(for: 1))
      #expect(reminder1["title"] as? String == "Get milk")
      #expect(reminder1.encryptedValues["title"] == nil)

      let reminder2 = try syncEngine.private.database
        .record(for: Reminder.recordID(for: 2))
      #expect(reminder2["title"] as? String == "Buy groceries")
      #expect(reminder2.encryptedValues["title"] == nil)
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func updateUnencryptedField() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 1, title: "Get milk", remindersListID: 1)
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      // Update the local database
      try await withDependencies {
        $0.currentTime.now += 1
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(1).update { $0.title = "Get bread" }.execute(db)
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
      }

      // Verify the CloudKit record has the updated unencrypted title
      let reminderRecord = try syncEngine.private.database
        .record(for: Reminder.recordID(for: 1))
      #expect(reminderRecord["title"] as? String == "Get bread")
      #expect(reminderRecord.encryptedValues["title"] == nil)
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func nullUnencryptedField() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 1, title: "", remindersListID: 1)  // Empty string (no nil in this schema)
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      let reminderRecord = try syncEngine.private.database
        .record(for: Reminder.recordID(for: 1))

      // Empty string should still be stored unencrypted
      #expect(reminderRecord["title"] as? String == "")
      #expect(reminderRecord.encryptedValues["title"] == nil)
    }
  }

  /// Tests for the `encryptedFields:` init that defaults all fields to unencrypted.
  @MainActor
  @Suite(
    .snapshots(record: .missing),
    .dependencies {
      $0.currentTime.now = 0
      $0.dataManager = InMemoryDataManager()
    },
    .attachMetadatabase(false)
  )
  final class EncryptedFieldsTests: @unchecked Sendable {
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
          attachMetadatabase: false
        )
      )
      let privateDatabase = MockCloudDatabase(databaseScope: .private)
      let sharedDatabase = MockCloudDatabase(databaseScope: .shared)
      let container = MockCloudContainer(
        accountStatus: .available,
        containerIdentifier: testContainerIdentifier,
        privateCloudDatabase: privateDatabase,
        sharedCloudDatabase: sharedDatabase
      )
      _container = container
      privateDatabase.set(container: container)
      sharedDatabase.set(container: container)

      // Create sync engine with only isCompleted encrypted, others are unencrypted
      _syncEngine = try await SyncEngine(
        container: container,
        userDatabase: userDatabase,
        delegate: nil,
        tables: [
          SynchronizedTable(
            for: Reminder.self,
            unencryptedColumnNames: ["id", "title", "remindersListID"]
          ),
          SynchronizedTable(
            for: RemindersList.self,
            unencryptedColumnNames: ["id", "title"]
          ),
        ],
        privateTables: [
          SynchronizedTable(
            for: RemindersListPrivate.self,
            unencryptedColumnNames: ["id", "title"]
          ),
        ],
        startImmediately: true
      )

      await syncEngine.handleEvent(
        .accountChange(changeType: .signIn(currentUser: CKRecord.ID(recordName: "currentUser"))),
        syncEngine: syncEngine.private
      )
      await syncEngine.handleEvent(
        .accountChange(changeType: .signIn(currentUser: CKRecord.ID(recordName: "currentUser"))),
        syncEngine: syncEngine.shared
      )
      try await syncEngine.processPendingDatabaseChanges(scope: .private)
    }

    deinit {
      if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *) {
        let syncEngine = _syncEngine as! SyncEngine
        guard syncEngine.isRunning
        else { return }

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
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func defaultUnencryptedWithSpecificEncrypted() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 1, isCompleted: true, title: "Get milk", remindersListID: 1)
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      let reminderRecord = try syncEngine.private.database
        .record(for: Reminder.recordID(for: 1))

      // isCompleted should be encrypted (specified in encryptedFields)
      #expect(reminderRecord.encryptedValues["isCompleted"] as? Int64 == 1)
      #expect(reminderRecord["isCompleted"] == nil)

      // title should be unencrypted (not in encryptedFields)
      #expect(reminderRecord["title"] as? String == "Get milk")
      #expect(reminderRecord.encryptedValues["title"] == nil)

      // remindersListID should be unencrypted (not in encryptedFields)
      #expect(reminderRecord["remindersListID"] as? Int64 == 1)
      #expect(reminderRecord.encryptedValues["remindersListID"] == nil)

      // id should be unencrypted (not in encryptedFields)
      #expect(reminderRecord["id"] as? Int64 == 1)
      #expect(reminderRecord.encryptedValues["id"] == nil)
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func listFieldsDefaultUnencrypted() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      let listRecord = try syncEngine.private.database
        .record(for: RemindersList.recordID(for: 1))

      // RemindersList has no fields in encryptedFields, so all should be unencrypted
      #expect(listRecord["title"] as? String == "Personal")
      #expect(listRecord.encryptedValues["title"] == nil)

      #expect(listRecord["id"] as? Int64 == 1)
      #expect(listRecord.encryptedValues["id"] == nil)
    }
  }

  /// Tests for the `allFieldsEncrypted: false` init that makes everything unencrypted.
  @MainActor
  @Suite(
    .snapshots(record: .missing),
    .dependencies {
      $0.currentTime.now = 0
      $0.dataManager = InMemoryDataManager()
    },
    .attachMetadatabase(false)
  )
  final class AllFieldsUnencryptedTests: @unchecked Sendable {
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
          attachMetadatabase: false
        )
      )
      let privateDatabase = MockCloudDatabase(databaseScope: .private)
      let sharedDatabase = MockCloudDatabase(databaseScope: .shared)
      let container = MockCloudContainer(
        accountStatus: .available,
        containerIdentifier: testContainerIdentifier,
        privateCloudDatabase: privateDatabase,
        sharedCloudDatabase: sharedDatabase
      )
      _container = container
      privateDatabase.set(container: container)
      sharedDatabase.set(container: container)

      // Create sync engine with everything unencrypted
      _syncEngine = try await SyncEngine(
        container: container,
        userDatabase: userDatabase,
        delegate: nil,
        tables: [
          SynchronizedTable(
            for: Reminder.self,
            unencryptedColumnNames: ["id", "isCompleted", "title", "remindersListID"]
          ),
          SynchronizedTable(
            for: RemindersList.self,
            unencryptedColumnNames: ["id", "title"]
          ),
        ],
        privateTables: [
          SynchronizedTable(
            for: RemindersListPrivate.self,
            unencryptedColumnNames: ["id", "title"]
          ),
        ],
        startImmediately: true
      )

      await syncEngine.handleEvent(
        .accountChange(changeType: .signIn(currentUser: CKRecord.ID(recordName: "currentUser"))),
        syncEngine: syncEngine.private
      )
      await syncEngine.handleEvent(
        .accountChange(changeType: .signIn(currentUser: CKRecord.ID(recordName: "currentUser"))),
        syncEngine: syncEngine.shared
      )
      try await syncEngine.processPendingDatabaseChanges(scope: .private)
    }

    deinit {
      if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *) {
        let syncEngine = _syncEngine as! SyncEngine
        guard syncEngine.isRunning
        else { return }

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
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func allFieldsStoredUnencrypted() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 1, isCompleted: true, title: "Get milk", remindersListID: 1)
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      let reminderRecord = try syncEngine.private.database
        .record(for: Reminder.recordID(for: 1))

      // All fields should be unencrypted
      #expect(reminderRecord["id"] as? Int64 == 1)
      #expect(reminderRecord.encryptedValues["id"] == nil)

      #expect(reminderRecord["title"] as? String == "Get milk")
      #expect(reminderRecord.encryptedValues["title"] == nil)

      #expect(reminderRecord["isCompleted"] as? Int64 == 1)
      #expect(reminderRecord.encryptedValues["isCompleted"] == nil)

      #expect(reminderRecord["remindersListID"] as? Int64 == 1)
      #expect(reminderRecord.encryptedValues["remindersListID"] == nil)

      // Also check the list record
      let listRecord = try syncEngine.private.database
        .record(for: RemindersList.recordID(for: 1))

      #expect(listRecord["id"] as? Int64 == 1)
      #expect(listRecord.encryptedValues["id"] == nil)

      #expect(listRecord["title"] as? String == "Personal")
      #expect(listRecord.encryptedValues["title"] == nil)
    }
  }
#endif
