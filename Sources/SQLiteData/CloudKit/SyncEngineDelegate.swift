#if canImport(CloudKit)
  import CloudKit
  import CustomDump

  /// An interface for observing ``SyncEngine`` events and customizing ``SyncEngine`` behavior.
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public protocol SyncEngineDelegate: AnyObject, Sendable {
    /// An event indicating a change to the device's iCloud account.
    ///
    /// By default, a sync engine will clear out local data when detecting a logout or account
    /// change. To override this behavior, _e.g._ if you want to prompt the user and let them decide
    /// if they want to clear their local data or not, implement this method, and explicitly call
    /// ``SyncEngine/deleteLocalData()`` if/when the data should be cleared.
    ///
    /// For example, an observable model could override this method to set up some alert state:
    ///
    /// ```swift
    /// @MainActor
    /// @Observable
    /// class MySyncEngineDelegate: SyncEngineDelegate {
    ///   var isResetDataAlertPresented = false
    ///
    ///   func syncEngine(
    ///     _ syncEngine: SyncEngine,
    ///     accountChanged changeType: CKSyncEngine.Event.AccountChange.ChangeType
    ///   ) {
    ///     switch changeType {
    ///     case .signOut, .switchAccounts:
    ///       isResetDataAlertPresented = true
    ///     case .signIn:
    ///       break
    ///     }
    ///   }
    /// }
    /// ```
    ///
    /// And then SwiftUI could drive an alert with this state:
    ///
    /// ```swift
    /// struct MyApp: App {
    ///   @State var syncEngineDelegate = MySyncEngineDelegate()
    ///
    ///   init() {
    ///     prepareDependencies {
    ///       try! $0.bootstrapDatabase(syncEngineDelegate: syncEngineDelegate)
    ///     }
    ///   }
    ///
    ///   var body: some Scene {
    ///     WindowGroup {
    ///       MyRootView()
    ///         .alert(
    ///           "Reset local data?",
    ///           isPresented: $syncEngineDelegate.isDeleteLocalDataAlertPresented
    ///         ) {
    ///           Button("Reset", role: .destructive) {
    ///             Task {
    ///               try await syncEngine.deleteLocalData()
    ///             }
    ///           }
    ///         } message: {
    ///           Text(
    ///             """
    ///             You are no longer logged into iCloud. Would you like to reset your local data \
    ///             to the defaults? This will not affect your data in iCloud.
    ///             """
    ///           )
    ///         }
    ///     }
    ///   }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - syncEngine: The sync engine that generates the event.
    ///   - changeType: The iCloud account's change type.
    func syncEngine(
      _ syncEngine: SyncEngine,
      accountChanged changeType: CKSyncEngine.Event.AccountChange.ChangeType
    ) async
      
    
    /// Handle any DatabaseError thrown while attempting to update or insert a record from iCloud
    ///
    /// By default, a sync engine will re-throw this error and end up not syncing the record. To override this behaviour, _e.g._ if your local schema is no longer compatible and you need to apply a custom data migration before inserting, implement this method, and explicitly handle your db updates.
    ///
    /// For example, your `PostalAddress` Table may have in the past used an enum field
    /// for addressType: (residential, commercial etc) but now uses a foreignKey to a
    /// dedicated table of `AddressType`. However the record being restored from iCloud
    /// predates this database migration so it attempting to save the string `residential`
    /// into the `addressType` field rather than the `ID` of the `AddressType` row who's
    /// name is `residential`, overriding this method and handling update/inserts to `PostalAddress`
    /// in this case will allow users to restore historic iCloud data when they re-install
    /// the app even through the schema is no longer backwards compatible:
    ///   .... EXAMPLE here
    ///
    /// Parameters:
    ///   - error: The DatabaseError that was thrown.
    ///   - serverRecord: The CKRecord that is being updated or inserted.
    ///   - columnNames: The column names that contain an update.
    ///   - table: The local database table.
    ///   - Database: The database into which the changes should be written.
    func handleUpsertFromServerRecord<T: Table>(
        error: DatabaseError,
        serverRecord: CKRecord,
        columnNames: some Collection<String>,
        table: T.Type,
        into database: Database
    ) throws
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SyncEngineDelegate {
    public func syncEngine(
      _ syncEngine: SyncEngine,
      accountChanged changeType: CKSyncEngine.Event.AccountChange.ChangeType
    ) async {
      switch changeType {
      case .signOut, .switchAccounts:
        await withErrorReporting {
          try await syncEngine.deleteLocalData()
        }
      case .signIn:
        break
      @unknown default:
        break
      }
    }
      
    public func handleUpsertFromServerRecord<T: Table>(
        error: DatabaseError,
        serverRecord: CKRecord,
        columnNames: some Collection<String>,
        table: T.Type,
        into database: Database
    ) throws {
      throw error
    }
  }
#endif
