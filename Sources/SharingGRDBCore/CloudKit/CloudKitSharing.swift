#if canImport(CloudKit)
import CloudKit
import Dependencies
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
  public struct UnrecognizedTable: Error {}
  public struct RecordMustBeRoot: Error {}
  public struct NoCKRecordFound: Error {}

  public func share<T: PrimaryKeyedTable>(
    record: T,
    configure: @Sendable (CKShare) -> Void
  ) async throws -> SharedRecord
  where T.TableColumns.PrimaryKey == UUID {
    guard let foreignKeys = foreignKeysByTableName[T.tableName]
    else {
      throw UnrecognizedTable()
    }
    guard foreignKeys.isEmpty
    else {
      throw RecordMustBeRoot()
    }

    let recordName = SyncMetadata.RecordName(record: record)
    let metadata =
      try await metadatabase.read { db in
        try SyncMetadata
          .find(recordName)
          .fetchOne(db)
      } ?? nil

    guard let metadata
    else {
      throw NoCKRecordFound()
    }

    let rootRecord =
      metadata.lastKnownServerRecord
      // 1) create record
      // 2) (before sync) you share
      // 3) create a CKRecord down below
      // 4) a moment later, sync engine creates a record
      ?? CKRecord(
        recordType: metadata.recordType,
        recordID: CKRecord.ID(
          recordName: metadata.recordName.rawValue,
          zoneID: Self.defaultZone.zoneID
        )
      )

    let sharedRecord: CKShare
    if let shareRecordID = rootRecord.share?.recordID,
      let existingShare = try await container.database(for: rootRecord.recordID)
        .record(for: shareRecordID) as? CKShare
    {
      sharedRecord = existingShare
    } else {
      sharedRecord = CKShare(
        rootRecord: rootRecord,
        shareID: CKRecord.ID(
          recordName: UUID().uuidString,
          zoneID: rootRecord.recordID.zoneID
        )
      )
    }

    configure(sharedRecord)
    // TODO: We are getting an "client oplock error updating record" error in the logs when
    //       creating new shares / editing existing shares.
    _ = try await container.privateCloudDatabase.modifyRecords(
      saving: [sharedRecord, rootRecord],
      deleting: []
    )
    try await database.write { db in
      try SyncMetadata
        .find(recordName)
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

#if canImport(UIKit)
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public struct CloudSharingView: UIViewControllerRepresentable {
    let sharedRecord: SharedRecord
    let didFinish: (Result<Void, Error>) -> Void
    let didStopSharing: () -> Void
    public init(sharedRecord: SharedRecord) {
      self.init(sharedRecord: sharedRecord, didFinish: { _ in }, didStopSharing: {})
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

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
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
      @Dependency(\.defaultSyncEngine) var syncEngine
      // TODO: eagerly clear out share data
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
#endif
