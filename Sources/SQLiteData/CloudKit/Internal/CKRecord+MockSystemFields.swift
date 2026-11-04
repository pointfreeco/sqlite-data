#if canImport(CloudKit)
  package import CloudKit
  import Foundation

  extension CKRecord {
    package func copyWithMockSystemFields(
      recordChangeTag: String,
      modificationDate: Date
    ) -> Self {
      let archiver = NSKeyedArchiver(requiringSecureCoding: true)
      self.encode(with: archiver)
      let unarchiver: MockSystemFieldsUnarchiver
      do {
        unarchiver = try MockSystemFieldsUnarchiver(forReadingFrom: archiver.encodedData)
      } catch {
        fatalError("Could not unarchive CKRecord: \(error)")
      }
      unarchiver.requiresSecureCoding = true
      unarchiver.recordChangeTag = recordChangeTag
      unarchiver.modificationDate = modificationDate
      guard let record = Self(coder: unarchiver)
      else { fatalError("Could not decode CKRecord.") }
      return record
    }
  }

  private final class MockSystemFieldsUnarchiver: NSKeyedUnarchiver {
    var recordChangeTag: String?
    var modificationDate: Date?

    override func decodeObject(forKey key: String) -> Any? {
      switch key {
      case "ETag":
        return self.recordChangeTag
      case "RecordMtime":
        return self.modificationDate
      default:
        return super.decodeObject(forKey: key)
      }
    }
  }
#endif
