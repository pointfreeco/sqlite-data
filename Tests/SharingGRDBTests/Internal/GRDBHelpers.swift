import GRDB

extension DatabaseWriter {
  func syncWrite<T>(_ updates: (Database) throws -> T) throws -> T {
    try write(updates)
  }
}

extension DatabaseReader {
  func syncRead<T>(_ updates: (Database) throws -> T) throws -> T {
    try read(updates)
  }
}
