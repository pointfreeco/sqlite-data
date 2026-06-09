#if !EXCLUDE_EXPORTS
  @_exported import Dependencies
  @_exported import StructuredQueriesSQLite

  public import GRDB
  public typealias Configuration = GRDB.Configuration
  public typealias Database = GRDB.Database
  public typealias DatabaseError = GRDB.DatabaseError
  public typealias DatabaseMigrator = GRDB.DatabaseMigrator
  public typealias DatabasePool = GRDB.DatabasePool
  public typealias DatabaseQueue = GRDB.DatabaseQueue
  public typealias DatabaseReader = GRDB.DatabaseReader
  public typealias DatabaseWriter = GRDB.DatabaseWriter
  public typealias ValueObservationScheduler = GRDB.ValueObservationScheduler
#endif
