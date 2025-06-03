import CloudKit
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

public struct SharedRecord: Hashable, Identifiable, Sendable {
  public let container: CKContainer
  public let share: CKShare

  public var id: CKRecord.ID { share.recordID }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncEngine {
  public struct CantShareRecordWithParent: Error {}
  public struct NoCKRecordFound: Error {}

//  public func records<T: PrimaryKeyedTable>(for _: T.Type) async throws -> [CKRecord] {
//    []
//  }

  public func record<T: PrimaryKeyedTable>(for record: T) async throws -> CKRecord? {
    let lastKnownServerRecord = try await metadatabase.read { db in
      try Metadata
        .where { $0.recordType.eq(T.tableName) }
        .select(\.lastKnownServerRecord)
        .fetchOne(db) ?? nil
    }

    return lastKnownServerRecord
  }

  public func shares<T: PrimaryKeyedTable>(for _: T.Type) throws -> [CKShare] {
    try metadatabase.read { db in
      try Metadata
        .where { $0.recordType.eq(T.tableName) }
        .select(\.share)
        .fetchAll(db)
        .compactMap(\.self)
    }
  }

  public func share<T: PrimaryKeyedTable>(
    for record: T
  ) async throws -> CKShare?
  where T.TableColumns.PrimaryKey == UUID
  {
    let primaryKey = record[keyPath: T.columns.primaryKey.keyPath]
    let share = try await metadatabase.read { db in
      try Metadata
        .where {
          $0.recordName.eq(primaryKey.uuidString.lowercased())
          && $0.recordType.eq(T.tableName)
        }
        .select(\.share)
        .fetchOne(db) ?? nil
    }
    guard let share
    else { return nil }
    // TODO: figure out if this share belongs to us or someone else so that we can choose between privateCloudDatabase and sharedCloudDatabase
    return (try await container.privateCloudDatabase.record(for: share.recordID) as? CKShare)
    ?? share
  }

  // TODO: upsertShare / share.
  //       share(record:) is very similar to share(for:)
  public func createShare<T: PrimaryKeyedTable>(
    record: T,
    configure: @Sendable (CKShare) -> Void
  ) async throws -> SharedRecord
  where T.TableColumns.PrimaryKey == UUID {
    guard foreignKeysByTableName[T.tableName]?.count(where: \.notnull) ?? 0 == 0
    else {
      throw CantShareRecordWithParent()
    }

    let recordName = record[keyPath: T.columns.primaryKey.keyPath].uuidString.lowercased()
    let lastKnownServerRecord =
      try await database.write { db in
        try Metadata
          .find(recordID: CKRecord.ID(recordName: recordName))
          .select(\.lastKnownServerRecord)
          .fetchOne(db)
      } ?? nil

    guard let lastKnownServerRecord
    else {
      throw NoCKRecordFound()
    }

    let sharedRecord: CKShare
    if let existingShareRecordID = lastKnownServerRecord.share?.recordID,
      let existingShare = try await container.privateCloudDatabase.record(
        for: existingShareRecordID
      ) as? CKShare
    {
      sharedRecord = existingShare
    } else {
      sharedRecord = CKShare(rootRecord: lastKnownServerRecord)
    }

    // TODO: upsert "metadata" and store the sharedID and/or the full serialized CKShare?
    // TODO: where we currently have purple warnings about cloudkit.share we should upsert that info into Metadata

    configure(sharedRecord)
    _ = try await container.privateCloudDatabase.modifyRecords(
      saving: [sharedRecord, lastKnownServerRecord],
      deleting: []
    )

    return SharedRecord(container: container, share: sharedRecord)
  }

  public func acceptShare(metadata: CKShare.Metadata) async throws {
    try await sharedSyncEngine.acceptShare(metadata: ShareMetadata(rawValue: metadata))
  }
}

// TODO: Handle: SharingGRDB CloudKit Failure: No table to delete from: "cloudkit.share"
// TODO: what kind of APIs do we need to expose for people to query for shared info? participants

#if canImport(UIKit)
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public struct CloudSharingView: UIViewControllerRepresentable {
    let sharedRecord: SharedRecord
    public init(sharedRecord: SharedRecord) {
      self.sharedRecord = sharedRecord
    }

    public func makeUIViewController(context: Context) -> UICloudSharingController {
      UICloudSharingController(
        share: sharedRecord.share,
        container: sharedRecord.container
      )
    }

    public func updateUIViewController(
      _ uiViewController: UICloudSharingController,
      context: Context
    ) {
    }
  }
#endif
