#if SharingGRDBSwiftLog
  import Logging

  public typealias Logger = Logging.Logger

  extension Logger {
    public static let syncEngine = Logger(label: "cloudkit.sqlite.data")
  }
#else
  import os

  @available(iOS 14, macOS 11, tvOS 14, watchOS 7, *)
  public typealias Logger = os.Logger

  @available(iOS 14, macOS 11, tvOS 14, watchOS 7, *)
  extension Logger {
    public static let syncEngine = Logger(subsystem: "SQLiteData", category: "CloudKit")
  }
#endif
