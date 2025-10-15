#if canImport(CloudKit)
  import CloudKit
  import CustomDump

  /// An interface for customizing ``SyncEngine`` behavior.
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public protocol SyncEngineDelegate: AnyObject, Sendable {
    /// An event indicating a change to the device's iCloud account.
    ///
    /// By default, a sync engine will clear out local data when detecting a logout or account
    /// change. To override this behavior, _e.g._ if you want to prompt the user and let them decide
    /// if they want to clear their local data or not, implement this method, and explicitly call
    /// ``SyncEngine/deleteLocalData()`` if/when the data should be cleared.
    ///
    /// - Parameters:
    ///   - syncEngine: The sync engine that generates the event.
    ///   - changeType: The iCloud account's change type.
    func syncEngine(
      _ syncEngine: SyncEngine,
      accountChanged changeType: CKSyncEngine.Event.AccountChange.ChangeType
    ) async
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SyncEngineDelegate {
    public func syncEngine(
      _ syncEngine: SyncEngine,
      accountChanged changeType: CKSyncEngine.Event.AccountChange.ChangeType
    ) async {
      await withErrorReporting {
        try await syncEngine.deleteLocalData()
      }
    }
  }
#endif
