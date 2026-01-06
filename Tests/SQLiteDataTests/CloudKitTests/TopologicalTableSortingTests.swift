#if canImport(CloudKit)
  import CloudKit
  import SQLiteData
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class TopologicalTableSortingTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func tablesByOrder() async throws {
        #expect(
          syncEngine.tablesByOrder == [
            "remindersLists": 0,
            "reminders": 1,
            "remindersListAssets": 2,
            "tags": 3,
            "reminderTags": 4,
            "parents": 5,
            "childWithOnDeleteSetNulls": 6,
            "childWithOnDeleteSetDefaults": 7,
            "modelAs": 8,
            "modelBs": 9,
            "modelCs": 10,
            "remindersListPrivates": 11,
          ]
        )
      }
    }
  }
#endif
