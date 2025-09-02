#if canImport(CloudKit)
  import Foundation

  @DatabaseFunction("sqlitedata_icloud_datetime")
  func datetime() -> Date {
    @Dependency(\.datetime.now) var now
    return now
  }
#endif
