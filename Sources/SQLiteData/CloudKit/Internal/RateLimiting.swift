#if canImport(CloudKit)
  import CloudKit
  import Dependencies

  @available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
  package func withRateLimiting<R>(
    maxRetries: Int = 5,
    operation: () async throws -> R
  ) async throws -> R {
    @Dependency(\.cloudKitClock) var clock
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
