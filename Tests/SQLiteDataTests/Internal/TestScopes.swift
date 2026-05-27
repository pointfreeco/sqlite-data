#if canImport(CloudKit)
  import CloudKit
  import Testing
  import SQLiteData

  var prepareDatabase: @Sendable (UserDatabase) async throws -> Void {
    _$prepareDatabase.get()
  }
  let _$prepareDatabase = TaskLocal<@Sendable (UserDatabase) async throws -> Void>(
    wrappedValue: { _ in }
  )

  var startImmediately: Bool {
    _$startImmediately.get()
  }
  let _$startImmediately = TaskLocal(wrappedValue: true)

  var attachMetadatabase: Bool {
    _$attachMetadatabase.get()
  }
  let _$attachMetadatabase = TaskLocal(wrappedValue: false)

  var accountStatus: CKAccountStatus {
    _$accountStatus.get()
  }
  let _$accountStatus = TaskLocal(wrappedValue: CKAccountStatus.available)

  var syncEngineDelegate: (any SyncEngineDelegate)? {
    _$syncEngineDelegate.get()
  }
  let _$syncEngineDelegate = TaskLocal<(any SyncEngineDelegate)?>(wrappedValue: nil)
#endif
