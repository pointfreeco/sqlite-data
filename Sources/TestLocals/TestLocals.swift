#if canImport(CloudKit)
  package import CloudKit
  package import SQLiteData
  import Testing

  @TaskLocal package var prepareDatabase: @Sendable (UserDatabase) async throws -> Void = { _ in }
  @TaskLocal package var startImmediately = true
  @TaskLocal package var attachMetadatabase = false
  @TaskLocal package var accountStatus = CKAccountStatus.available
  @TaskLocal package var rateLimit = Int.max
  @TaskLocal package var rateLimitDuration = Duration.seconds(1)
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @TaskLocal package var syncEngineDelegate: (any SyncEngineDelegate)? = nil
#endif
