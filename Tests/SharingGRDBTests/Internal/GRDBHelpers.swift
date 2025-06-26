import GRDB

extension DatabaseWriter {
  // TODO: Should we put this in the main library and use it everywhere?
  //       OR: should we make a version of 'write async' that propagates our task locals across
  //           the escaping boundary?
  func syncWrite<T>(_ updates: (Database) throws -> T) throws -> T {
    try write(updates)
  }
}

extension DatabaseReader {
  func syncRead<T>(_ updates: (Database) throws -> T) throws -> T {
    try read(updates)
  }
}
