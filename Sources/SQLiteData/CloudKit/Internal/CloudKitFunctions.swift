#if canImport(CloudKit)
  import CloudKit
  import Foundation

// TODO: Move this to SyncEngine so that we don't have to use `@Dependency`
  @DatabaseFunction("sqlitedata_icloud_currentTime")
  func currentTime() -> Int64 {
    @Dependency(\.currentTime.now) var now
    return now
  }

  @DatabaseFunction(
    "sqlitedata_icloud_hasPermission",
    as: ((CKShare?.SystemFieldsRepresentation) -> Bool).self,
    isDeterministic: true
  )
  func hasPermission(_ share: CKShare?) -> Bool {
    guard let share else { return true }
    return share.publicPermission == .readWrite
      || share.currentUserParticipant?.permission == .readWrite
  }

  @DatabaseFunction("sqlitedata_icloud_syncEngineIsSynchronizingChanges")
  func syncEngineIsSynchronizingChanges() -> Bool {
    _isSynchronizingChanges
  }
#endif
