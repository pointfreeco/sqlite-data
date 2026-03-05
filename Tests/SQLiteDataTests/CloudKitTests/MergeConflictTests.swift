#if canImport(CloudKit)
  import CloudKit
  import CustomDump
  import Foundation
  import InlineSnapshotTesting
  import OrderedCollections
  import SQLiteData
  import SQLiteDataTestSupport
  import SnapshotTestingCustomDump
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    @Suite(.attachMetadatabase, .printTimestamps)
    final class MergeConflictTests: BaseCloudKitTests, @unchecked Sendable {
      
      // MARK: - Different Fields Change

      @Test func differentFieldsChange_conflictOnSend_clientNewer() async throws {
        // Step 1: Seed and initial sync
        try await userDatabase.userWrite { db in
          try db.seed { Post(id: 1, title: "") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "",
                title🗓️: 0,
                🗓️: 0
              )
            ]
          )
          """
        }

        // Step 2: Server edits title @ t=30
        let record = try syncEngine.private.database.record(for: Post.recordID(for: 1))
        record.setValue("Hello", forKey: "title", at: 30)
        let fetchedRecordZoneChangesCallback = try syncEngine.modifyRecords(
          scope: .private,
          saving: [record]
        )

        // Step 3: Client edits isPublished @ t=60
        try await withDependencies {
          $0.currentTime.now = 60
        } operation: {
          try await userDatabase.userWrite { db in
            try Post.find(1).update { $0.isPublished = true }.execute(db)
          }
        }

        // Step 4: Send (rejected, merged locally)
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello",
                title🗓️: 30,
                🗓️: 30
              )
            ]
          )
          """
        }

        // Step 5: Retry send
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        // Step 6: Fetch arrives (no-op, conflict already resolved)
        await fetchedRecordZoneChangesCallback.notify()

        assertQuery(
          Post.find(1)
            .join(SyncMetadata.all) { $0.syncMetadataID.eq($1.id) }
            .select { ($0, $1.userModificationTime) },
          database: userDatabase.database
        ) {
          """
          ┌─────────────────────┬────┐
          │ Post(               │ 60 │
          │   id: 1,            │    │
          │   title: "Hello",   │    │
          │   body: nil,        │    │
          │   isPublished: true │    │
          │ )                   │    │
          └─────────────────────┴────┘
          """
        }
        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 1,
                isPublished🗓️: 60,
                title: "Hello",
                title🗓️: 30,
                🗓️: 60
              )
            ]
          )
          """
        }
      }

      @Test func differentFieldsChange_conflictOnSend_serverNewer() async throws {
        // Step 1: Seed and initial sync
        try await userDatabase.userWrite { db in
          try db.seed { Post(id: 1, title: "") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "",
                title🗓️: 0,
                🗓️: 0
              )
            ]
          )
          """
        }

        // Step 2: Client edits isPublished @ t=30
        try await withDependencies {
          $0.currentTime.now = 30
        } operation: {
          try await userDatabase.userWrite { db in
            try Post.find(1).update { $0.isPublished = true }.execute(db)
          }
        }

        // Step 3: Server edits title @ t=60
        let record = try syncEngine.private.database.record(for: Post.recordID(for: 1))
        record.setValue("Hello", forKey: "title", at: 60)
        let fetchedRecordZoneChangesCallback = try syncEngine.modifyRecords(
          scope: .private,
          saving: [record]
        )

        // Step 4: Send (rejected, merged locally)
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello",
                title🗓️: 60,
                🗓️: 60
              )
            ]
          )
          """
        }

        // Step 5: Retry send
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        // Step 6: Fetch arrives (no-op, conflict already resolved)
        await fetchedRecordZoneChangesCallback.notify()

        assertQuery(
          Post.find(1)
            .join(SyncMetadata.all) { $0.syncMetadataID.eq($1.id) }
            .select { ($0, $1.userModificationTime) },
          database: userDatabase.database
        ) {
          """
          ┌─────────────────────┬────┐
          │ Post(               │ 60 │
          │   id: 1,            │    │
          │   title: "Hello",   │    │
          │   body: nil,        │    │
          │   isPublished: true │    │
          │ )                   │    │
          └─────────────────────┴────┘
          """
        }
        // NB: t_isPublished is 60 (not 30), because all changed fields are sent with the user
        //     modification time, which is set to max(t_client, t_server).
        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 1,
                isPublished🗓️: 60,
                title: "Hello",
                title🗓️: 60,
                🗓️: 60
              )
            ]
          )
          """
        }
      }

      @Test func differentFieldsChange_conflictOnFetch_clientNewer() async throws {
        // Step 1: Seed and initial sync
        try await userDatabase.userWrite { db in
          try db.seed { Post(id: 1, title: "") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "",
                title🗓️: 0,
                🗓️: 0
              )
            ]
          )
          """
        }

        // Step 2: Server edits title @ t=30
        let record = try syncEngine.private.database.record(for: Post.recordID(for: 1))
        record.setValue("Hello", forKey: "title", at: 30)
        let fetchedRecordZoneChangesCallback = try syncEngine.modifyRecords(
          scope: .private,
          saving: [record]
        )
        
        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello",
                title🗓️: 30,
                🗓️: 30
              )
            ]
          )
          """
        }

        // Step 3: Client edits isPublished @ t=60
        try await withDependencies {
          $0.currentTime.now = 60
        } operation: {
          try await userDatabase.userWrite { db in
            try Post.find(1).update { $0.isPublished = true }.execute(db)
          }
        }

        // Step 4: Fetch arrives (merged locally)
        await fetchedRecordZoneChangesCallback.notify()

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello",
                title🗓️: 30,
                🗓️: 30
              )
            ]
          )
          """
        }

        // Step 5: Send (merged record)
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertQuery(
          Post.find(1)
            .join(SyncMetadata.all) { $0.syncMetadataID.eq($1.id) }
            .select { ($0, $1.userModificationTime) },
          database: userDatabase.database
        ) {
          """
          ┌─────────────────────┬────┐
          │ Post(               │ 60 │
          │   id: 1,            │    │
          │   title: "Hello",   │    │
          │   body: nil,        │    │
          │   isPublished: true │    │
          │ )                   │    │
          └─────────────────────┴────┘
          """
        }
        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 1,
                isPublished🗓️: 60,
                title: "Hello",
                title🗓️: 30,
                🗓️: 60
              )
            ]
          )
          """
        }
      }

      @Test func differentFieldsChange_conflictOnFetch_serverNewer() async throws {
        // Step 1: Seed and initial sync
        try await userDatabase.userWrite { db in
          try db.seed { Post(id: 1, title: "") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "",
                title🗓️: 0,
                🗓️: 0
              )
            ]
          )
          """
        }

        // Step 2: Client edits isPublished @ t=30
        try await withDependencies {
          $0.currentTime.now = 30
        } operation: {
          try await userDatabase.userWrite { db in
            try Post.find(1).update { $0.isPublished = true }.execute(db)
          }
        }

        // Step 3: Server edits title @ t=60
        let record = try syncEngine.private.database.record(for: Post.recordID(for: 1))
        record.setValue("Hello", forKey: "title", at: 60)
        let fetchedRecordZoneChangesCallback = try syncEngine.modifyRecords(
          scope: .private,
          saving: [record]
        )

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello",
                title🗓️: 60,
                🗓️: 60
              )
            ]
          )
          """
        }

        // Step 4: Fetch arrives (merged locally)
        await fetchedRecordZoneChangesCallback.notify()

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello",
                title🗓️: 60,
                🗓️: 60
              )
            ]
          )
          """
        }

        // Step 5: Send (merged record)
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertQuery(
          Post.find(1)
            .join(SyncMetadata.all) { $0.syncMetadataID.eq($1.id) }
            .select { ($0, $1.userModificationTime) },
          database: userDatabase.database
        ) {
          """
          ┌─────────────────────┬────┐
          │ Post(               │ 60 │
          │   id: 1,            │    │
          │   title: "Hello",   │    │
          │   body: nil,        │    │
          │   isPublished: true │    │
          │ )                   │    │
          └─────────────────────┴────┘
          """
        }
        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 1,
                isPublished🗓️: 60,
                title: "Hello",
                title🗓️: 60,
                🗓️: 60
              )
            ]
          )
          """
        }
      }

      @Test func differentNullableFieldsChange_conflictOnFetch_clientNewer() async throws {
        // Step 1: Seed and initial sync
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            Reminder(id: 1, remindersListID: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        // Step 2: Server changes dueDate @ t=30
        let record = try syncEngine.private.database.record(for: Reminder.recordID(for: 1))
        record.setValue(Date(timeIntervalSince1970: 30), forKey: "dueDate", at: 30)
        let fetchedRecordZoneChangesCallback = try syncEngine.modifyRecords(
          scope: .private,
          saving: [record]
        )

        // Step 3: Client changes priority @ t=60
        try await withDependencies {
          $0.currentTime.now = 60
        } operation: {
          try await userDatabase.userWrite { db in
            try Reminder.find(1).update { $0.priority = #bind(3) }.execute(db)
          }
        }

        // Step 4: Fetch arrives (conflict, merged locally)
        await fetchedRecordZoneChangesCallback.notify()

        // Step 5: Send (merged result)
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertQuery(
          Reminder.find(1)
            .join(SyncMetadata.all) { $0.syncMetadataID.eq($1.id) }
            .select { ($0, $1.userModificationTime) },
          database: userDatabase.database
        ) {
          """
          ┌────────────────────────────────────────────┬────┐
          │ Reminder(                                  │ 60 │
          │   id: 1,                                   │    │
          │   dueDate: Date(1970-01-01T00:00:30.000Z), │    │
          │   isCompleted: false,                      │    │
          │   priority: 3,                             │    │
          │   title: "",                               │    │
          │   remindersListID: 1                       │    │
          │ )                                          │    │
          └────────────────────────────────────────────┴────┘
          """
        }
        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
                share: nil,
                dueDate: Date(1970-01-01T00:00:30.000Z),
                dueDate🗓️: 30,
                id: 1,
                id🗓️: 0,
                isCompleted: 0,
                isCompleted🗓️: 0,
                priority: 3,
                priority🗓️: 60,
                remindersListID: 1,
                remindersListID🗓️: 0,
                title: "",
                title🗓️: 0,
                🗓️: 60
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
                id🗓️: 0,
                title: "Personal",
                title🗓️: 0,
                🗓️: 0
              )
            ]
          )
          """
        }
      }

      // MARK: - Same Field Change

      @Test func sameFieldChange_conflictOnSend_retryBeforeFetch_clientNewer() async throws {
        // Step 1: Seed and initial sync
        try await userDatabase.userWrite { db in
          try db.seed { Post(id: 1, title: "Hello") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello",
                title🗓️: 0,
                🗓️: 0
              )
            ]
          )
          """
        }

        // Step 2: Server edits title @ t=30
        let record = try syncEngine.private.database.record(for: Post.recordID(for: 1))
        record.setValue("Hello from server", forKey: "title", at: 30)
        let fetchedRecordZoneChangesCallback = try syncEngine.modifyRecords(
          scope: .private,
          saving: [record]
        )

        // Step 3: Client edits title @ t=60
        try await withDependencies {
          $0.currentTime.now = 60
        } operation: {
          try await userDatabase.userWrite { db in
            try Post.find(1).update { $0.title = "Hello from client" }.execute(db)
          }
        }

        // Step 4: Send (rejected, merged locally)
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello from server",
                title🗓️: 30,
                🗓️: 30
              )
            ]
          )
          """
        }

        // Step 5: Retry send
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        // Step 6: Fetch arrives (no-op, conflict already resolved)
        await fetchedRecordZoneChangesCallback.notify()

        assertQuery(
          Post.find(1)
            .join(SyncMetadata.all) { $0.syncMetadataID.eq($1.id) }
            .select { ($0, $1.userModificationTime) },
          database: userDatabase.database
        ) {
          """
          ┌───────────────────────────────┬────┐
          │ Post(                         │ 60 │
          │   id: 1,                      │    │
          │   title: "Hello from client", │    │
          │   body: nil,                  │    │
          │   isPublished: false          │    │
          │ )                             │    │
          └───────────────────────────────┴────┘
          """
        }
        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello from client",
                title🗓️: 60,
                🗓️: 60
              )
            ]
          )
          """
        }
      }

      @Test func sameFieldChange_conflictOnSend_retryBeforeFetch_serverNewer() async throws {
        // Step 1: Seed and initial sync
        try await userDatabase.userWrite { db in
          try db.seed { Post(id: 1, title: "Hello") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello",
                title🗓️: 0,
                🗓️: 0
              )
            ]
          )
          """
        }

        // Step 2: Client edits title @ t=30
        try await withDependencies {
          $0.currentTime.now = 30
        } operation: {
          try await userDatabase.userWrite { db in
            try Post.find(1).update { $0.title = "Hello from client" }.execute(db)
          }
        }

        // Step 3: Server edits title @ t=60
        let record = try syncEngine.private.database.record(for: Post.recordID(for: 1))
        record.setValue("Hello from server", forKey: "title", at: 60)
        let fetchedRecordZoneChangesCallback = try syncEngine.modifyRecords(
          scope: .private,
          saving: [record]
        )

        // Step 4: Send (rejected, merged locally)
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello from server",
                title🗓️: 60,
                🗓️: 60
              )
            ]
          )
          """
        }

        // Step 5: Retry send
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        // Step 6: Fetch arrives (no-op, conflict already resolved)
        await fetchedRecordZoneChangesCallback.notify()

        await withKnownIssue("Server should win same-field conflict when it has a newer timestamp") {
          try await userDatabase.read { db in
            let post = try #require(try Post.find(1).fetchOne(db))
            #expect(post.title == "Hello from server")
          }
        }
      }

      @Test func sameFieldChange_conflictOnSend_fetchBeforeRetry_clientNewer() async throws {
        // Step 1: Seed and initial sync
        try await userDatabase.userWrite { db in
          try db.seed { Post(id: 1, title: "Hello") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello",
                title🗓️: 0,
                🗓️: 0
              )
            ]
          )
          """
        }

        // Step 2: Server edits title @ t=30
        let record = try syncEngine.private.database.record(for: Post.recordID(for: 1))
        record.setValue("Hello from server", forKey: "title", at: 30)
        let fetchedRecordZoneChangesCallback = try syncEngine.modifyRecords(
          scope: .private,
          saving: [record]
        )

        // Step 3: Client edits title @ t=60
        try await withDependencies {
          $0.currentTime.now = 60
        } operation: {
          try await userDatabase.userWrite { db in
            try Post.find(1).update { $0.title = "Hello from client" }.execute(db)
          }
        }

        // Step 4: Send (rejected, merged locally)
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello from server",
                title🗓️: 30,
                🗓️: 30
              )
            ]
          )
          """
        }

        // Step 5: Fetch arrives
        await fetchedRecordZoneChangesCallback.notify()

        // Step 6: Retry send
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertQuery(
          Post.find(1)
            .join(SyncMetadata.all) { $0.syncMetadataID.eq($1.id) }
            .select { ($0, $1.userModificationTime) },
          database: userDatabase.database
        ) {
          """
          ┌───────────────────────────────┬────┐
          │ Post(                         │ 60 │
          │   id: 1,                      │    │
          │   title: "Hello from client", │    │
          │   body: nil,                  │    │
          │   isPublished: false          │    │
          │ )                             │    │
          └───────────────────────────────┴────┘
          """
        }
        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello from client",
                title🗓️: 60,
                🗓️: 60
              )
            ]
          )
          """
        }
      }

      @Test func sameFieldChange_conflictOnSend_fetchBeforeRetry_serverNewer() async throws {
        // Step 1: Seed and initial sync
        try await userDatabase.userWrite { db in
          try db.seed { Post(id: 1, title: "Hello") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello",
                title🗓️: 0,
                🗓️: 0
              )
            ]
          )
          """
        }

        // Step 2: Client edits title @ t=30
        try await withDependencies {
          $0.currentTime.now = 30
        } operation: {
          try await userDatabase.userWrite { db in
            try Post.find(1).update { $0.title = "Hello from client" }.execute(db)
          }
        }

        // Step 3: Server edits title @ t=60
        let record = try syncEngine.private.database.record(for: Post.recordID(for: 1))
        record.setValue("Hello from server", forKey: "title", at: 60)
        let fetchedRecordZoneChangesCallback = try syncEngine.modifyRecords(
          scope: .private,
          saving: [record]
        )

        // Step 4: Send (rejected, merged locally)
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello from server",
                title🗓️: 60,
                🗓️: 60
              )
            ]
          )
          """
        }

        // Step 5: Fetch arrives
        await fetchedRecordZoneChangesCallback.notify()

        // Step 6: Retry send
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        await withKnownIssue("Server should win same-field conflict when it has a newer timestamp") {
          try await userDatabase.read { db in
            let post = try #require(try Post.find(1).fetchOne(db))
            #expect(post.title == "Hello from server")
          }
        }
      }

      @Test func sameFieldChange_conflictOnSend_equalTimestamps() async throws {
        // Step 1: Seed and initial sync
        try await userDatabase.userWrite { db in
          try db.seed { Post(id: 1, title: "Hello") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        // Step 2: Server edits title @ t=60
        let record = try syncEngine.private.database.record(for: Post.recordID(for: 1))
        record.setValue("Hello from server", forKey: "title", at: 60)
        let fetchedRecordZoneChangesCallback = try syncEngine.modifyRecords(
          scope: .private,
          saving: [record]
        )

        // Step 3: Client edits title @ t=60
        try await withDependencies {
          $0.currentTime.now = 60
        } operation: {
          try await userDatabase.userWrite { db in
            try Post.find(1).update { $0.title = "Hello from client" }.execute(db)
          }
        }

        // Step 4: Send (rejected, merged locally)
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        // Step 5: Retry send
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        // Step 6: Fetch arrives (no-op, conflict already resolved)
        await fetchedRecordZoneChangesCallback.notify()

        assertQuery(
          Post.find(1)
            .join(SyncMetadata.all) { $0.syncMetadataID.eq($1.id) }
            .select { ($0, $1.userModificationTime) },
          database: userDatabase.database
        ) {
          """
          ┌───────────────────────────────┬────┐
          │ Post(                         │ 60 │
          │   id: 1,                      │    │
          │   title: "Hello from client", │    │
          │   body: nil,                  │    │
          │   isPublished: false          │    │
          │ )                             │    │
          └───────────────────────────────┴────┘
          """
        }
        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello from client",
                title🗓️: 60,
                🗓️: 60
              )
            ]
          )
          """
        }
      }

      @Test func sameFieldChange_conflictOnFetch_clientNewer() async throws {
        // Step 1: Seed and initial sync
        try await userDatabase.userWrite { db in
          try db.seed { Post(id: 1, title: "Hello") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello",
                title🗓️: 0,
                🗓️: 0
              )
            ]
          )
          """
        }

        // Step 2: Server edits title @ t=30
        let record = try syncEngine.private.database.record(for: Post.recordID(for: 1))
        record.setValue("Hello from server", forKey: "title", at: 30)
        let fetchedRecordZoneChangesCallback = try syncEngine.modifyRecords(
          scope: .private,
          saving: [record]
        )

        // Step 3: Client edits title @ t=60
        try await withDependencies {
          $0.currentTime.now = 60
        } operation: {
          try await userDatabase.userWrite { db in
            try Post.find(1).update { $0.title = "Hello from client" }.execute(db)
          }
        }

        // Step 4: Fetch arrives (conflict, merged locally)
        await fetchedRecordZoneChangesCallback.notify()
        
        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello from server",
                title🗓️: 30,
                🗓️: 30
              )
            ]
          )
          """
        }

        // Step 5: Send (merged result)
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertQuery(
          Post.find(1)
            .join(SyncMetadata.all) { $0.syncMetadataID.eq($1.id) }
            .select { ($0, $1.userModificationTime) },
          database: userDatabase.database
        ) {
          """
          ┌───────────────────────────────┬────┐
          │ Post(                         │ 60 │
          │   id: 1,                      │    │
          │   title: "Hello from client", │    │
          │   body: nil,                  │    │
          │   isPublished: false          │    │
          │ )                             │    │
          └───────────────────────────────┴────┘
          """
        }
        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello from client",
                title🗓️: 60,
                🗓️: 60
              )
            ]
          )
          """
        }
      }

      @Test func sameFieldChange_conflictOnFetch_serverNewer() async throws {
        // Step 1: Seed and initial sync
        try await userDatabase.userWrite { db in
          try db.seed { Post(id: 1, title: "Hello") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello",
                title🗓️: 0,
                🗓️: 0
              )
            ]
          )
          """
        }

        // Step 2: Client edits title @ t=30
        try await withDependencies {
          $0.currentTime.now = 30
        } operation: {
          try await userDatabase.userWrite { db in
            try Post.find(1).update { $0.title = "Hello from client" }.execute(db)
          }
        }

        // Step 3: Server edits title @ t=60
        let record = try syncEngine.private.database.record(for: Post.recordID(for: 1))
        record.setValue("Hello from server", forKey: "title", at: 60)
        let fetchedRecordZoneChangesCallback = try syncEngine.modifyRecords(
          scope: .private,
          saving: [record]
        )

        // Step 4: Fetch arrives (conflict, merged locally)
        await fetchedRecordZoneChangesCallback.notify()

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello from server",
                title🗓️: 60,
                🗓️: 60
              )
            ]
          )
          """
        }

        // Step 5: Send (merged result)
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        await withKnownIssue("Server should win same-field conflict when it has a newer timestamp") {
          try await userDatabase.read { db in
            let post = try #require(try Post.find(1).fetchOne(db))
            #expect(post.title == "Hello from server")
          }
        }
      }

      // MARK: - Same Field Change & Removal

      @Test func sameFieldChangeAndRemoval_conflictOnSend_clientNewer() async throws {
        // Step 1: Seed with body and initial sync
        try await userDatabase.userWrite { db in
          try db.seed { Post(id: 1, title: "Hello", body: "Original body") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body: "Original body",
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello",
                title🗓️: 0,
                🗓️: 0
              )
            ]
          )
          """
        }

        // Step 2: Server changes body @ t=30
        let record = try syncEngine.private.database.record(for: Post.recordID(for: 1))
        record.setValue("Server body", forKey: "body", at: 30)
        let fetchedRecordZoneChangesCallback = try syncEngine.modifyRecords(
          scope: .private,
          saving: [record]
        )

        // Step 3: Client nulls body @ t=60
        try await withDependencies {
          $0.currentTime.now = 60
        } operation: {
          try await userDatabase.userWrite { db in
            try Post.find(1).update { $0.body = #bind(nil as String?) }.execute(db)
          }
        }

        // Step 4: Send (rejected, merged locally)
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body: "Server body",
                body🗓️: 30,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello",
                title🗓️: 0,
                🗓️: 30
              )
            ]
          )
          """
        }

        // Step 5: Retry send
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        // Step 6: Fetch arrives (no-op, conflict already resolved)
        await fetchedRecordZoneChangesCallback.notify()

        assertQuery(
          Post.find(1)
            .join(SyncMetadata.all) { $0.syncMetadataID.eq($1.id) }
            .select { ($0, $1.userModificationTime) },
          database: userDatabase.database
        ) {
          """
          ┌──────────────────────┬────┐
          │ Post(                │ 60 │
          │   id: 1,             │    │
          │   title: "Hello",    │    │
          │   body: nil,         │    │
          │   isPublished: false │    │
          │ )                    │    │
          └──────────────────────┴────┘
          """
        }
        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 60,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello",
                title🗓️: 0,
                🗓️: 60
              )
            ]
          )
          """
        }
      }

      @Test func sameFieldChangeAndRemoval_conflictOnSend_serverNewer() async throws {
        // Step 1: Seed with body and initial sync
        try await userDatabase.userWrite { db in
          try db.seed { Post(id: 1, title: "Hello", body: "Original body") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body: "Original body",
                body🗓️: 0,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello",
                title🗓️: 0,
                🗓️: 0
              )
            ]
          )
          """
        }

        // Step 2: Client nulls body @ t=30
        try await withDependencies {
          $0.currentTime.now = 30
        } operation: {
          try await userDatabase.userWrite { db in
            try Post.find(1).update { $0.body = #bind(nil as String?) }.execute(db)
          }
        }

        // Step 3: Server changes body @ t=60
        let record = try syncEngine.private.database.record(for: Post.recordID(for: 1))
        record.setValue("Server body", forKey: "body", at: 60)
        let fetchedRecordZoneChangesCallback = try syncEngine.modifyRecords(
          scope: .private,
          saving: [record]
        )

        // Step 4: Send (rejected, merged locally)
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body: "Server body",
                body🗓️: 60,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello",
                title🗓️: 0,
                🗓️: 60
              )
            ]
          )
          """
        }

        // Step 5: Retry send
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        // Step 6: Fetch arrives (no-op, conflict already resolved)
        await fetchedRecordZoneChangesCallback.notify()

        await withKnownIssue("Server should win same-field conflict when it has a newer timestamp") {
          try await userDatabase.read { db in
            let post = try #require(try Post.find(1).fetchOne(db))
            #expect(post.body == "Server body")
          }
        }
      }

      @Test func sameFieldRemoval_conflictOnSend_clientNewer() async throws {
        // Step 1: Seed with body and initial sync
        try await userDatabase.userWrite { db in
          try db.seed { Post(id: 1, title: "Hello", body: "Original body") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        // Step 2: Server nulls body @ t=30
        let record = try syncEngine.private.database.record(for: Post.recordID(for: 1))
        record.removeValue(forKey: "body", at: 30)
        let fetchedRecordZoneChangesCallback = try syncEngine.modifyRecords(
          scope: .private,
          saving: [record]
        )

        // Step 3: Client nulls body @ t=60
        try await withDependencies {
          $0.currentTime.now = 60
        } operation: {
          try await userDatabase.userWrite { db in
            try Post.find(1).update { $0.body = #bind(nil as String?) }.execute(db)
          }
        }

        // Step 4: Send (rejected, merged locally)
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        // Step 5: Retry send
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        // Step 6: Fetch arrives (no-op, conflict already resolved)
        await fetchedRecordZoneChangesCallback.notify()

        assertQuery(
          Post.find(1)
            .join(SyncMetadata.all) { $0.syncMetadataID.eq($1.id) }
            .select { ($0, $1.userModificationTime) },
          database: userDatabase.database
        ) {
          """
          ┌──────────────────────┬────┐
          │ Post(                │ 60 │
          │   id: 1,             │    │
          │   title: "Hello",    │    │
          │   body: nil,         │    │
          │   isPublished: false │    │
          │ )                    │    │
          └──────────────────────┴────┘
          """
        }
        withKnownIssue("Per-field timestamp should reflect the newer removal") {
          let recordID = Post.recordID(for: 1)
          let record = try syncEngine.private.database.record(for: recordID)
          #expect(record.encryptedValues[at: "body"] == 60)
        }
      }

      @Test func sameFieldRemoval_conflictOnSend_serverNewer() async throws {
        // Step 1: Seed with body and initial sync
        try await userDatabase.userWrite { db in
          try db.seed { Post(id: 1, title: "Hello", body: "Original body") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        // Step 2: Server nulls body @ t=60
        let record = try syncEngine.private.database.record(for: Post.recordID(for: 1))
        record.removeValue(forKey: "body", at: 60)
        let fetchedRecordZoneChangesCallback = try syncEngine.modifyRecords(
          scope: .private,
          saving: [record]
        )

        // Step 3: Client nulls body @ t=30
        try await withDependencies {
          $0.currentTime.now = 30
        } operation: {
          try await userDatabase.userWrite { db in
            try Post.find(1).update { $0.body = #bind(nil as String?) }.execute(db)
          }
        }

        // Step 4: Send (rejected, merged locally)
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        // Step 5: Retry send
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        // Step 6: Fetch arrives (no-op, conflict already resolved)
        await fetchedRecordZoneChangesCallback.notify()

        assertQuery(
          Post.find(1)
            .join(SyncMetadata.all) { $0.syncMetadataID.eq($1.id) }
            .select { ($0, $1.userModificationTime) },
          database: userDatabase.database
        ) {
          """
          ┌──────────────────────┬────┐
          │ Post(                │ 60 │
          │   id: 1,             │    │
          │   title: "Hello",    │    │
          │   body: nil,         │    │
          │   isPublished: false │    │
          │ )                    │    │
          └──────────────────────┴────┘
          """
        }
        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:posts/zone/__defaultOwner__),
                recordType: "posts",
                parent: nil,
                share: nil,
                body🗓️: 60,
                id: 1,
                id🗓️: 0,
                isPublished: 0,
                isPublished🗓️: 0,
                title: "Hello",
                title🗓️: 0,
                🗓️: 60
              )
            ]
          )
          """
        }
      }
    }
  }
#endif
