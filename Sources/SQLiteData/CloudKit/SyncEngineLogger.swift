#if canImport(CloudKit)
  import CloudKit

  /// A protocol that defines logging requirements for CloudKit sync operations.
  ///
  /// This protocol allows for injectable logging implementations, enabling
  /// custom logging backends while maintaining compatibility with the existing
  /// Apple Logger implementation.
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public protocol SyncEngineLogger: Sendable {
    /// Logs a CloudKit sync event.
    ///
    /// - Parameters:
    ///   - event: The sync engine event to log.
    ///   - databaseScope: The database scope label (e.g., "private", "shared", "global").
    func log(_ event: SyncEngine.Event, databaseScope: String)

    /// Logs a debug message.
    ///
    /// - Parameter message: The debug message to log.
    func debug(_ message: String)
  }
#endif