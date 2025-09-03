#if canImport(CloudKit)
  import CloudKit
  import Foundation

  @DatabaseFunction("sqlitedata_icloud_datetime")
  func datetime() -> Date {
    @Dependency(\.datetime.now) var now
    return now
  }

  @DatabaseFunction(
    "sqlitedata_icloud_hasPermission",
    as: ((CKShare?.SystemFieldsRepresentation) -> Bool).self
  )
  func hasPermission(_ share: CKShare?) -> Bool {
    guard let share else { return true }
    return share.publicPermission == .readWrite
      || share.currentUserParticipant?.permission == .readWrite
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @DatabaseFunction("sqlitedata_icloud_syncEngineIsSynchronizingChanges")
  func syncEngineIsSynchronizingChanges() -> Bool {
    SyncEngine._isSynchronizingChanges
  }
#endif
