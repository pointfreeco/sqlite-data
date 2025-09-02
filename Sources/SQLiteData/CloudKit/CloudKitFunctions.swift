#if canImport(CloudKit)
  import Foundation

  @DatabaseFunction("sqlitedata_icloud_datetime")
  func datetime() -> Date {
    @Dependency(\.datetime.now) var now
    return now
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @DatabaseFunction("sqlitedata_icloud_syncEngineIsSynchronizingChanges")
  func syncEngineIsSynchronizingChanges() -> Bool {
    SyncEngine._isSynchronizingChanges
  }
#endif
