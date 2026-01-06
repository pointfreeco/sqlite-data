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
          syncEngine.tablesByOrder == ["remindersListPrivates": 11, "childWithOnDeleteSetNulls": 6, "reminders": 1, "modelAs": 8, "remindersLists": 0, "reminderTags": 4, "modelBs": 9, "parents": 5, "childWithOnDeleteSetDefaults": 7, "modelCs": 10, "remindersListAssets": 2, "tags": 3]
        )
      }
    }
  }
#endif
