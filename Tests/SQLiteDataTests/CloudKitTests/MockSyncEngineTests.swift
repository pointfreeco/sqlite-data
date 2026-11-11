#if canImport(CloudKit)
  import CloudKit
  import Dependencies
  import SQLiteData
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class MockSyncEngineTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func `fetching changes does not mutate database`() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 30
        } operation: {
          try await userDatabase.userWrite { db in
            try RemindersList.find(1).update { $0.title = "Family" }.execute(db)
          }
        }

        let before = try syncEngine.private.database.record(
          for: RemindersList.recordID(for: 1)
        )
        #expect(before.userModificationTime == 0)

        try await syncEngine.private.fetchChanges(CKSyncEngine.FetchChangesOptions())

        let after = try syncEngine.private.database.record(
          for: RemindersList.recordID(for: 1)
        )
        #expect(after.userModificationTime == 0)
        #expect(after.encryptedValues["title"] as? String == "Personal")

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func `untracked changes ask delegate for next batch`() async throws {
        #expect(syncEngine.private.state.pendingRecordZoneChanges.isEmpty)
        syncEngine.private.state.hasPendingUntrackedChanges = true

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        #expect(!syncEngine.private.state.hasPendingUntrackedChanges)
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func `sendChanges sends when only untracked changes are pending`() async throws {
        syncEngine.private.state.hasPendingUntrackedChanges = true

        try await syncEngine.private.sendChanges(CKSyncEngine.SendChangesOptions())

        #expect(!syncEngine.private.state.hasPendingUntrackedChanges)
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func `untracked changes flag clears once delegate has nothing to send`() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
          }
        }
        syncEngine.private.state.hasPendingUntrackedChanges = true

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        let record = try syncEngine.private.database.record(for: RemindersList.recordID(for: 1))
        #expect(record.encryptedValues["title"] as? String == "Personal")
        #expect(syncEngine.private.state.hasPendingUntrackedChanges)

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        #expect(!syncEngine.private.state.hasPendingUntrackedChanges)
      }

      @Test func isNewerChangeTag() {
        #expect("0".isNewerChangeTag(than: nil))

        #expect(!"0".isNewerChangeTag(than: "0"))
        #expect(!"z".isNewerChangeTag(than: "z"))

        #expect("1".isNewerChangeTag(than: "0"))
        #expect(!"0".isNewerChangeTag(than: "1"))
        #expect("a".isNewerChangeTag(than: "9"))
        #expect(!"9".isNewerChangeTag(than: "a"))
        #expect("z".isNewerChangeTag(than: "a"))

        #expect("10".isNewerChangeTag(than: "z"))
        #expect(!"z".isNewerChangeTag(than: "10"))
        #expect("100".isNewerChangeTag(than: "zz"))
        #expect(!"zz".isNewerChangeTag(than: "100"))
      }
    }
  }
#endif
