#if canImport(CloudKit)
  import CloudKit
  import Dependencies

  package func withRateLimiting<R>(
    maxRetries: Int = 5,
    operation: () async throws -> R
  ) async throws -> R {
    @Dependency(\.continuousClock) var clock
    var retries = 0
    while true {
      do {
        return try await operation()
      } catch let error as CKError where error.code == .requestRateLimited && retries < maxRetries {
        retries += 1
        try await clock.sleep(for: .seconds(error.retryAfterSeconds ?? 1))
      }
    }
  }
#endif
