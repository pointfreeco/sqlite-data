import SQLiteData

#if canImport(CloudKit)
  import CloudKit
#endif

private final class Model {
  @FetchAll var titles: [String]

  init() {
    _titles = FetchAll(Reminder.select(\.title))
  }
}

#if canImport(CloudKit)
  @Table
  struct RepresentableFields {
    @Column(as: CKShare.SystemFieldsRepresentation.self)
    var share: CKShare
    @Column(as: CKShare?.SystemFieldsRepresentation.self)
    var optionalShare: CKShare?
    @Column(as: CKRecord.SystemFieldsRepresentation.self)
    var record: CKRecord
    @Column(as: CKRecord?.SystemFieldsRepresentation.self)
    var optionalRecord: CKRecord?
  }

  @DatabaseFunction(
    as: ((
      CKShare.SystemFieldsRepresentation,
      CKRecord.SystemFieldsRepresentation,
      CKShare?.SystemFieldsRepresentation,
      CKRecord?.SystemFieldsRepresentation
    ) -> Void).self
  )
  nonisolated func representableArguments(
    share: CKShare,
    record: CKRecord,
    optionalShare: CKShare?,
    optionalRecord: CKRecord?
  ) {
  }
#endif
