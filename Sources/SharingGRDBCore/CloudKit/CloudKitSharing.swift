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

  // TODO: beef up to take query and bundle into @Selection?
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

    guard let lastKnownServerRecord
    else { return nil }
    // TODO: Add logic to determine privateCloudDatabase vs sharedCloudDatabase
    return try await container.privateCloudDatabase.record(for: lastKnownServerRecord.recordID)
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
  where T.TableColumns.PrimaryKey == UUID {
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
    // TODO: If we feel confident that our CKShares are always up to date, let's not even refresh
    // TODO: figure out if this share belongs to us or someone else so that we can choose between privateCloudDatabase and sharedCloudDatabase
    //    TODO: figure out how to expose private/shared database to outside world
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
    let metadata =
      try await metadatabase.read { db in
        try Metadata
          .find(recordID: CKRecord.ID(recordName: recordName))
          .fetchOne(db)
      } ?? nil

    guard let metadata
    else {
      throw NoCKRecordFound()
    }

    let rootRecord =
      metadata.lastKnownServerRecord
      ?? CKRecord(
        recordType: metadata.recordType,
        recordID: CKRecord.ID(
          recordName: metadata.recordName,
          zoneID: CKRecordZone.ID(
            zoneName: metadata.zoneName,
            ownerName: metadata.ownerName
          )
        )
      )

    let sharedRecord: CKShare
    if let shareRecordID = rootRecord.share?.recordID,
      let existingShare = try await container.privateCloudDatabase.record(for: shareRecordID)
        as? CKShare
    {
      sharedRecord = existingShare
    } else {
      sharedRecord = CKShare(rootRecord: rootRecord)
    }

    configure(sharedRecord)
    // TODO: We are getting an "client oplock error updating record" error in the logs when
    //       creating new shares / editing existing shares.
    _ = try await container.privateCloudDatabase.modifyRecords(
      saving: [sharedRecord, rootRecord],
      deleting: []
    )
    try await database.write { db in
      try Metadata
        .find(recordID: CKRecord.ID(recordName: recordName))
        .update { $0.share = sharedRecord }
        .execute(db)
    }

    return SharedRecord(container: container, share: sharedRecord)
  }

  public func acceptShare(metadata: CKShare.Metadata) async throws {
    try await syncEngines
      .withValue(\.shared)?
      .acceptShare(metadata: ShareMetadata(rawValue: metadata))
  }
}

// TODO: what kind of APIs do we need to expose for people to query for shared info? participants

#if canImport(UIKit)
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public struct CloudSharingView: UIViewControllerRepresentable {
    let sharedRecord: SharedRecord
    let didFinish: (Result<Void, Error>) -> Void
    let didStopSharing: () -> Void
    public init(sharedRecord: SharedRecord) {
      self.init(sharedRecord: sharedRecord, didFinish: { _ in }, didStopSharing: { })
    }
    public init(
      sharedRecord: SharedRecord,
      didFinish: @escaping (Result<Void, Error>) -> Void,
      didStopSharing: @escaping () -> Void
    ) {
      self.sharedRecord = sharedRecord
      self.didFinish = didFinish
      self.didStopSharing = didStopSharing
    }

    public func makeCoordinator() -> CloudSharingDelegate {
      CloudSharingDelegate(
        share: sharedRecord.share,
        didFinish: didFinish,
        didStopSharing: didStopSharing
      )
    }

    public func makeUIViewController(context: Context) -> UICloudSharingController {
      let controller = UICloudSharingController(
        share: sharedRecord.share,
        container: sharedRecord.container
      )
      controller.delegate = context.coordinator
      return controller
    }

    public func updateUIViewController(
      _ uiViewController: UICloudSharingController,
      context: Context
    ) {
    }
  }

  public final class CloudSharingDelegate: NSObject, UICloudSharingControllerDelegate {
    let share: CKShare
    let didFinish: (Result<Void, Error>) -> Void
    let didStopSharing: () -> Void
    init(
      share: CKShare,
      didFinish: @escaping (Result<Void, Error>) -> Void,
      didStopSharing: @escaping () -> Void
    ) {
      self.share = share
      self.didFinish = didFinish
      self.didStopSharing = didStopSharing
    }

    public func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
      share[CKShare.SystemFieldKey.thumbnailImageData] as? Data
    }

    public func itemTitle(for csc: UICloudSharingController) -> String? {
      share[CKShare.SystemFieldKey.title] as? String
    }

    public func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
      didFinish(.success(()))
    }

    public func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
      didStopSharing()
    }

    public func cloudSharingController(
      _ csc: UICloudSharingController,
      failedToSaveShareWithError error: any Error
    ) {
      didFinish(.failure(error))
    }
  }
#endif
