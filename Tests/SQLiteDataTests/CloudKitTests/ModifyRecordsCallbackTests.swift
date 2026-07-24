#if canImport(CloudKit)
  import CloudKit
  import SQLiteData
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class ModifyRecordsCallbackTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func deferredCallbackDeliversLatestRecords() async throws {
        try await userDatabase.userWrite { db in
          try db.seed { RemindersList(id: 1, title: "Original") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let firstRecord = try syncEngine.private.database.record(
          for: RemindersList.recordID(for: 1)
        )
        firstRecord.setValue("First", forKey: "title", at: 30)
        let callback = try syncEngine.modifyRecords(scope: .private, saving: [firstRecord])

        let secondRecord = try syncEngine.private.database.record(
          for: RemindersList.recordID(for: 1)
        )
        secondRecord.setValue("Second", forKey: "title", at: 60)
        _ = try syncEngine.modifyRecords(scope: .private, saving: [secondRecord])

        await callback.notify()

        let title = try await userDatabase.database.read { db in
          try RemindersList.find(1).select(\.title).fetchOne(db)
        }
        #expect(title == "Second")
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func deferredCallbackSkipsDeletionOfReSavedRecord() async throws {
        try await userDatabase.userWrite { db in
          try db.seed { RemindersList(id: 1, title: "Original") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let recordID = RemindersList.recordID(for: 1)

        let callback = try syncEngine.modifyRecords(
          scope: .private,
          deleting: [recordID]
        )

        let revivedRecord = CKRecord(
          recordType: RemindersList.tableName,
          recordID: recordID
        )
        revivedRecord.setValue("Revived", forKey: "title", at: 30)
        _ = try syncEngine.modifyRecords(scope: .private, saving: [revivedRecord])

        await callback.notify()

        let title = try await userDatabase.database.read { db in
          try RemindersList.find(1).select(\.title).fetchOne(db)
        }
        // NB: The deletion is skipped and the revival's callback isn't notified at this point,
        //     so the local record stays untouched.
        #expect(title == "Original")
      }
    }
  }
#endif
