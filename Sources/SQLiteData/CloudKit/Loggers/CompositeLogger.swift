#if canImport(CloudKit)
  import CloudKit

  /// A logger that forwards events to multiple underlying loggers.
  ///
  /// This allows you to use multiple logging backends simultaneously,
  /// such as logging to both Apple's Console.app and a third-party
  /// crash reporting service.
  ///
  /// Example:
  /// ```swift
  /// let logger = CompositeLogger(loggers: [
  ///     AppleLoggerAdapter(),
  ///     MySentryLogger(),
  ///     MyDataDogLogger()
  /// ])
  /// ```
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public struct CompositeLogger: SyncEngineLogger {
    private let loggers: [any SyncEngineLogger]

    /// Creates a new composite logger with the specified loggers.
    ///
    /// - Parameter loggers: An array of loggers to forward events to.
    public init(loggers: [any SyncEngineLogger]) {
      self.loggers = loggers
    }

    public func log(_ event: SyncEngine.Event, databaseScope: String) {
      for logger in loggers {
        logger.log(event, databaseScope: databaseScope)
      }
    }

    public func debug(_ message: String) {
      for logger in loggers {
        logger.debug(message)
      }
    }
  }
#endif