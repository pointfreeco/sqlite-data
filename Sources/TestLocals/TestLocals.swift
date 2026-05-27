#if canImport(CloudKit)
  import CloudKit
  import Testing
  import SQLiteData

  @TaskLocal package var prepareDatabase: @Sendable (UserDatabase) async throws -> Void = { _ in }
  @TaskLocal package var startImmediately = true
  @TaskLocal package var attachMetadatabase = false
  @TaskLocal package var accountStatus = CKAccountStatus.available
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @TaskLocal package var syncEngineDelegate: (any SyncEngineDelegate)? = nil
#endif
