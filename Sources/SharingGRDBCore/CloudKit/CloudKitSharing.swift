#if canImport(CloudKit)
import CloudKit
import Dependencies
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

@available(iOS 15, macOS 12, *)
public struct SharedRecord: Hashable, Identifiable, Sendable {
  let container: any CloudContainer
  public let share: CKShare

  public var id: CKRecord.ID { share.recordID }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.container === rhs.container && lhs.share == rhs.share
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(container))
    hasher.combine(share)
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncEngine {
  private struct SharingError: LocalizedError {
    enum Reason {
      case recordMetadataNotFound
      case recordNotRoot([ForeignKey])
      case recordTableNotSynchronized
      case recordTablePrivate
    }

    let recordTableName: String
    let recordPrimaryKey: String
    let reason: Reason
    let debugDescription: String

    var errorDescription: String? {
      "The record could not be shared."
    }
  }

  public func share<T: PrimaryKeyedTable>(
    record: T,
    configure: @Sendable (CKShare) -> Void
  ) async throws -> SharedRecord
  where T.TableColumns.PrimaryKey.QueryOutput: IdentifierStringConvertible {
    guard tablesByName[T.tableName] != nil
    else {
      throw SharingError(
        recordTableName: T.tableName,
        recordPrimaryKey: record.primaryKey.rawIdentifier,
        reason: .recordTableNotSynchronized,
        debugDescription: """
          Table is not shareable: table type not passed to 'tables' parameter of 'SyncEngine.init'.
          """
      )
    }
    if let foreignKeys = foreignKeysByTableName[T.tableName], !foreignKeys.isEmpty {
      throw SharingError(
        recordTableName: T.tableName,
        recordPrimaryKey: record.primaryKey.rawIdentifier,
        reason: .recordNotRoot(foreignKeys),
        debugDescription: """
          Only root records are shareable, but parent record(s) detected via foreign key(s).
          """
      )
    }
    guard !privateTables.contains(where: { T.self == $0 })
    else {
      throw SharingError(
        recordTableName: T.tableName,
        recordPrimaryKey: record.primaryKey.rawIdentifier,
        reason: .recordTablePrivate,
        debugDescription: """
          Private tables are not shareable: table type passed to 'privateTables' parameter of \
          'SyncEngine.init'.
          """
      )
    }
    let recordName = record.recordName
    let metadata =
      try await metadatabase.read { db in
        try SyncMetadata
          .where { $0.recordName.eq(recordName) }
          .fetchOne(db)
      } ?? nil
    guard let metadata
    else {
      throw SharingError(
        recordTableName: T.tableName,
        recordPrimaryKey: record.primaryKey.rawIdentifier,
        reason: .recordMetadataNotFound,
        debugDescription: """
          No sync metadata found for record. Has the record been saved to the database?
          """
      )
    }

    let rootRecord =
      metadata.lastKnownServerRecord
      ?? CKRecord(
        recordType: metadata.recordType,
        recordID: CKRecord.ID(recordName: metadata.recordName, zoneID: defaultZone.zoneID)
      )

    var existingShare: CKShare? {
      get async throws {
        guard let shareRecordID = rootRecord.share?.recordID
        else { return nil }
        do {
          return try await container.database(for: rootRecord.recordID)
            .record(for: shareRecordID) as? CKShare
        } catch let error as CKError where error.code == .unknownItem {
          reportIssue("This would have been a problem before")
          return nil
        }
      }
    }

    let sharedRecord = try await existingShare ?? CKShare(
      rootRecord: rootRecord,
      shareID: CKRecord.ID(
        recordName: "share-\(recordName)",
        zoneID: rootRecord.recordID.zoneID
      )
    )

    configure(sharedRecord)
    // TODO: We are getting an "client oplock error updating record" error in the logs when
    //       creating new shares / editing existing shares.
    _ = try await container.privateCloudDatabase.modifyRecords(
      saving: [sharedRecord, rootRecord],
      deleting: []
    )
    try await userDatabase.write { db in
      try SyncMetadata
        .where { $0.recordName.eq(recordName) }
        .update { $0.share = sharedRecord }
        .execute(db)
    }

    return SharedRecord(container: container, share: sharedRecord)
  }

  public func acceptShare(metadata: CKShare.Metadata) async throws {
    try await acceptShare(metadata: ShareMetadata(rawValue: metadata))
  }
}

#if canImport(UIKit) && !os(watchOS)
  @available(iOS 17, macOS 14, tvOS 17, *)
  public struct CloudSharingView: UIViewControllerRepresentable {
    let sharedRecord: SharedRecord
    let availablePermissions: UICloudSharingController.PermissionOptions
    let didFinish: (Result<Void, Error>) -> Void
    let didStopSharing: () -> Void
    public init(sharedRecord: SharedRecord, availablePermissions: UICloudSharingController.PermissionOptions = []) {
      self.init(sharedRecord: sharedRecord, availablePermissions: availablePermissions, didFinish: { _ in }, didStopSharing: {})
    }
    public init(
      sharedRecord: SharedRecord,
      availablePermissions: UICloudSharingController.PermissionOptions = [],
      didFinish: @escaping (Result<Void, Error>) -> Void,
      didStopSharing: @escaping () -> Void
    ) {
      self.sharedRecord = sharedRecord
      self.didFinish = didFinish
      self.didStopSharing = didStopSharing
      self.availablePermissions = availablePermissions
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
        container: sharedRecord.container.rawValue
      )
      controller.delegate = context.coordinator
      controller.availablePermissions = availablePermissions
      return controller
    }

    public func updateUIViewController(
      _ uiViewController: UICloudSharingController,
      context: Context
    ) {
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, *)
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
      withErrorReporting {
        try syncEngine.deleteShare(recordID: share.recordID)
      }
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
