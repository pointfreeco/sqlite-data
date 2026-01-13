#if canImport(CloudKit)
  import CloudKit
  import Dependencies
  import SwiftUI

  #if canImport(UIKit)
    import UIKit
  #endif

  /// A shared record that can be used to present a ``CloudSharingView``.
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
        case shareCouldNotBeCreated
        case recordMetadataNotFound
        case recordNotRoot([ForeignKey])
        case recordTableNotSynchronized
        case recordTablePrivate
        case syncEngineNotRunning
      }

      var recordTableName: String?
      var recordPrimaryKey: String?
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
    /// [`SyncEngine` initializer](<doc:SyncEngine/init(for:tables:privateTables:containerIdentifier:defaultZone:startImmediately:delegate:logger:)>).
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
      guard isRunning
      else {
        throw SharingError(
          reason: .syncEngineNotRunning,
          debugDescription: """
            Sync engine is not running. Make sure engine is running by invoking the 'start()' \
            method, or using the 'startImmediately' argument when initializing the engine.
            """
        )
      }
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
      guard !privateTables.contains(where: { T.self == $0.base })
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
      let lastKnownServerRecord = try await {
        let lastKnownServerRecord =
          try await metadatabase.read { db in
            try SyncMetadata
              .where { $0.recordName.eq(recordName) }
              .select(\._lastKnownServerRecordAllFields)
              .fetchOne(db)
          } ?? nil
        guard let lastKnownServerRecord
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
        return try await container.database(for: lastKnownServerRecord.recordID)
          .record(for: lastKnownServerRecord.recordID)
      }()

      var existingShare: CKShare? {
        get async throws {
          let share = try await metadatabase.read { db in
            try SyncMetadata
              .find(lastKnownServerRecord.recordID)
              .select(\.share)
              .fetchOne(db) ?? nil
          }
          guard let shareRecordID = share?.recordID
          else {
            return nil
          }
          do {
            return try await container.database(for: lastKnownServerRecord.recordID)
              .record(for: shareRecordID) as? CKShare
          } catch let error as CKError where error.code == .unknownItem {
            return nil
          }
        }
      }

      let sharedRecord =
        try await existingShare
        ?? CKShare(
          rootRecord: lastKnownServerRecord,
          shareID: CKRecord.ID(
            recordName: "share-\(recordName)",
            zoneID: lastKnownServerRecord.recordID.zoneID
          )
        )

      configure(sharedRecord)
      let (saveResults, _) = try await container.privateCloudDatabase.modifyRecords(
        saving: [sharedRecord, lastKnownServerRecord],
        deleting: []
      )

      let savedShare = try saveResults.values.compactMap { result in
        let record = try result.get()
        return record.recordID == sharedRecord.recordID ? record as? CKShare : nil
      }
      .first
      let savedRootRecord = try saveResults.values.compactMap { result in
        let record = try result.get()
        return record.recordID == lastKnownServerRecord.recordID ? record : nil
      }
      .first
      guard let savedShare, let savedRootRecord
      else {
        throw SharingError(
          recordTableName: T.tableName,
          recordPrimaryKey: record.primaryKey.rawIdentifier,
          reason: .shareCouldNotBeCreated,
          debugDescription: """
            A 'CKShare' could not be created in iCloud.
            """
        )
      }
      try await userDatabase.write { db in
        try SyncMetadata
          .where { $0.recordName.eq(recordName) }
          .update {
            $0.setLastKnownServerRecord(savedRootRecord)
            $0.share = savedShare
          }
          .execute(db)
      }

      return SharedRecord(container: container, share: savedShare)
    }

    public func unshare<T: PrimaryKeyedTable>(record: T) async throws
    where T.TableColumns.PrimaryKey.QueryOutput: IdentifierStringConvertible {
      let share = try await metadatabase.read { [recordName = record.recordName] db in
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
          """
        )
        return
      }

      try await unshare(share: share)
    }

    func unshare(share: CKShare) async throws {
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

  #if canImport(UIKit) && !os(tvOS) && !os(watchOS)
    /// A view that presents standard screens for adding and removing people from a CloudKit share \
    /// record.
    ///
    /// See <doc:CloudKitSharing#Creating-CKShare-records> for more info.
    @available(iOS 17, macOS 14, tvOS 17, *)
    public struct CloudSharingView: View {
      let sharedRecord: SharedRecord
      let availablePermissions: UICloudSharingController.PermissionOptions
      let didFinish: (Result<Void, Error>) -> Void
      let didStopSharing: () -> Void
      let syncEngine: SyncEngine
      @Dependency(\.context) var context
      @Environment(\.dismiss) var dismiss
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
      public var body: some View {
        if context == .live {
          CloudSharingViewRepresentable(
            sharedRecord: sharedRecord,
            availablePermissions: availablePermissions,
            didFinish: didFinish,
            didStopSharing: didStopSharing,
            syncEngine: syncEngine
          )
        } else {
          NavigationStack {
            Form {
              Section {
                if let title = sharedRecord.share[CKShare.SystemFieldKey.title] as? String {
                  Text(title)
                }
                if let imageData = sharedRecord.share[CKShare.SystemFieldKey.thumbnailImageData]
                  as? Data,
                  let image = UIImage(data: imageData)
                {
                  Image(uiImage: image)
                }
              }
              Section {
                Button("Stop sharing", role: .destructive) {
                  Task {
                    try await syncEngine.unshare(share: sharedRecord.share)
                    try await syncEngine.fetchChanges()
                    dismiss()
                  }
                }
              }
            }
            .navigationTitle("Share")
          }
          .task {
            await withErrorReporting {
              try await syncEngine.fetchChanges()
            }
          }
        }
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, *)
    private struct CloudSharingViewRepresentable: UIViewControllerRepresentable {
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
        Task {
          await withErrorReporting(.sqliteDataCloudKitFailure) {
            try await syncEngine.deleteShare(shareRecordID: share.recordID)
          }
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
