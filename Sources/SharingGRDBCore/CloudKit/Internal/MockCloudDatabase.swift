import CloudKit
import CustomDump
import IssueReporting

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
package final class MockCloudDatabase: CloudDatabase {
  package let storage = LockIsolated<[CKRecordZone.ID: [CKRecord.ID: CKRecord]]>([:])
  let assets = LockIsolated<[AssetID: Data]>([:])
  package let databaseScope: CKDatabase.Scope
  let _container = IsolatedWeakVar<MockCloudContainer>()

  let dataManager = Dependency(\.dataManager)

  struct AssetID: Hashable {
    let recordID: CKRecord.ID
    let key: String
  }

  package init(databaseScope: CKDatabase.Scope) {
    self.databaseScope = databaseScope
  }

  package func set(container: MockCloudContainer) {
    _container.set(container)
  }

  package var container: MockCloudContainer {
    _container.value!
  }

  package func record(for recordID: CKRecord.ID) throws -> CKRecord {
    let accountStatus = container.accountStatus()
    guard accountStatus == .available
    else { throw ckError(forAccountStatus: accountStatus) }
    guard let zone = storage[recordID.zoneID]
    else { throw CKError(.zoneNotFound) }
    guard let record = zone[recordID]
    else { throw CKError(.unknownItem) }
    guard let record = record.copy() as? CKRecord
    else { fatalError("Could not copy CKRecord.") }

    try assets.withValue { assets in
      for key in record.allKeys() {
        guard let assetData = assets[AssetID(recordID: record.recordID, key: key)]
        else { continue }
        let url = URL(filePath: UUID().uuidString.lowercased())
        try dataManager.wrappedValue.save(assetData, to: url)
        record[key] = CKAsset(fileURL: url)
      }
    }

    return record
  }

  package func records(
    for ids: [CKRecord.ID],
    desiredKeys: [CKRecord.FieldKey]?
  ) throws -> [CKRecord.ID: Result<CKRecord, any Error>] {
    let accountStatus = container.accountStatus()
    guard accountStatus == .available
    else { throw ckError(forAccountStatus: accountStatus) }

    var results: [CKRecord.ID: Result<CKRecord, any Error>] = [:]
    for id in ids {
      results[id] = Result { try record(for: id) }
    }
    return results
  }

  package func modifyRecords(
    saving recordsToSave: [CKRecord] = [],
    deleting recordIDsToDelete: [CKRecord.ID] = [],
    savePolicy: CKModifyRecordsOperation.RecordSavePolicy = .ifServerRecordUnchanged,
    atomically: Bool = true
  ) throws -> (
    saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
    deleteResults: [CKRecord.ID: Result<Void, any Error>]
  ) {
    let accountStatus = container.accountStatus()
    guard accountStatus == .available
    else { throw ckError(forAccountStatus: accountStatus) }

    return storage.withValue { storage in
      var saveResults: [CKRecord.ID: Result<CKRecord, any Error>] = [:]
      var deleteResults: [CKRecord.ID: Result<Void, any Error>] = [:]

      switch savePolicy {
      case .ifServerRecordUnchanged:
        for recordToSave in recordsToSave {
          if let share = recordToSave as? CKShare {
            let isSavingRootRecord = recordsToSave.contains(where: {
              $0.share?.recordID == share.recordID
            })
            let shareWasPreviouslySaved = storage[share.recordID.zoneID]?[share.recordID] != nil
            guard shareWasPreviouslySaved || isSavingRootRecord
            else {
              reportIssue(
                """
                An added share is being saved without its rootRecord being saved in the same \
                operation.
                """
              )
              saveResults[recordToSave.recordID] = .failure(CKError(.invalidArguments))
              continue
            }
          }

          guard storage[recordToSave.recordID.zoneID] != nil
          else {
            saveResults[recordToSave.recordID] = .failure(CKError(.zoneNotFound))
            continue
          }

          let existingRecord = storage[recordToSave.recordID.zoneID]?[recordToSave.recordID]

          func saveRecordToDatabase() {
            let hasReferenceViolation =
              recordToSave.parent.map { parent in
                storage[parent.recordID.zoneID]?[parent.recordID] == nil
                  && !recordsToSave.contains { $0.recordID == parent.recordID }
              }
              ?? false
            guard !hasReferenceViolation
            else {
              saveResults[recordToSave.recordID] = .failure(CKError(.referenceViolation))
              return
            }

            func root(of record: CKRecord) -> CKRecord {
              guard let parent = record.parent
              else { return record }
              return (storage[parent.recordID.zoneID]?[parent.recordID]).map(root) ?? record
            }
            func share(for rootRecord: CKRecord) -> CKShare? {
              for (_, record) in storage[rootRecord.recordID.zoneID] ?? [:] {
                guard record.recordID == rootRecord.share?.recordID
                else { continue }
                return record as? CKShare
              }
              return nil
            }
            let rootRecord = root(of: recordToSave)
            let share = share(for: rootRecord)
            let isSavingShare = recordsToSave.contains { $0.recordID == share?.recordID }
            if
              !isSavingShare,
              !(recordToSave is CKShare),
              let share,
              !(share.publicPermission == .readWrite
                || share.currentUserParticipant?.permission == .readWrite)
            {
              saveResults[recordToSave.recordID] = .failure(CKError(.permissionFailure))
              return
            }

            guard let copy = recordToSave.copy() as? CKRecord
            else { fatalError("Could not copy CKRecord.") }
            copy._recordChangeTag = UUID().uuidString

            assets.withValue { assets in
              for key in copy.allKeys() {
                guard let assetURL = (copy[key] as? CKAsset)?.fileURL
                else { continue }
                assets[AssetID(recordID: copy.recordID, key: key)] = try? dataManager.wrappedValue
                  .load(assetURL)
              }
            }

            // TODO: this should merge copy's values into storage but not sure how right now.
            storage[recordToSave.recordID.zoneID]?[recordToSave.recordID] = copy
            saveResults[recordToSave.recordID] = .success(copy)
          }

          switch (existingRecord, recordToSave._recordChangeTag) {
          case (.some(let existingRecord), .some(let recordToSaveChangeTag)):
            // We are trying to save a record with a change tag that also already exists in the
            // DB. If the tags match, we can save the record. Otherwise, we notify the sync engine
            // that the server record has changed since it was last synced.
            if existingRecord._recordChangeTag == recordToSaveChangeTag {
              precondition(existingRecord._recordChangeTag != nil)
              saveRecordToDatabase()
            } else {
              saveResults[recordToSave.recordID] = .failure(
                CKError(
                  .serverRecordChanged,
                  userInfo: [
                    CKRecordChangedErrorServerRecordKey: existingRecord.copy() as Any,
                    CKRecordChangedErrorClientRecordKey: recordToSave.copy(),
                  ]
                )
              )
            }
            break
          case (.some(let existingRecord), .none):
            // We are trying to save a record that does not have a change tag yet also already
            // exists in the DB. This means the user has created a new CKRecord from scratch,
            // giving it a new identity, rather than leveraging an existing CKRecord.
            reportIssue(
              """
              A new identity was created for an existing 'CKRecord' \
              ('\(existingRecord.recordID.recordName)'). Rather than creating \
              'CKRecord' from scratch for an existing record, use the database to fetch the \
              current record.
              """
            )
            saveResults[recordToSave.recordID] = .failure(
              CKError(
                .serverRejectedRequest,
                userInfo: [
                  CKRecordChangedErrorServerRecordKey: existingRecord.copy() as Any,
                  CKRecordChangedErrorClientRecordKey: recordToSave.copy(),
                ]
              )
            )
          case (.none, .some):
            // We are trying to save a record with a change tag but it does not exist in the DB.
            // This means the record was deleted by another device.
            saveResults[recordToSave.recordID] = .failure(CKError(.unknownItem))
          case (.none, .none):
            // We are trying to save a record with no change tag and no existing record in the DB.
            // This means it's a brand new record.
            saveRecordToDatabase()
          }
        }
      case .allKeys, .changedKeys:
        fatalError()
      @unknown default:
        fatalError()
      }
      for recordIDToDelete in recordIDsToDelete {
        guard storage[recordIDToDelete.zoneID] != nil
        else {
          deleteResults[recordIDToDelete] = .failure(CKError(.zoneNotFound))
          continue
        }
        let hasReferenceViolation = !Set(
          storage[recordIDToDelete.zoneID]?.values
            .compactMap { $0.parent?.recordID == recordIDToDelete ? $0.recordID : nil }
            ?? []
        )
        .subtracting(recordIDsToDelete)
        .isEmpty

        guard !hasReferenceViolation
        else {
          deleteResults[recordIDToDelete] = .failure(CKError(.referenceViolation))
          continue
        }
        storage[recordIDToDelete.zoneID]?[recordIDToDelete] = nil
        deleteResults[recordIDToDelete] = .success(())
      }

      return (saveResults: saveResults, deleteResults: deleteResults)
    }
  }

  package func modifyRecordZones(
    saving recordZonesToSave: [CKRecordZone] = [],
    deleting recordZoneIDsToDelete: [CKRecordZone.ID] = []
  ) throws -> (
    saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>],
    deleteResults: [CKRecordZone.ID: Result<Void, any Error>]
  ) {
    let accountStatus = container.accountStatus()
    guard accountStatus == .available
    else { throw ckError(forAccountStatus: accountStatus) }

    return storage.withValue { storage in
      var saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>] = [:]
      var deleteResults: [CKRecordZone.ID: Result<Void, any Error>] = [:]

      for recordZoneToSave in recordZonesToSave {
        storage[recordZoneToSave.zoneID] = storage[recordZoneToSave.zoneID] ?? [:]
        saveResults[recordZoneToSave.zoneID] = .success(recordZoneToSave)
      }

      for recordZoneIDsToDelete in recordZoneIDsToDelete {
        guard storage[recordZoneIDsToDelete] != nil
        else {
          deleteResults[recordZoneIDsToDelete] = .failure(CKError(.zoneNotFound))
          continue
        }
        storage[recordZoneIDsToDelete] = nil
        deleteResults[recordZoneIDsToDelete] = .success(())
      }

      return (saveResults: saveResults, deleteResults: deleteResults)
    }
  }

  package nonisolated static func == (lhs: MockCloudDatabase, rhs: MockCloudDatabase) -> Bool {
    lhs === rhs
  }

  package nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension MockCloudDatabase: CustomDumpReflectable {
  package var customDumpMirror: Mirror {
    Mirror(
      self,
      children: [
        "databaseScope": databaseScope,
        "storage": storage
          .value
          .flatMap { _, value in value.values }
          .sorted {
            ($0.recordType, $0.recordID.recordName) < ($1.recordType, $1.recordID.recordName)
          },
      ],
      displayStyle: .struct
    )
  }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
private func ckError(forAccountStatus accountStatus: CKAccountStatus) -> CKError {
  switch accountStatus {
  case .couldNotDetermine, .restricted, .noAccount:
    return CKError(.notAuthenticated)
  case .temporarilyUnavailable:
    return CKError(.accountTemporarilyUnavailable)
  case .available:
    fatalError()
  @unknown default:
    fatalError()
  }
}
