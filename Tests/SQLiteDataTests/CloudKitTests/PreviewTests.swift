#if canImport(CloudKit)
  import DependenciesTestSupport
  import InlineSnapshotTesting
  import SnapshotTestingCustomDump
  import SQLiteData
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    @Suite(.dependencies { $0.context = .preview })
    final class PreviewTests: BaseCloudKitTests, @unchecked Sendable {
      @Test
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      func autoSyncChangesInPreviews() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
          }
        }
        await testClock.advance(by: .seconds(1))
        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  title: "Personal"
                )
              ]
            ),
            sharedCloudDatabase: MockCloudDatabase(
              databaseScope: .shared,
              storage: []
            )
          )
          """
        }
      }

      @Test
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      func delete() async throws {
        @FetchAll(RemindersList.all, database: userDatabase.database) var remindersLists

        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
          }
        }

        await testClock.advance(by: .seconds(1))
        try await $remindersLists.load()
        #expect(remindersLists.count == 1)
        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  title: "Personal"
                )
              ]
            ),
            sharedCloudDatabase: MockCloudDatabase(
              databaseScope: .shared,
              storage: []
            )
          )
          """
        }

        try await userDatabase.userWrite { db in
          try RemindersList.delete().execute(db)
        }
        try await $remindersLists.load()
        #expect(remindersLists.count == 0)

        await testClock.advance(by: .seconds(1))
        #expect(remindersLists.count == 0)
        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: []
            ),
            sharedCloudDatabase: MockCloudDatabase(
              databaseScope: .shared,
              storage: []
            )
          )
          """
        }
      }
    }
  }
#endif
