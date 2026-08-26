import Foundation
import GRDB

func temporaryDatabasePool(configuration: Configuration = Configuration()) throws -> DatabasePool {
  try FileManager.default.createDirectory(
    at: temporaryDatabaseDirectory, withIntermediateDirectories: true
  )
  return try DatabasePool(
    path: temporaryDatabaseDirectory
      .appending(path: "\(UUID().uuidString).db")
      .path(percentEncoded: false),
    configuration: configuration
  )
}

private let temporaryDatabaseDirectory: URL = {
  atexit {
    try? FileManager.default.removeItem(at: temporaryDatabaseDirectory)
  }
  return URL.temporaryDirectory.appending(
    path: "co.pointfree.SQLiteData/\(ProcessInfo.processInfo.processIdentifier)",
    directoryHint: .isDirectory
  )
}()
