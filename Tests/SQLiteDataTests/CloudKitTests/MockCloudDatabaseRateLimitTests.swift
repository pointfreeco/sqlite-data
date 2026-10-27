#if canImport(CloudKit)
  import Clocks
  import CloudKit
  import ConcurrencyExtras
  import Dependencies
  import SQLiteData
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class MockCloudDatabaseRateLimitTests: BaseCloudKitTests, @unchecked Sendable {
      let recordID = CKRecord.ID(
        recordName: "A",
        zoneID: CKRecordZone.ID(zoneName: "zone")
      )

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func unlimitedByDefault() async throws {
        let database = try createDatabase()
        for _ in 1...1_000 {
          _ = try database.record(for: recordID)
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func rateLimitedOnceLimitReached() async throws {
        let database = try createDatabase(rateLimit: 3, rateLimitDuration: .seconds(10))

        for _ in 1...3 {
          _ = try database.record(for: recordID)
        }
        let error = #expect(throws: CKError.self) {
          try database.record(for: self.recordID)
        }
        #expect(error?.code == .requestRateLimited)
        #expect(error?.retryAfterSeconds == 10)
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func zeroLimit() async throws {
        let database = try createDatabase(rateLimit: 0, rateLimitDuration: .seconds(10))

        let error = #expect(throws: CKError.self) {
          try database.record(for: self.recordID)
        }
        #expect(error?.code == .requestRateLimited)
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func rateLimitResetsAfterDuration() async throws {
        let database = try createDatabase(rateLimit: 2, rateLimitDuration: .seconds(10))

        _ = try database.record(for: recordID)
        _ = try database.record(for: recordID)
        #expect(throws: CKError.self) { try database.record(for: self.recordID) }

        await testClock.advance(by: .seconds(10))
        _ = try database.record(for: recordID)
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func slidingWindow() async throws {
        let database = try createDatabase(rateLimit: 2, rateLimitDuration: .seconds(10))

        _ = try database.record(for: recordID)
        await testClock.advance(by: .seconds(5))
        _ = try database.record(for: recordID)

        await testClock.advance(by: .seconds(5))
        _ = try database.record(for: recordID)
        #expect(throws: CKError.self) { try database.record(for: self.recordID) }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func rejectedRequestsCountAgainstRateLimit() async throws {
        let database = try createDatabase(rateLimit: 1, rateLimitDuration: .seconds(10))

        _ = try database.record(for: recordID)
        await testClock.advance(by: .seconds(5))
        #expect(throws: CKError.self) { try database.record(for: self.recordID) }

        await testClock.advance(by: .seconds(5))
        #expect(throws: CKError.self) { try database.record(for: self.recordID) }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func waitingRetryAfterSecondsSucceeds() async throws {
        let database = try createDatabase(rateLimit: 3, rateLimitDuration: .seconds(10))

        for _ in 1...3 {
          _ = try database.record(for: recordID)
        }
        for _ in 1...5 {
          await testClock.advance(by: .seconds(1))
          #expect(throws: CKError.self) { try database.record(for: self.recordID) }
        }
        let error = #expect(throws: CKError.self) {
          try database.record(for: self.recordID)
        }
        let retryAfterSeconds = try #require(error?.retryAfterSeconds)

        await testClock.advance(by: .seconds(retryAfterSeconds))
        _ = try database.record(for: recordID)
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func allRequestsShareRateLimit() async throws {
        let database = try createDatabase(rateLimit: 4, rateLimitDuration: .seconds(10))

        _ = try database.record(for: recordID)
        _ = try database.records(for: [recordID], desiredKeys: nil)
        _ = try database.modifyRecords(saving: [], deleting: [])
        _ = try database.modifyRecordZones(saving: [], deleting: [])

        let errors = [
          #expect(throws: CKError.self) {
            try database.record(for: self.recordID)
          },
          #expect(throws: CKError.self) {
            try database.records(for: [self.recordID], desiredKeys: nil)
          },
          #expect(throws: CKError.self) {
            try database.modifyRecords(saving: [], deleting: [])
          },
          #expect(throws: CKError.self) {
            try database.modifyRecordZones(saving: [], deleting: [])
          },
        ]
        #expect(errors.map(\.?.code) == Array(repeating: .requestRateLimited, count: 4))
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func batchFetchCountsAsSingleRequest() async throws {
        let database = try createDatabase(rateLimit: 2, rateLimitDuration: .seconds(10))

        let recordIDs = Array(repeating: recordID, count: 10)
        let results = try database.records(for: recordIDs, desiredKeys: nil)
        #expect(results.values.allSatisfy { (try? $0.get()) != nil })
        _ = try database.records(for: recordIDs, desiredKeys: nil)
        #expect(throws: CKError.self) {
          try database.records(for: recordIDs, desiredKeys: nil)
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func limitExceededCountsAgainstRateLimit() async throws {
        let database = try createDatabase(rateLimit: 1, rateLimitDuration: .seconds(10))

        let error = #expect(throws: CKError.self) {
          try database.records(
            for: Array(repeating: self.recordID, count: 200),
            desiredKeys: nil
          )
        }
        #expect(error?.code == .limitExceeded)
        #expect(throws: CKError.self) { try database.record(for: self.recordID) }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func rateLimitingDisabled() async throws {
        let database = try createDatabase(rateLimit: 1, rateLimitDuration: .seconds(10))

        try $_isRateLimitingDisabled.withValue(true) {
          for _ in 1...10 {
            _ = try database.record(for: recordID)
          }
        }
        _ = try database.record(for: recordID)
        #expect(throws: CKError.self) { try database.record(for: self.recordID) }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func syncEngineIsExempt() async throws {
        syncEngine.private.database.state.withValue {
          $0.rateLimit = 0
          $0.rateLimitDuration = .seconds(10)
        }

        try await userDatabase.userWrite { db in
          try RemindersList.insert { RemindersList(id: 1, title: "Personal") }.execute(db)
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let remoteRecord = CKRecord(
          recordType: RemindersList.tableName,
          recordID: RemindersList.recordID(for: 2)
        )
        remoteRecord.setValue(2, forKey: "id", at: now)
        remoteRecord.setValue("Business", forKey: "title", at: now)
        try await syncEngine.modifyRecords(scope: .private, saving: [remoteRecord]).notify()

        let storedRecordIDs = syncEngine.private.database.state.withValue {
          Set($0.storage.values.flatMap(\.records.keys))
        }
        #expect(storedRecordIDs.contains(RemindersList.recordID(for: 1)))
        try await userDatabase.read { db in
          try #expect(RemindersList.fetchCount(db) == 2)
        }
        #expect(throws: CKError.self) {
          try self.syncEngine.private.database.record(for: RemindersList.recordID(for: 1))
        }
      }

      private func createDatabase(
        rateLimit: Int = .max,
        rateLimitDuration: Duration = .seconds(Int64.max)
      ) throws -> MockCloudDatabase {
        let database = MockCloudDatabase(
          databaseScope: .private,
          rateLimit: rateLimit,
          rateLimitDuration: rateLimitDuration
        )
        database.set(container: container)
        try $_isRateLimitingDisabled.withValue(true) {
          _ = try database.modifyRecordZones(
            saving: [CKRecordZone(zoneID: recordID.zoneID)],
            deleting: []
          )
          _ = try database.modifyRecords(
            saving: [CKRecord(recordType: "A", recordID: recordID)],
            deleting: []
          )
        }
        return database
      }
    }
  }
#endif
