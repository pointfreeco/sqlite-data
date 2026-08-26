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
  let directory = URL.temporaryDirectory.appending(
    path: "co.pointfree.SQLiteData",
    directoryHint: .isDirectory
  )
  let processDirectories =
    (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
    ?? []
  for processDirectory in processDirectories {
    guard
      let processIdentifier = pid_t(processDirectory.lastPathComponent),
      kill(processIdentifier, 0) != 0,
      errno == ESRCH
    else { continue }
    try? FileManager.default.removeItem(at: processDirectory)
  }
  return directory.appending(
    path: "\(ProcessInfo.processInfo.processIdentifier)",
    directoryHint: .isDirectory
  )
}()
