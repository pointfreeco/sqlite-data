import os
import IssueReporting

#if SharingGRDBSwiftLog
  import Logging
#endif

@available(iOS 14, macOS 11, tvOS 14, watchOS 7, *)
public enum Logger: Sendable {
  case osLogger(os.Logger)
  #if SharingGRDBSwiftLog
    case swiftLogger(Logging.Logger)
  #endif
}
