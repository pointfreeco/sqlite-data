#if canImport(CloudKit)
  import CloudKit
  @testable import SQLiteData
  import Testing

  @Suite
  struct MockSystemFieldsTests {
    @Test func modificationDateOverride() {
      let record = CKRecord(recordType: "record", recordID: CKRecord.ID(recordName: "A"))
      #expect(record.modificationDate == nil)

      record._modificationDate = Date(timeIntervalSinceReferenceDate: 1)
      #expect(record.modificationDate == Date(timeIntervalSinceReferenceDate: 1))
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func systemFieldsRepresentationRoundtrip() throws {
      let record = CKRecord(recordType: "record", recordID: CKRecord.ID(recordName: "A"))
      record._recordChangeTag = 42
      record._modificationDate = Date(timeIntervalSinceReferenceDate: 1)

      let representation = CKRecord.SystemFieldsRepresentation(queryOutput: record)
      let result = try #require(CKRecord.SystemFieldsRepresentation(queryBinding: representation.queryBinding))

      #expect(result.queryOutput._recordChangeTag == 42)
      #expect(result.queryOutput._modificationDate == Date(timeIntervalSinceReferenceDate: 1))
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func allFieldsRepresentationRoundtrip() throws {
      let record = CKRecord(recordType: "record", recordID: CKRecord.ID(recordName: "A"))
      record._recordChangeTag = 42
      record._modificationDate = Date(timeIntervalSinceReferenceDate: 1)

      let representation = CKRecord._AllFieldsRepresentation(queryOutput: record)
      let result = try #require(CKRecord._AllFieldsRepresentation(queryBinding: representation.queryBinding))

      #expect(result.queryOutput._recordChangeTag == 42)
      #expect(result.queryOutput._modificationDate == Date(timeIntervalSinceReferenceDate: 1))
    }
  }
#endif
