import GRDBSQLite

#if !StrictDecoding
  import ConcurrencyExtras

  let reportedTypeMismatches = LockIsolated<Set<String>>([])
#endif

@usableFromInline
func storageClassName(_ type: Int32) -> String {
  switch type {
  case SQLITE_BLOB: "BLOB"
  case SQLITE_FLOAT: "REAL"
  case SQLITE_INTEGER: "INTEGER"
  case SQLITE_TEXT: "TEXT"
  case SQLITE_NULL: "NULL"
  default: "unknown storage class \(type)"
  }
}
