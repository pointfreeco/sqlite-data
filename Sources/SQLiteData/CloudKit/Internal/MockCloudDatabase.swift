#if canImport(CloudKit)
  import CloudKit
  import IssueReporting

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  package final class MockCloudDatabase: CloudDatabase {
    package let state = LockIsolated(State())
    package let databaseScope: CKDatabase.Scope
    let _container = IsolatedWeakVar<MockCloudContainer>()
    let dataManager = Dependency(\.dataManager)

    package struct State {
      private var lastRecordChangeTag = 0
      package var storage: [CKRecordZone.ID: Zone] = [:]
      var assets: [AssetID: Data] = [:]
      var deletedRecords: [(CKRecord.ID, CKRecord.RecordType)] = []
      mutating func nextRecordChangeTag() -> Int {
        lastRecordChangeTag += 1
        return lastRecordChangeTag
      }

      mutating func saveRecord(_ record: CKRecord) {
        guard var existingEntry = storage[record.recordID.zoneID]?.entries[record.recordID]
        else {
          storage[record.recordID.zoneID]?.entries[record.recordID] =
            RecordEntry(record: record, history: [:])
          return
        }
        if let existingRecordChangeTag = existingEntry.record._recordChangeTag {
          existingEntry.history[existingRecordChangeTag] = existingEntry.record.copy() as? CKRecord
        }
        existingEntry.record = record
        storage[record.recordID.zoneID]?.entries[record.recordID] = existingEntry
      }
    }

    struct AssetID: Hashable {
      let recordID: CKRecord.ID
      let key: String
    }

    package struct Zone {
      package var zone: CKRecordZone
      package var entries: [CKRecord.ID: RecordEntry] = [:]
    }

    package struct RecordEntry {
      package var record: CKRecord
      package var history: [Int: CKRecord]
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
      let record = try state.withValue { state in
        guard let zone = state.storage[recordID.zoneID]
        else { throw CKError(.zoneNotFound) }
        guard let record = zone.entries[recordID]?.record
        else { throw CKError(.unknownItem) }
        guard let record = record.copy() as? CKRecord
        else { fatalError("Could not copy CKRecord.") }
        return record
      }

      try state.withValue { state in
        for key in record.allKeys() {
          guard let assetData = state.assets[AssetID(recordID: record.recordID, key: key)]
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

      guard ids.count < 200
      else { throw CKError(.limitExceeded) }

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

      guard (recordsToSave.count + recordIDsToDelete.count) < 200
      else {
        throw CKError(.limitExceeded)
      }

      return state.withValue { state in
        let previousStorage = state.storage
        var saveResults: [CKRecord.ID: Result<CKRecord, any Error>] = [:]
        var deleteResults: [CKRecord.ID: Result<Void, any Error>] = [:]

        switch savePolicy {
        case .ifServerRecordUnchanged:
          for recordToSave in recordsToSave {
            if let share = recordToSave as? CKShare {
              let isSavingRootRecord = recordsToSave.contains(where: {
                $0.share?.recordID == share.recordID
              })
              let shareWasPreviouslySaved =
                state.storage[share.recordID.zoneID]?.entries[share.recordID] != nil
              guard shareWasPreviouslySaved || isSavingRootRecord
              else {
                saveResults[recordToSave.recordID] = .failure(CKError(.invalidArguments))
                continue
              }
            } else if databaseScope == .shared,
              recordToSave.parent == nil,
              recordToSave.share == nil
            {
              // NB: Emit 'permissionFailure' if saving to shared database with no parent reference
              //     or share reference.
              saveResults[recordToSave.recordID] = .failure(CKError(.permissionFailure))
              continue
            }

            // NB: Emit 'zoneNotFound' error if saving record with a zone not found in database.
            guard state.storage[recordToSave.recordID.zoneID] != nil
            else {
              saveResults[recordToSave.recordID] = .failure(CKError(.zoneNotFound))
              continue
            }

            let existingRecord = state.storage[recordToSave.recordID.zoneID]?.entries[
              recordToSave.recordID
            ]?.record

            func saveRecordToDatabase() {
              let hasReferenceViolation =
                recordToSave.parent.map { parent in
                  state.storage[parent.recordID.zoneID]?.entries[parent.recordID] == nil
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
                return (state.storage[parent.recordID.zoneID]?.entries[parent.recordID]?.record)
                  .map(root) ?? record
              }
              func share(for rootRecord: CKRecord) -> CKShare? {
                for (_, entry) in state.storage[rootRecord.recordID.zoneID]?.entries ?? [:] {
                  let record = entry.record
                  guard record.recordID == rootRecord.share?.recordID
                  else { continue }
                  return record as? CKShare
                }
                return nil
              }
              let rootRecord = root(of: recordToSave)
              let share = share(for: rootRecord)
              let isSavingShare = recordsToSave.contains { $0.recordID == share?.recordID }
              if !isSavingShare,
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
              copy._recordChangeTag = state.nextRecordChangeTag()

              for key in copy.allKeys() {
                guard let assetURL = (copy[key] as? CKAsset)?.fileURL
                else { continue }
                state.assets[AssetID(recordID: copy.recordID, key: key)] =
                  try? dataManager.wrappedValue
                  .load(assetURL)
              }

              // TODO: This should merge copy's values to more accurately reflect reality
              state.saveRecord(copy)
              saveResults[recordToSave.recordID] = .success(copy)

              // NB: "Touch" parent records when saving a child:
              if let parent = recordToSave.parent,
                // If the parent isn't also being saved in this batch.
                !recordsToSave.contains(where: { $0.recordID == parent.recordID }),
                // And if the parent is in the database.
                let parentRecord = state.storage[parent.recordID.zoneID]?.entries[parent.recordID]?
                  .record
                  .copy() as? CKRecord
              {
                parentRecord._recordChangeTag = state.nextRecordChangeTag()
                state.saveRecord(parentRecord)
              }
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
                let ancestorRecord =
                  state.storage[recordToSave.recordID.zoneID]?.entries[recordToSave.recordID]?
                  .history[recordToSaveChangeTag]
                  ?? (existingRecord.copy() as? CKRecord ?? existingRecord)
                saveResults[recordToSave.recordID] = .failure(
                  CKError(
                    .serverRecordChanged,
                    userInfo: [
                      CKRecordChangedErrorServerRecordKey: existingRecord.copy() as Any,
                      CKRecordChangedErrorClientRecordKey: recordToSave.copy(),
                      CKRecordChangedErrorAncestorRecordKey: ancestorRecord as Any,
                    ]
                  )
                )
              }
              break
            case (.some(let existingRecord), .none):
              // We are trying to save a record that does not have a change tag yet also already
              // exists in the DB. This means the user has created a new CKRecord from scratch,
              // giving it a new identity, rather than leveraging an existing CKRecord.
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
          guard state.storage[recordIDToDelete.zoneID] != nil
          else {
            deleteResults[recordIDToDelete] = .failure(CKError(.zoneNotFound))
            continue
          }
          let hasReferenceViolation = !Set(
            state.storage[recordIDToDelete.zoneID]?.entries.values
              .compactMap { $0.record.parent?.recordID == recordIDToDelete ? $0.record.recordID : nil }
              ?? []
          )
          .subtracting(recordIDsToDelete)
          .isEmpty

          guard !hasReferenceViolation
          else {
            deleteResults[recordIDToDelete] = .failure(CKError(.referenceViolation))
            continue
          }
          let recordToDelete = state.storage[recordIDToDelete.zoneID]?.entries[recordIDToDelete]?
            .record
          state.storage[recordIDToDelete.zoneID]?.entries[recordIDToDelete] = nil
          deleteResults[recordIDToDelete] = .success(())
          if let recordType = recordToDelete?.recordType {
            state.deletedRecords.append((recordIDToDelete, recordType))
          }

          // NB: If deleting a share that the current user owns, delete the shared records and all
          //     associated records.
          if databaseScope == .shared,
            let shareToDelete = recordToDelete as? CKShare,
            shareToDelete.recordID.zoneID.ownerName == CKCurrentUserDefaultName
          {
            func deleteRecords(referencing recordID: CKRecord.ID) {
              for entryToDelete in (state.storage[recordIDToDelete.zoneID]?.entries ?? [:]).values
              {
                let record = entryToDelete.record
                guard
                  record.share?.recordID == recordID
                    || record.parent?.recordID == recordID
                else {
                  continue
                }
                state.storage[recordIDToDelete.zoneID]?.entries[record.recordID] = nil
                deleteResults[record.recordID] = .success(())
                state.deletedRecords.append((recordIDToDelete, record.recordType))
                deleteRecords(referencing: record.recordID)
              }
            }
            deleteRecords(referencing: shareToDelete.recordID)
          }
        }

        guard atomically
        else {
          return (saveResults: saveResults, deleteResults: deleteResults)
        }

        let affectedZones = Set(
          recordsToSave.map(\.recordID.zoneID) + recordIDsToDelete.map(\.zoneID)
        )
        for zoneID in affectedZones {
          let saveResultsInZone = saveResults.filter { recordID, _ in recordID.zoneID == zoneID }
          let deleteResultsInZone = deleteResults.filter { recordID, _ in
            recordID.zoneID == zoneID
          }
          let saveSuccessRecordIDs = saveResultsInZone.compactMap { recordID, result in
            (try? result.get()) == nil ? nil : recordID
          }
          let deleteSuccessRecordIDs = deleteResultsInZone.compactMap { recordID, result in
            (try? result.get()) == nil ? nil : recordID
          }
          guard
            saveSuccessRecordIDs.count != saveResultsInZone.count
              || deleteSuccessRecordIDs.count != deleteResultsInZone.count
          else {
            continue
          }
          // Every successful save and deletion becomes a '.batchRequestFailed'.
          for saveSuccessRecordID in saveSuccessRecordIDs {
            saveResults[saveSuccessRecordID] = .failure(CKError(.batchRequestFailed))
          }
          for deleteSuccessRecordID in deleteSuccessRecordIDs {
            deleteResults[deleteSuccessRecordID] = .failure(CKError(.batchRequestFailed))
          }
          // All storage changes are reverted in zone.
          state.storage[zoneID]?.entries = previousStorage[zoneID]?.entries ?? [:]
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

      return state.withValue { state in
        var saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>] = [:]
        var deleteResults: [CKRecordZone.ID: Result<Void, any Error>] = [:]

        for recordZoneToSave in recordZonesToSave {
          state.storage[recordZoneToSave.zoneID] =
            state.storage[recordZoneToSave.zoneID] ?? Zone(zone: recordZoneToSave)
          saveResults[recordZoneToSave.zoneID] = .success(recordZoneToSave)
        }

        for recordZoneIDsToDelete in recordZoneIDsToDelete {
          guard state.storage[recordZoneIDsToDelete] != nil
          else {
            deleteResults[recordZoneIDsToDelete] = .failure(CKError(.zoneNotFound))
            continue
          }
          state.storage[recordZoneIDsToDelete] = nil
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
#endif
