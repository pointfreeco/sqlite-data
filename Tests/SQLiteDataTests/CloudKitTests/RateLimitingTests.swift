#if canImport(CloudKit)
  import Clocks
  import CloudKit
  import ConcurrencyExtras
  import Dependencies
  import SQLiteData
  import Testing
  import TestLocals

  extension BaseCloudKitTests {
    @MainActor
    @Suite(.taskLocal($rateLimitDuration, .seconds(10)))
    final class RateLimitingTests: BaseCloudKitTests, @unchecked Sendable {
      let recordID = CKRecord.ID(
        recordName: "A",
        zoneID: SyncEngine.defaultTestZone.zoneID
      )

      var database: MockCloudDatabase {
        syncEngine.private.database
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      override init() async throws {
        try await super.init()
        try $_isRateLimitingDisabled.withValue(true) {
          _ = try database.modifyRecords(
            saving: [CKRecord(recordType: "A", recordID: recordID)],
            deleting: []
          )
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func notRateLimited() async throws {
        let record = try await withRateLimiting {
          try database.record(for: recordID)
        }
        #expect(record.recordID == recordID)
      }

      @available(iOS 26, macOS 26, tvOS 26, watchOS 26, *)
      @Test(.taskLocal($rateLimit, 1))
      func sleepsForRetryAfterSecondsThenRetries() async throws {
        _ = try database.record(for: recordID)

        let attempts = LockIsolated(0)
        let task = Task.immediate {
          try await withRateLimiting {
            attempts.withValue { $0 += 1 }
            return try database.record(for: recordID).recordID
          }
        }

        await cloudKitClock.advance(by: .seconds(9))
        #expect(attempts.value == 1)

        await cloudKitClock.advance(by: .seconds(1))
        #expect(try await task.value == recordID)
        #expect(attempts.value == 2)
      }

      @available(iOS 26, macOS 26, tvOS 26, watchOS 26, *)
      @Test(.taskLocal($rateLimit, 0))
      func rethrowsAfterMaxRetries() async throws {
        let attempts = LockIsolated(0)
        let task = Task.immediate {
          try await withRateLimiting(maxRetries: 2) {
            attempts.withValue { $0 += 1 }
            return try database.record(for: recordID).recordID
          }
        }

        await cloudKitClock.advance(by: .seconds(10))
        #expect(attempts.value == 2)
        await cloudKitClock.advance(by: .seconds(10))
        #expect(attempts.value == 3)

        let error = await #expect(throws: CKError.self) {
          try await task.value
        }
        #expect(error?.code == .requestRateLimited)
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test(.taskLocal($rateLimit, 0))
      func noRetries() async throws {
        let attempts = LockIsolated(0)
        let error = await #expect(throws: CKError.self) {
          try await withRateLimiting(maxRetries: 0) {
            attempts.withValue { $0 += 1 }
            return try database.record(for: self.recordID)
          }
        }
        #expect(error?.code == .requestRateLimited)
        #expect(attempts.value == 1)
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func otherErrorsAreNotRetried() async throws {
        let missingRecordID = CKRecord.ID(recordName: "B", zoneID: recordID.zoneID)
        let attempts = LockIsolated(0)
        let error = await #expect(throws: CKError.self) {
          try await withRateLimiting {
            attempts.withValue { $0 += 1 }
            return try database.record(for: missingRecordID)
          }
        }
        #expect(error?.code == .unknownItem)
        #expect(attempts.value == 1)
      }

      @available(iOS 26, macOS 26, tvOS 26, watchOS 26, *)
      @Test(arguments: [CKError.Code.requestRateLimited, .serviceUnavailable])
      func retriesAfterRetryAfterSeconds(code: CKError.Code) async throws {
        let attempts = LockIsolated(0)
        let task = Task.immediate {
          try await withRateLimiting {
            let attempt = attempts.withValue {
              $0 += 1
              return $0
            }
            guard attempt > 1
            else { throw CKError(code, userInfo: [CKErrorRetryAfterKey: 3.0]) }
          }
        }

        await cloudKitClock.advance(by: .milliseconds(2999))
        #expect(attempts.value == 1)

        await cloudKitClock.advance(by: .milliseconds(1))
        try await task.value
        #expect(attempts.value == 2)
      }

      @available(iOS 26, macOS 26, tvOS 26, watchOS 26, *)
      @Test func defaultsToOneSecondWithoutRetryAfterSeconds() async throws {
        let attempts = LockIsolated(0)
        let task = Task.immediate {
          try await withRateLimiting {
            let attempt = attempts.withValue {
              $0 += 1
              return $0
            }
            guard attempt > 1
            else { throw CKError(.requestRateLimited) }
          }
        }

        await cloudKitClock.advance(by: .milliseconds(999))
        #expect(attempts.value == 1)

        await cloudKitClock.advance(by: .milliseconds(1))
        try await task.value
        #expect(attempts.value == 2)
      }

      @available(iOS 26, macOS 26, tvOS 26, watchOS 26, *)
      @Test(.taskLocal($rateLimit, 0))
      func cancellationWhileSleeping() async throws {
        let attempts = LockIsolated(0)
        let task = Task.immediate {
          try await withRateLimiting {
            attempts.withValue { $0 += 1 }
            return try database.record(for: recordID).recordID
          }
        }

        await cloudKitClock.advance(by: .seconds(1))
        task.cancel()

        await #expect(throws: CancellationError.self) {
          try await task.value
        }
        #expect(attempts.value == 1)
      }
    }
  }
#endif
