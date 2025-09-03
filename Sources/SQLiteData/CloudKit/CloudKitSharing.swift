#if canImport(CloudKit)
  import CloudKit
  import Dependencies
  import SwiftUI

  #if canImport(UIKit)
    import UIKit
  #endif

  /// A shared record that can be used to present a ``CloudSharingView``
  ///
  /// See <doc:CloudKitSharing#Creating-CKShare-records> for more information.,
  @available(iOS 15, tvOS 15, macOS 12, watchOS 8, *)
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
    
    /// Shares a record in CloudKit.
    ///
    /// This method will thrown an error if:
    ///
    /// * The table the `record` belongs to is not synchronized to CloudKit.
    /// * The `record` has any foreign keys. Only root records are shareable in CloudKit.
    /// * The table the `record` belongs to is a "private" table as determined by the
    /// [`SyncEngine` initializer](<doc:SyncEngine/init(for:tables:privateTables:containerIdentifier:defaultZone:startImmediately:logger:)>).
    /// * The `record` is being shared before it has been synchronized to CloudKit.
    /// * Any of the CloudKit APIs invoked throw an error.
    ///
    /// The value returned from this method can be used to present a ``CloudSharingView`` which
    /// allows the user to send a share URL to another user.
    ///
    /// - Parameters:
    ///   - record: The record to be shared on CloudKit.
    ///   - configure: A trailing closure that can customize the `CKShare` sent to CloudKit. See
    ///   [Apple's documentation](https://developer.apple.com/documentation/cloudkit/ckshare/systemfieldkey)
    ///   for more info on what can be configured.
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
            Table is not shareable: table type not passed to 'tables' parameter of \
            'SyncEngine.init'.
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
            return nil
          }
        }
      }

      let sharedRecord =
        try await existingShare
        ?? CKShare(
          rootRecord: rootRecord,
          shareID: CKRecord.ID(
            recordName: "share-\(recordName)",
            zoneID: rootRecord.recordID.zoneID
          )
        )

      configure(sharedRecord)
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

    public func unshare<T: PrimaryKeyedTable>(record: T) async throws
    where T.TableColumns.PrimaryKey.QueryOutput: IdentifierStringConvertible {
      let share = try await userDatabase.read { [recordName = record.recordName] db in
        try SyncMetadata
          .where { $0.recordName.eq(recordName) }
          .select(\.share)
          .fetchOne(db)
          ?? nil
      }
      guard let share
      else {
        reportIssue(
          """
          No share found associated with record.
          """)
        return
      }

      let result = try await syncEngines.private?.database.modifyRecords(
        saving: [],
        deleting: [share.recordID]
      )
      try result?.deleteResults.values.forEach { _ = try $0.get() }
    }
    
    /// Accepts a shared record.
    ///
    /// This method should be invoked from various delegate methods on the scene delegate of the
    /// app. See <doc:CloudKitSharing#Accepting-shared-records> for more info.
    public func acceptShare(metadata: CKShare.Metadata) async throws {
      try await acceptShare(metadata: ShareMetadata(rawValue: metadata))
    }
  }

#if canImport(UIKit) && !os(watchOS)
    /// A view that presents standard screens for adding and removing people from a CloudKit share \
    /// record.
    ///
    /// See <doc:CloudKitSharing#Creating-CKShare-records> for more info.
    @available(iOS 17, macOS 14, tvOS 17, *)
    public struct CloudSharingView: UIViewControllerRepresentable {
      let sharedRecord: SharedRecord
      let availablePermissions: UICloudSharingController.PermissionOptions
      let didFinish: (Result<Void, Error>) -> Void
      let didStopSharing: () -> Void
      let syncEngine: SyncEngine
      public init(
        sharedRecord: SharedRecord,
        availablePermissions: UICloudSharingController.PermissionOptions = [],
        didFinish: @escaping (Result<Void, Error>) -> Void = { _ in },
        didStopSharing: @escaping () -> Void = {},
        syncEngine: SyncEngine = {
          @Dependency(\.defaultSyncEngine) var defaultSyncEngine
          return defaultSyncEngine
        }()
      ) {
        self.sharedRecord = sharedRecord
        self.didFinish = didFinish
        self.didStopSharing = didStopSharing
        self.availablePermissions = availablePermissions
        self.syncEngine = syncEngine
      }

      public func makeCoordinator() -> _CloudSharingDelegate {
        _CloudSharingDelegate(
          share: sharedRecord.share,
          didFinish: didFinish,
          didStopSharing: didStopSharing,
          syncEngine: syncEngine
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
    public final class _CloudSharingDelegate: NSObject, UICloudSharingControllerDelegate {
      let share: CKShare
      let didFinish: (Result<Void, Error>) -> Void
      let didStopSharing: () -> Void
      let syncEngine: SyncEngine
      init(
        share: CKShare,
        didFinish: @escaping (Result<Void, Error>) -> Void,
        didStopSharing: @escaping () -> Void,
        syncEngine: SyncEngine
      ) {
        self.share = share
        self.didFinish = didFinish
        self.didStopSharing = didStopSharing
        self.syncEngine = syncEngine
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
        withErrorReporting(.sqliteDataCloudKitFailure) {
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
