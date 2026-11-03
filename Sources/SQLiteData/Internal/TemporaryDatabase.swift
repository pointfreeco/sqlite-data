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

private let temporaryDatabaseDirectory = URL.temporaryDirectory.appending(
  path: "co.pointfree.SQLiteData",
  directoryHint: .isDirectory
)
