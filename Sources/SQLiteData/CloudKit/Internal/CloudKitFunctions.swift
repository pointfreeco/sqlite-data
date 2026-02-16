#if canImport(CloudKit)
  import CloudKit
  import Foundation

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
#endif
