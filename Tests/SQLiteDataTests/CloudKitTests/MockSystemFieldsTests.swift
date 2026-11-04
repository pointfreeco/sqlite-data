#if canImport(CloudKit)
  import CloudKit
  import SQLiteData
  import Testing

  @Suite struct MockSystemFieldsTests {
    @Test func systemFieldsOverride() {
      let record = CKRecord(recordType: "A", recordID: CKRecord.ID(recordName: "A"))
      #expect(record.recordChangeTag == nil)
      #expect(record.modificationDate == nil)

      let mocked = record.copyWithMockSystemFields(
        recordChangeTag: "ab",
        modificationDate: Date(timeIntervalSinceReferenceDate: 1)
      )

      #expect(mocked.recordChangeTag == "ab")
      #expect(mocked.modificationDate == Date(timeIntervalSinceReferenceDate: 1))
    }

    @Test func systemFieldsOverridePreservesValues() {
      let record = CKRecord(recordType: "A", recordID: CKRecord.ID(recordName: "A"))
      record["unencryptedValue"] = 42
      record.encryptedValues["encryptedValue"] = 42

      let mocked = record.copyWithMockSystemFields(
        recordChangeTag: "ab",
        modificationDate: Date(timeIntervalSinceReferenceDate: 1)
      )

      #expect(mocked["unencryptedValue"] as? Int == 42)
      #expect(mocked.encryptedValues["encryptedValue"] as? Int == 42)
    }

    @Test func systemFieldsOverrideOnShare() {
      let share = CKShare(
        rootRecord: CKRecord(recordType: "A", recordID: CKRecord.ID(recordName: "A"))
      )

      let mocked = share.copyWithMockSystemFields(
        recordChangeTag: "ab",
        modificationDate: Date(timeIntervalSinceReferenceDate: 1)
      )

      #expect(mocked.recordChangeTag == "ab")
      #expect(mocked.modificationDate == Date(timeIntervalSinceReferenceDate: 1))
    }

    @Test func subsequentSystemFieldsOverride() {
      let record = CKRecord(recordType: "A", recordID: CKRecord.ID(recordName: "A"))
        .copyWithMockSystemFields(
          recordChangeTag: "ab",
          modificationDate: Date(timeIntervalSinceReferenceDate: 1)
        )

      let mocked = record.copyWithMockSystemFields(
        recordChangeTag: "ac",
        modificationDate: Date(timeIntervalSinceReferenceDate: 2)
      )

      #expect(mocked.recordChangeTag == "ac")
      #expect(mocked.modificationDate == Date(timeIntervalSinceReferenceDate: 2))
    }

    @Test func copyPreservesMockSystemFields() throws {
      let record = CKRecord(recordType: "A", recordID: CKRecord.ID(recordName: "A"))
        .copyWithMockSystemFields(
          recordChangeTag: "ab",
          modificationDate: Date(timeIntervalSinceReferenceDate: 1)
        )

      let copy = try #require(record.copy() as? CKRecord)

      #expect(copy.recordChangeTag == "ab")
      #expect(copy.modificationDate == Date(timeIntervalSinceReferenceDate: 1))
    }

    @Test func systemFieldsRepresentationRoundtrip() throws {
      let record = CKRecord(recordType: "A", recordID: CKRecord.ID(recordName: "A"))
        .copyWithMockSystemFields(
          recordChangeTag: "ab",
          modificationDate: Date(timeIntervalSinceReferenceDate: 1)
        )

      let representation = CKRecord.SystemFieldsRepresentation(queryOutput: record)
      let result = try #require(
        CKRecord.SystemFieldsRepresentation(queryBinding: representation.queryBinding)
      )

      #expect(result.queryOutput.recordChangeTag == "ab")
      #expect(result.queryOutput.modificationDate == Date(timeIntervalSinceReferenceDate: 1))
    }

    @Test func allFieldsRepresentationRoundtrip() throws {
      let record = CKRecord(recordType: "A", recordID: CKRecord.ID(recordName: "A"))
        .copyWithMockSystemFields(
          recordChangeTag: "ab",
          modificationDate: Date(timeIntervalSinceReferenceDate: 1)
        )

      let representation = CKRecord._AllFieldsRepresentation(queryOutput: record)
      let result = try #require(
        CKRecord._AllFieldsRepresentation(queryBinding: representation.queryBinding)
      )

      #expect(result.queryOutput.recordChangeTag == "ab")
      #expect(result.queryOutput.modificationDate == Date(timeIntervalSinceReferenceDate: 1))
    }

    @Test func isNewerChangeTag() {
      #expect("0".isNewerChangeTag(than: nil))

      #expect(!"0".isNewerChangeTag(than: "0"))
      #expect(!"z".isNewerChangeTag(than: "z"))

      #expect("1".isNewerChangeTag(than: "0"))
      #expect(!"0".isNewerChangeTag(than: "1"))
      #expect("a".isNewerChangeTag(than: "9"))
      #expect(!"9".isNewerChangeTag(than: "a"))
      #expect("z".isNewerChangeTag(than: "a"))

      #expect("10".isNewerChangeTag(than: "z"))
      #expect(!"z".isNewerChangeTag(than: "10"))
      #expect("100".isNewerChangeTag(than: "zz"))
      #expect(!"zz".isNewerChangeTag(than: "100"))
    }
  }
#endif
