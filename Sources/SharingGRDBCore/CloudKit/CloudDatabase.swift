#if canImport(CloudKit)
import CloudKit

package protocol CloudDatabase: AnyObject, Hashable, Sendable {
  func record(for recordID: CKRecord.ID) async throws -> CKRecord

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  func records(
    for ids: [CKRecord.ID]
  ) async throws -> [CKRecord.ID : Result<CKRecord, any Error>]

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  func modifyRecords(
    saving recordsToSave: [CKRecord],
    deleting recordIDsToDelete: [CKRecord.ID],
    savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
    atomically: Bool
  ) async throws -> (
    saveResults: [CKRecord.ID : Result<CKRecord, any Error>],
    deleteResults: [CKRecord.ID : Result<Void, any Error>]
  )
}

final class AnyCloudDatabase: CloudDatabase {
  let rawValue: any CloudDatabase
  init(_ rawValue: any CloudDatabase) {
    self.rawValue = rawValue
  }
  func record(for recordID: CKRecord.ID) async throws -> CKRecord {
    try await rawValue.record(for: recordID)
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  func records(
    for ids: [CKRecord.ID]
  ) async throws -> [CKRecord.ID : Result<CKRecord, any Error>] {
    try await rawValue.records(for: ids)
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  func modifyRecords(
    saving recordsToSave: [CKRecord],
    deleting recordIDsToDelete: [CKRecord.ID],
    savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
    atomically: Bool
  ) async throws -> (
    saveResults: [CKRecord.ID : Result<CKRecord, any Error>],
    deleteResults: [CKRecord.ID : Result<Void, any Error>]
  ) {
    try await rawValue.modifyRecords(
        saving: recordsToSave,
        deleting: recordIDsToDelete,
        savePolicy: savePolicy,
        atomically: atomically
      )
  }

  static func == (lhs: AnyCloudDatabase, rhs: AnyCloudDatabase) -> Bool {
    lhs.rawValue === rhs.rawValue
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(rawValue))
  }
}

extension CloudDatabase {
  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  func modifyRecords(
    saving recordsToSave: [CKRecord],
    deleting recordIDsToDelete: [CKRecord.ID]
  ) async throws -> (
    saveResults: [CKRecord.ID : Result<CKRecord, any Error>],
    deleteResults: [CKRecord.ID : Result<Void, any Error>]
  ) {
    try await modifyRecords(
      saving: recordsToSave,
      deleting: recordIDsToDelete,
      savePolicy: .ifServerRecordUnchanged,
      atomically: true
    )
  }
}

extension CKDatabase: CloudDatabase {
  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  package func records(
    for ids: [CKRecord.ID]
  ) async throws -> [CKRecord.ID : Result<CKRecord, any Error>] {
    try await records(for: ids, desiredKeys: nil)
  }
}
#endif
